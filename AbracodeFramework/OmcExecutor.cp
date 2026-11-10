/*
 *  OmcExecutor.cp
 *  OnMyCommand
 *  Mach-O only
 *  Created by Tomasz Kukielka on Thu Aug 21 2003.
 *  Copyright (c) 2003  Abracode, Inc. All rights reserved.
 *
 */

#include "OmcExecutor.h"
#include "ACFString.h"
#include "OMCAppleScriptRunner.h"
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>
#include "OutputWindowHandler.h"
#include "OmcTaskManager.h"
#include "OmcTaskNotification.h"
#include "OnMyCommand.h"
#include "OMCScriptsManager.h"
#include "OMCPrivateConstants.h"
#include "OMCActionUIRemoteHost.h"    // the per-command token
#include "OMCDialog.h"
#include "OMCMainThreadSignal.h"
#include <dispatch/dispatch.h>
#include "OMCDispatchPlatform.h"
#include "OMCAppletSupportURL.h"
#include "OMCPlatformInterpreters.h"
#include <mutex>
#include <algorithm>

void
AddBundlePathToDict(ACFMutableDict &ioDict, CFStringRef inKey, CFBundleRef inBundle)
{
	CFObj<CFURLRef> bundleURL( ::CFBundleCopyBundleURL(inBundle) );
	if(bundleURL != nullptr)
	{
		CFObj<CFStringRef> bundlePath( ::CFURLCopyFileSystemPath(bundleURL, kCFURLPOSIXPathStyle) );
		if(bundlePath != nullptr)
			ioDict.SetValue( inKey, (CFStringRef)bundlePath);//retained
	}
}

static inline
Boolean IsFileExecutable(CFURLRef inFileURL)
{
    if(inFileURL == nullptr)
    {
        return false;
    }
    
    CFObj<CFErrorRef> error;
    CFObj<CFBooleanRef> isExecutableRef;
    if(::CFURLCopyResourcePropertyForKey(inFileURL, kCFURLIsExecutableKey, &isExecutableRef, &error))
    {
        return ((isExecutableRef != nullptr) && ::CFBooleanGetValue(isExecutableRef));
    }
    return false;
}

// The first executable python3 of the platform's candidates (OMCPlatformInterpreters.h), else
// the platform's default one
static inline
const char* FindInstalledPython(void)
{
    const char * const *candidates = OMCPlatformInstalledPythonCandidates();
    for (size_t i = 0; candidates[i] != NULL; i++)
    {
        if (::access(candidates[i], X_OK) == 0)
        {
            return candidates[i];
        }
    }
    
    return OMCPlatformDefaultPython();
}


#pragma mark -

void
OmcExecutor::ReportToManager(OmcTaskManager *inTaskManager, CFIndex inTaskIndex)
{
	if(inTaskManager != nullptr )
	{
		mNotifier->AddObserver( inTaskManager->GetObserver() );
	}
	mTaskIndex = inTaskIndex;
}

bool
OmcExecutor::ExecuteCFString( CFStringRef inCommand, CFStringRef inInputPipe )
{
	this->Retain();//we need to keep us alive during execution. will be balanced by Release() on Finish()

//	DEBUG_CFSTR( inCommand );

	SetInputString( inInputPipe );

	bool endedSynchronously = true;//in error condition finish right away
	OSStatus resultErr = noErr;

	if(inCommand != nullptr)
	{
	    std::string theString = ACFStringToUTF8(inCommand);
        endedSynchronously = Execute( theString.c_str(), resultErr );
	}
	else
	{
        endedSynchronously = Execute( nullptr, resultErr );
	}

	if(endedSynchronously)
    {
        Finish(endedSynchronously, true, resultErr);
    }
    
	return endedSynchronously;
}

void
OmcExecutor::Finish(bool wasSynchronous, bool sendNotification, OSStatus inError)
{
	TRACE_CSTR("OmcExecutor::Finish\n");

    if(sendNotification)
	{
		OmcTaskData notificationData;
		memset( &notificationData, 0, sizeof(notificationData) );
		notificationData.messageID = kOmcTaskFinished;
		notificationData.taskID = GetTaskIndex();
		notificationData.childProcessID = GetChildProcessID();
		notificationData.error = inError;
		notificationData.dataType = kOmcDataTypeBoolean;
		notificationData.dataSize = 0;
		notificationData.data.test = wasSynchronous;
		
		mNotifier->NotifyObservers( &notificationData );
	}
	//else //someone is cancelling and already knows we are dying

	this->Release(); //balance the retain we did in ExecuteCFString
}

void
OmcExecutor::ProcessOutputData(const void *inData, size_t inSize)
{
	try
	{
		OmcTaskData notificationData;
		memset( &notificationData, 0, sizeof(notificationData) );
		notificationData.messageID = kOmcTaskProgress;
		notificationData.taskID = GetTaskIndex();
		notificationData.childProcessID = GetChildProcessID();
		notificationData.error = noErr;
		notificationData.dataType = kOmcDataTypePointer;
		notificationData.dataSize = inSize;
		notificationData.data.ptr = inData;

		mNotifier->NotifyObservers( &notificationData );
	}
	catch(...)
	{
		LOG_CSTR( "OMC->OmcExecutor::ProcessOutputData. Unknown error ocurred\n" );
	}
}

void
OmcExecutor::ProcessOutputString(CFStringRef inString)
{
	try
	{
		OmcTaskData notificationData;
		memset( &notificationData, 0, sizeof(notificationData) );
		notificationData.messageID = kOmcTaskProgress;
		notificationData.taskID = GetTaskIndex();
		notificationData.childProcessID = GetChildProcessID();
		notificationData.error = noErr;
		notificationData.dataType = kOmcDataTypeCFString;
		notificationData.dataSize = 0;
		notificationData.data.cfObj = inString;

		mNotifier->NotifyObservers( &notificationData );
	}
	catch(...)
	{
		LOG_CSTR( "OMC->OmcExecutor::ProcessOutputString. Unknown error ocurred\n" );
	}
}

void
OmcExecutor::ReceiveNotification(void *ioData)
{
	if(ioData == nullptr)
		return;

	OmcTaskData *taskData = (OmcTaskData *)ioData;

	switch(taskData->messageID)
	{
		case kOmcTaskCancel:
		{
			bool wasSynchronous = false;
			if( taskData->dataType == kOmcDataTypeBoolean )
				wasSynchronous = taskData->data.test;
			Finish(wasSynchronous, false, taskData->error);
		}
		break;
			
		default:
		break;
	}
}

#pragma mark -

// Pipe I/O for one child process (Phase 3 step 4, Private/phase3-run-loop-design.md). The two
// dispatch sources run on a private serial queue and only move bytes: output into pendingOutput,
// input from a copy of the input string. Observers, Finish and everything else run on the main
// thread. The I/O queue never touches the executor, whose reference count is not atomic; each
// source and each pending delivery holds the state by a shared_ptr of its own.
// A delivery reaches the main thread through OMCMainThreadSignal (platform code).
struct POpenIO
{
						~POpenIO();

	std::mutex			lock;
	// guarded by lock
	std::string			pendingOutput;				// read, not delivered yet
	bool				outputEnded {false};		// EOF or a read error: nothing more will be read
	OSStatus			readError {noErr};
	bool				deliveryScheduled {false};	// a delivery is on its way
	bool				readSuspended {false};		// too much undelivered output, see kMaxPendingOutput
	bool				stopping {false};			// StopPipeIO has begun: the read source must not suspend again
	std::unique_ptr<OMCMainThreadSignal> delivery;	// destroyed when the I/O stops; signaled only under the lock

	// main thread only
	POpenExecutor *		executor {nullptr};			// nullptr once the executor has finished
	bool				delivering {false};
	std::string			heldIncompleteCharacter;	// taken from pendingOutput, not delivered yet: the start of a character whose other bytes are not read yet

	// set before the sources start, then read-only
	pid_t				pid {-1};
	int					outputFD {-1};
	int					inputFD {-1};
	dispatch_queue_t	queue {nullptr};
	dispatch_source_t	readSource {nullptr};
	dispatch_source_t	writeSource {nullptr};
	dispatch_group_t	descriptorsClosed {nullptr};	// entered per source, left by its cancel handler

	// I/O queue only
	std::string			input;
	size_t				writtenInputBytes {0};
};

POpenIO::~POpenIO()
{
	if(readSource != nullptr)
		dispatch_release(readSource);
	if(writeSource != nullptr)
		dispatch_release(writeSource);
	if(descriptorsClosed != nullptr)
		dispatch_release(descriptorsClosed);
	if(queue != nullptr)
		dispatch_release(queue);
}

// At most this much is read per read event, so a fast writer cannot hold the I/O queue
static const size_t kMaxReadPerEvent = 256 * 1024;
// Above this much undelivered output the read source is suspended until a delivery takes it.
// The pipe used to give this backpressure by itself: nothing was read until the main thread read it.
static const size_t kMaxPendingOutput = 1024 * 1024;
// Observers get the output in pieces of this size, what the CFSocket callback used to read at once,
// so progress parsing sees the same granularity
static const size_t kOutputDeliveryPieceSize = 512;
// At most this much per delivery: the rest goes in the next pass of the run loop, so events, timers
// and other commands are served in between (the CFSocket callback returned after every 512 bytes)
static const size_t kMaxDeliveryPerPass = 64 * 1024;

typedef std::shared_ptr<POpenIO> POpenIOHandle;

// The length of inData without a trailing incomplete UTF-8 character: a lead byte followed by fewer
// continuation bytes than it announces. Observers make each piece into a string from UTF-8, which
// fails for a piece that ends inside a character, and they drop that piece. Bytes that are not UTF-8
// at all are left as they are.
static size_t LengthWithoutIncompleteUTF8Tail(const char *inData, size_t inLength)
{
	size_t continuationCount = 0;
	while( (continuationCount < 3) && (continuationCount < inLength) )
	{
		unsigned char oneByte = (unsigned char)inData[inLength - 1 - continuationCount];
		if( (oneByte & 0xC0) == 0x80 )
		{
			continuationCount++;
			continue;
		}

		size_t characterLength = 1;
		if( (oneByte & 0xE0) == 0xC0 )
			characterLength = 2;
		else if( (oneByte & 0xF0) == 0xE0 )
			characterLength = 3;
		else if( (oneByte & 0xF8) == 0xF0 )
			characterLength = 4;

		if(characterLength > continuationCount + 1)
			return inLength - continuationCount - 1;
		return inLength;
	}
	return inLength;
}

// Called with io->lock held, from either thread. Asks the main thread for a delivery, once until it runs.
static void ScheduleDelivery(const POpenIOHandle &io)
{
	if( !io->deliveryScheduled && (io->delivery != nullptr) )
	{
		io->deliveryScheduled = true;
		io->delivery->Signal();
	}
}

// Main thread. Hands what was read to the observers, in order, at most kMaxDeliveryPerPass per call,
// and finishes the executor after the last bytes. The rest, and what arrives meanwhile, goes in the
// next pass of the run loop (or of the wait), so events, timers and other commands are served between
// batches. A child
// that writes faster than the observers take its output would otherwise keep the main thread here,
// where nothing can cancel it, until it ends. Re-entered from an observer (one that runs the run
// loop), it returns, and the newer bytes follow the older ones in the next pass.
static void DeliverPendingOutput(const POpenIOHandle &io)
{
	if( io->delivering || (io->executor == nullptr) )
		return;

	io->delivering = true;
	ARefCountedObj<POpenExecutor> keepAlive(io->executor, kARefCountRetain);

	std::string output;
	bool ended = false;
	OSStatus error = noErr;
	bool resume = false;
	{
		std::lock_guard<std::mutex> guard(io->lock);
		if(io->pendingOutput.size() > kMaxDeliveryPerPass)
		{
			output.assign(io->pendingOutput, 0, kMaxDeliveryPerPass);
			io->pendingOutput.erase(0, kMaxDeliveryPerPass);
		}
		else
		{
			output.swap(io->pendingOutput);
		}
		io->deliveryScheduled = false;
		ended = io->outputEnded && (io->pendingOutput.size() == 0); // the end comes after the last bytes
		error = io->readError;
		if(io->readSuspended)
		{
			io->readSuspended = false;
			resume = true;
		}
	}

	if(resume)
		dispatch_resume(io->readSource);

	// A character cut by a read, or by the kMaxDeliveryPerPass limit, waits for its other bytes.
	// After the end, an incomplete last character is delivered as it is, in a piece of its own.
	if( !io->heldIncompleteCharacter.empty() )
	{
		output.insert(0, io->heldIncompleteCharacter);
		io->heldIncompleteCharacter.clear();
	}
	if(!ended)
	{
		size_t completeLength = LengthWithoutIncompleteUTF8Tail(output.data(), output.size());
		io->heldIncompleteCharacter.assign(output, completeLength, std::string::npos);
		output.resize(completeLength);
	}

	size_t offset = 0;
	while( (offset < output.size()) && (io->executor != nullptr) )
	{
		size_t pieceLength = std::min(kOutputDeliveryPieceSize, output.size() - offset);
		size_t completeLength = LengthWithoutIncompleteUTF8Tail(output.data() + offset, pieceLength);
		if(completeLength > 0) // 0 only for an incomplete last character after the end, delivered as it is
			pieceLength = completeLength;
		io->executor->ProcessOutputData(output.data() + offset, pieceLength);
		offset += pieceLength;
	}

	if(io->executor != nullptr)
	{
		if(ended)
		{
			io->executor->Finish(false, true, error);
		}
		else
		{
			std::lock_guard<std::mutex> guard(io->lock);
			if( (io->pendingOutput.size() > 0) || io->outputEnded )
			{
				// A re-entered call may have taken the signal for these bytes: ask again
				io->deliveryScheduled = false;
				ScheduleDelivery(io);
			}
		}
	}

	io->delivering = false;
}

// The delivery signal's callbacks; its context is a POpenIOHandle the signal owns
static void DeliverySignaled(void *inContext)
{
	POpenIOHandle io = *static_cast<POpenIOHandle *>(inContext); // a copy: the delivery may stop the I/O and destroy the signal
	DeliverPendingOutput(io);
}

static void DeliveryContextRelease(void *inContext)
{
	delete static_cast<POpenIOHandle *>(inContext);
}

static void ReadEvent(void *inContext)
{
	const POpenIOHandle &io = *static_cast<POpenIOHandle *>(inContext);

	char buffer[16 * 1024];
	std::string chunk;
	bool ended = false;
	OSStatus error = noErr;
	while(chunk.size() < kMaxReadPerEvent)
	{
		ssize_t bytesRead = read(io->outputFD, buffer, sizeof(buffer));
		if(bytesRead > 0)
		{
			chunk.append(buffer, (size_t)bytesRead);
		}
		else if(bytesRead == 0)
		{
			ended = true;
			break;
		}
		else if(errno == EINTR)
		{
			continue;
		}
		else if(errno == EAGAIN)
		{
			break; // all read: the descriptor is non-blocking
		}
		else
		{
			ended = true;
			error = readErr;
			break;
		}
	}

	if( (chunk.size() == 0) && !ended )
		return;

	{
		std::lock_guard<std::mutex> guard(io->lock);
		io->pendingOutput.append(chunk);
		if(ended)
		{
			io->outputEnded = true;
			io->readError = error;
		}
		else if( (io->pendingOutput.size() >= kMaxPendingOutput) && !io->readSuspended && !io->stopping )
		{
			io->readSuspended = true;
			dispatch_suspend(io->readSource);
		}

		ScheduleDelivery(io);
	}

	if(ended)
		dispatch_source_cancel(io->readSource);
}

static void WriteEvent(void *inContext)
{
	POpenIO &io = **static_cast<POpenIOHandle *>(inContext);

	if(io.writtenInputBytes < io.input.size())
	{
		ssize_t bytesWritten = write(io.inputFD, io.input.data() + io.writtenInputBytes, io.input.size() - io.writtenInputBytes);
		if(bytesWritten > 0)
		{
			io.writtenInputBytes += (size_t)bytesWritten;
		}
		else if( (bytesWritten < 0) && ((errno == EAGAIN) || (errno == EINTR)) )
		{
			return; // the pipe is full: the source fires again when there is room
		}
		else
		{
			// 0, or failed for good (EPIPE when the child closed its input): stop writing
			io.writtenInputBytes = io.input.size();
		}
	}

	if(io.writtenInputBytes >= io.input.size())
	{
		std::string().swap(io.input); // free it now, it cannot be written twice
		io.writtenInputBytes = 0;
		dispatch_source_cancel(io.writeSource); // the cancel handler closes the pipe: the child sees the end of its input
	}
}

// A cancel handler is the only place that closes its descriptor, and the last call with its context
static void CloseDescriptorAfterCancel(void *inContext, bool inOutput)
{
	POpenIOHandle *ioBox = static_cast<POpenIOHandle *>(inContext);
	POpenIO &io = **ioBox;
	int fd = inOutput ? io.outputFD : io.inputFD;
	omc_pforget_fd(io.pid, fd);
	(void)close(fd);
	dispatch_group_leave(io.descriptorsClosed);
	delete ioBox; // may be the last reference: nothing after this
}

static void ReadCanceled(void *inContext)
{
	CloseDescriptorAfterCancel(inContext, true);
}

static void WriteCanceled(void *inContext)
{
	CloseDescriptorAfterCancel(inContext, false);
}

static void SetNonBlocking(int inFD)
{
	int fileFlags = fcntl(inFD, F_GETFL);
	if(fileFlags != -1)
		(void)fcntl(inFD, F_SETFL, fileFlags | O_NONBLOCK);
}


#pragma mark -

POpenExecutor::POpenExecutor(const CommandDescription &inCommandDesc, CFMutableDictionaryRef inEnviron)
	: OmcExecutor(),
	mCustomShell(inCommandDesc.popenShell, kCFObjRetain),
	mEnvironmentVariables(inEnviron, kCFObjRetain)
{
   if ((inCommandDesc.executionOptions & kExecutionOption_WaitForTaskCompletion) != 0)
   {
       mWaitForTaskCompletion = true;
   }
}

bool
POpenExecutor::Execute( const char *inCommand, OSStatus &outError )
{
	outError = noErr;
	if(inCommand == nullptr)
		return true;

	TRACE_CSTR( "POpenExecutor. Executing silently now\n" );


	bool wantsToWriteToStdin = (mInputString.length() > 0);

	char ** envList = CreateEnvironmentList( mEnvironmentVariables );

    std::vector<char*> shellArgs;
    std::vector<std::string> customShellStrings;
	if(mCustomShell != nullptr)
	{
		CFIndex itemCount = ::CFArrayGetCount(mCustomShell);
		if(itemCount > 0)
		{
            customShellStrings.resize(itemCount);
			shellArgs.resize(itemCount+1);

			size_t currItemIndex = 0;
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef theValue = ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(mCustomShell, i) );
				if(theValue != nullptr)
				{
                    customShellStrings[currItemIndex] = ACFStringToUTF8(theValue);
                    shellArgs[currItemIndex] = (char*)customShellStrings[currItemIndex].c_str();
					if(shellArgs[currItemIndex] != nullptr)
						currItemIndex++;
				}
			}
            
			shellArgs[currItemIndex] = nullptr;
		}
	}
	
	ProcessOutputString(nullptr); //send one progress notification before we start the execution

	// The handler's ActionUI remote token, when this process serves a bridge. One per spawn,
	// labeled with the command's GUID so that a command's grants can be withdrawn together, and
	// delivered on a descriptor rather than in the environment: a child's environment at exec
	// time is what `ps` reports to any process of the same user (see omc_popen.h). A command
	// that spawns several processes therefore gives each its own token, which is the "this
	// handler, not everything it spawns" rule the bridge's design wanted anyway.
	//
	// This is the place for it because it is the place that has both the environment and the
	// spawn. Nothing is minted when no bridge is running, and a handler then runs exactly as it
	// did before.
	std::string tokenLabel;
	if(mEnvironmentVariables != nullptr)
	{
		CFStringRef commandGUID = ACFType<CFStringRef>::DynamicCast(
								::CFDictionaryGetValue(mEnvironmentVariables, CFSTR("OMC_CURRENT_COMMAND_GUID")) );
		if(commandGUID != nullptr)
			tokenLabel = ACFStringToUTF8(commandGUID);
	}

	char tokenBuffer[kOMCActionUIRemoteTokenBufferSize];
	const char *token = nullptr;
	if( (tokenLabel.length() > 0) && OMCMintActionUIRemoteToken(tokenLabel.c_str(), tokenBuffer, sizeof(tokenBuffer)) )
	{
		token = tokenBuffer;
	}
	else if( OMCGetActionUIRemoteEndpoint() != nullptr )
	{
		// A bridge is running and this handler is going to be refused with 1006. Silence here
		// would be indistinguishable from "no bridge", which is the ordinary case, and the
		// handler's own error says only that the host refused it.
		LOG_CSTR( "OMC->POpenExecutor::Execute. the ActionUI bridge is running but no token could be minted%s; this handler cannot use it\n",
					(tokenLabel.length() > 0) ? "" : " (the command has no GUID)" );
	}

	outError = omc_popen_with_token(	inCommand, shellArgs.data(), envList,
							wantsToWriteToStdin ? (kOMCPopenRead | kOMCPopenWrite) : kOMCPopenRead,
							token, kOMCActionUIRemoteTokenFD,
							&mChildProcessInfo );

	// The child has it, or the spawn failed and nobody does. Either way this copy has no further
	// use, and a secret with no further use should not sit in a stack frame. Not memset: nothing
	// reads the buffer afterwards, so that would be a dead store the optimizer may delete.
	OMCSecureClear(tokenBuffer, sizeof(tokenBuffer));

	ReleaseEnviron( envList );
	
	if(outError == 0)
	{
		if(wantsToWriteToStdin)
		{
			//set SIGPIPE handler to IGNORE so the host app will not be forced quit if writing to broken pipe happens
			//should we bother remembering the state and restoring after command execution?
			{
				struct sigaction signalState;
				int err = sigaction(SIGPIPE, nullptr, &signalState);
				if (err == 0)
				{
					signalState.sa_handler = SIG_IGN;
					err = sigaction(SIGPIPE, &signalState, nullptr);
				}
			}
		}

		if( !StartPipeIO(wantsToWriteToStdin) )
		{
			outError = ioErr; // nothing would read the child's output; Finish closes the pipes and waits for it
			return true;
		}

        if (mWaitForTaskCompletion)
        {
            // keep us alive for the duration of the wait
            // we may end up with Finish() while waiting, get released and dealloced
            ARefCountedObj<POpenExecutor> localRetain(this, kARefCountRetain);

            TRACE_CSTR("POpenExecutor waiting for child process execution to finish\n");
            WaitForTaskCompletion();

            // Even if we were waiting here, we don't consider this case
            // a blocking execution for the purpose of OmcHostTaskManager::RunNext()
            // With popen async execution the OMCHostTaskManager should receive NoteTaskEnded() and call RunNext()
            // The wait returns only once the executor has finished, so this is false: true would make the
            // caller call Finish() again, which over-releases and crashes
            return !mHasFinished;
        }

		return false;
	}

	return true; // error condition. finished
}

// Starts reading the child's output and, when there is input, writing it. Main thread.
bool
POpenExecutor::StartPipeIO(bool inWritesInput)
{
	POpenIOHandle io = std::make_shared<POpenIO>();
	io->executor = this;
	io->pid = mChildProcessInfo.pid;
	io->outputFD = mChildProcessInfo.outputFD;
	io->inputFD = inWritesInput ? mChildProcessInfo.inputFD : -1;
	if( (io->outputFD < 0) || (inWritesInput && (io->inputFD < 0)) )
		return false;

	// StopPipeIO waits on the main thread for this queue's cancel handlers, so the queue runs at the main
	// thread's class where the platform has classes (OMCDispatchPlatform.h). The queue only moves bytes.
	io->queue = OMCCreateSerialQueueForMainThreadWaits("com.abracode.OMC.POpenExecutor.io");
	io->descriptorsClosed = dispatch_group_create();
	if( (io->queue == nullptr) || (io->descriptorsClosed == nullptr) )
		return false;

	// Non-blocking on our ends only (O_NONBLOCK belongs to the open file description, and the child's
	// ends are other ones): a read event reads what is there, and a write takes what fits instead of
	// waiting for the child to read, which deadlocked when the child wrote output while it read
	// (the stdin fix, OMCStandardInputTests).
	SetNonBlocking(io->outputFD);
	io->readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)io->outputFD, 0, io->queue);
	if(inWritesInput)
	{
		SetNonBlocking(io->inputFD);
		io->input.swap(mInputString);
		io->writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, (uintptr_t)io->inputFD, 0, io->queue);
	}

	bool sourcesCreated = (io->readSource != nullptr) && (!inWritesInput || (io->writeSource != nullptr));
	if(sourcesCreated)
		io->delivery = OMCMainThreadSignal::Create(DeliverySignaled, new POpenIOHandle(io), DeliveryContextRelease);

	if( !sourcesCreated || (io->delivery == nullptr) )
	{
		// A source must be activated before its last release; with no handlers, nothing runs.
		// The descriptors stay with omc_popen, and Finish closes them.
		if(io->readSource != nullptr)
		{
			dispatch_source_cancel(io->readSource);
			dispatch_resume(io->readSource);
		}
		if(io->writeSource != nullptr)
		{
			dispatch_source_cancel(io->writeSource);
			dispatch_resume(io->writeSource);
		}
		mInputString.swap(io->input);
		return false;
	}

	dispatch_set_context(io->readSource, new POpenIOHandle(io));
	dispatch_source_set_event_handler_f(io->readSource, ReadEvent);
	dispatch_source_set_cancel_handler_f(io->readSource, ReadCanceled);
	dispatch_group_enter(io->descriptorsClosed);

	if(io->writeSource != nullptr)
	{
		dispatch_set_context(io->writeSource, new POpenIOHandle(io));
		dispatch_source_set_event_handler_f(io->writeSource, WriteEvent);
		dispatch_source_set_cancel_handler_f(io->writeSource, WriteCanceled);
		dispatch_group_enter(io->descriptorsClosed);
	}

	mIO = io;
	dispatch_resume(io->readSource);
	if(io->writeSource != nullptr)
		dispatch_resume(io->writeSource);
	return true;
}

// Stops both sources and returns once their cancel handlers have closed the descriptors, so the
// child sees the pipes closed before omc_pclose waits for it. Main thread; safe to call again.
void
POpenExecutor::StopPipeIO()
{
	POpenIOHandle io = mIO;
	if(io == nullptr)
		return;

	io->executor = nullptr; // no more deliveries to us

	bool resume = false;
	std::unique_ptr<OMCMainThreadSignal> delivery;
	{
		std::lock_guard<std::mutex> guard(io->lock);
		// A read event already running would otherwise suspend the source after this check, and a
		// suspended source never runs its cancel handler: the wait below would never return
		io->stopping = true;
		if(io->readSuspended)
		{
			io->readSuspended = false;
			resume = true;
		}
		delivery.swap(io->delivery); // the I/O queue signals it only under the lock
	}

	// Its context holds the state, so it must go (a cycle otherwise); also when called from its callback
	delivery.reset();

	dispatch_source_cancel(io->readSource);
	if(resume)
		dispatch_resume(io->readSource); // a suspended source runs its cancel handler only once resumed
	if(io->writeSource != nullptr)
		dispatch_source_cancel(io->writeSource);

	// The handlers on the I/O queue never wait for the main thread, so this cannot deadlock
	dispatch_group_wait(io->descriptorsClosed, DISPATCH_TIME_FOREVER);
	mChildProcessInfo.outputFD = -1;
	mChildProcessInfo.inputFD = -1;
}

// WAIT_FOR_TASK_COMPLETION: returns once the executor has finished. Main thread.
void
POpenExecutor::WaitForTaskCompletion()
{
	POpenIOHandle io = mIO;
	if(io == nullptr)
		return;

	// What a pass runs is platform code (OMCMainThreadSignal::WaitPass): on macOS the run loop's default
	// mode, as released (owner, 2026-11-06), on Linux only the engine's own work. Neither spins: a pass
	// sleeps until something arrives, at most 0.1 s.
	// Until the executor finishes, which it does after the last of the output: ending earlier would
	// leave the output unread, and Execute's caller would then finish the command without it.
	while(!mHasFinished)
	{
		OMCMainThreadSignal::WaitPass(0.1);
		DeliverPendingOutput(io); // usually done by the delivery signal during the pass already
		OMCDialog::ServicePendingMessages(); // what the script sends its dialog lands during the wait
	}
}

POpenExecutor::~POpenExecutor()
{
	TRACE_CSTR("POpenExecutor::~POpenExecutor()\n");
	//just to be safe, if it did not go the normal way through Finish()
	StopPipeIO();
	(void)omc_pclose( mChildProcessInfo.pid );
}

void
POpenExecutor::Finish(bool wasSynchronous, bool sendNotification, OSStatus inError)
{
    // check if Finish() has already been called
    // normally in async execution it is called just once when the output ends
    // in synchronous execution it is also called after the task ends so let's return early

    if(mHasFinished)
    {
        return;
    }
    mHasFinished = true;

	TRACE_CSTR("POpenExecutor::Finish\n");

	StopPipeIO();

	int pipeResult = omc_pclose( mChildProcessInfo.pid );

    if(mWaitForTaskCompletion)
    {
        mWaitForTaskCompletion = false;

        // even if we wait for the task completion
        // we don't consider popen a synchronous execution
        // this matters because the logic for determining if all tasks finished is different
        // for synchronous (blocking) and asynchronouse execution
        // marking this a sync call here prevents sending kOmcAllTasksFinished to observers
        // so we keep wasSynchronous = false
    }

	OmcExecutor::Finish(wasSynchronous, sendNotification, (OSStatus)pipeResult );
}

void
POpenExecutor::SetInputString( CFStringRef inInputPipe )
{
	mInputString = ACFStringToUTF8(inInputPipe);
}

#pragma mark -


POpenWithOutputExecutor::POpenWithOutputExecutor(const CommandDescription &inCommandDesc,
												CFStringRef inDynamicName,
												CFBundleRef inExternBundleRef,
												CFMutableDictionaryRef inEnviron)
	: POpenExecutor(inCommandDesc, inEnviron),
	mSettingsDict(inCommandDesc.outputWindowOptions, kCFObjRetain),
	mCommandName(inCommandDesc.name, kCFObjRetain),
	mDynamicCommandName(inDynamicName, kCFObjRetain),
	mExternBundleRef(inExternBundleRef, kCFObjRetain),
	mLocalizationTableName(inCommandDesc.localizationTableName, kCFObjRetain)
{
}

POpenWithOutputExecutor::~POpenWithOutputExecutor()
{
}

							
bool
POpenWithOutputExecutor::Execute( const char *inCommand, OSStatus &outError )
{
	outError = noErr;
	if(inCommand == nullptr)
		return true;

	TRACE_CSTR("POpenWithOutputExecutor. Executing now\n" );

	OutputWindowHandler *theOutput = new OutputWindowHandler( mSettingsDict, mCommandName, mDynamicCommandName, mExternBundleRef, mLocalizationTableName);
	mNotifier->AddObserver( theOutput->GetObserver() );
	return POpenExecutor::Execute(inCommand, outError);
}

void
POpenWithOutputExecutor::Finish(bool wasSynchronous, bool sendNotification, OSStatus inError)
{
	POpenExecutor::Finish(wasSynchronous, sendNotification, inError);
}

#pragma mark -

// sh is the default fallback for any script with no extension, or one the platform has no
// interpreter for (OMCPlatformInterpreters.h)
static CFStringRef
DefaultShell()
{
	return CFSTR("/bin/sh");
}

// Returns the path to the embedded python3 binary if present, nullptr otherwise.
// the expected location for bundled Python is Library/Python/ in the applet's support files folder
// (OMCApplet.app/Contents/Library/Python/ on macOS; OMCAppletSupportURL.h)
// A relocatable Python 3 distribution suitable for embeddeding in the applets can be produced with this infra:
// https://github.com/abra-code/Python-Embedding
static CFStringRef GetEmbeddedPythonPath()
{
    static CFStringRef sEmbeddedPythonPath = nullptr;
    static dispatch_once_t sOnce;
    dispatch_once_f(&sOnce, nullptr, [](void *) {
        CFObj<CFURLRef> pythonURL( OMCCopyAppletSupportURL(CFSTR("Library/Python/bin/python3"), false) );
        if((pythonURL != nullptr) && IsFileExecutable(pythonURL))
            sEmbeddedPythonPath = CreatePathFromCFURL(pythonURL, kEscapeNone);
    });
    return sEmbeddedPythonPath;
}

static CFStringRef GetPythonToolPath()
{
    static CFStringRef sPythonPath = nullptr;

    static dispatch_once_t sOnce;
    dispatch_once_f(&sOnce, nullptr, [](void *) {
        sPythonPath = GetEmbeddedPythonPath();

        // Embedded Python 3 distribution not found
        // The command assumes Python is installed on deployment machine
        // Let's find the location, if any
        if(sPythonPath == nullptr)
        {
            const char *python_path = FindInstalledPython();
            sPythonPath = ::CFStringCreateWithCString(kCFAllocatorDefault, python_path, kCFStringEncodingUTF8);
        }
    });

    return sPythonPath;
}

static CFStringRef
PrependPythonBinDirToEnvironmentPATH(CFStringRef pythonPath)
{
    // Extract the directory from the python path by removing the last path component
    CFObj<CFURLRef> pythonURL = ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                                pythonPath,
                                                                kCFURLPOSIXPathStyle,
                                                                false);
    if (pythonURL == NULL)
    {
        return NULL;
    }
    
    CFObj<CFURLRef> binDirURL = ::CFURLCreateCopyDeletingLastPathComponent(kCFAllocatorDefault, pythonURL);
    
    if (binDirURL == NULL)
    {
        return NULL;
    }
    
    CFObj<CFStringRef> binDir = ::CFURLCopyFileSystemPath(binDirURL, kCFURLPOSIXPathStyle);
    
    if (binDir == NULL)
    {
        return NULL;
    }
    
    // Create the new PATH by prepending binDir. With no PATH, or an empty one, binDir alone: "binDir:"
    // would end in an empty entry, which the shell takes as the current folder.
    CFObj<CFStringRef> currentPath;
    const char *currentPathText = ::getenv("PATH");
    if ((currentPathText != nullptr) && (currentPathText[0] != '\0'))
    {
        currentPath.Adopt( ::CFStringCreateWithCString(kCFAllocatorDefault, currentPathText, kCFStringEncodingUTF8) );
        if (currentPath == nullptr)
            return NULL; // not UTF-8: leave PATH as it is rather than drop the rest of it
    }

    CFMutableStringRef newPath = ::CFStringCreateMutable(kCFAllocatorDefault, 0);
    ::CFStringAppend(newPath, binDir);
    if (currentPath != nullptr)
    {
        ::CFStringAppend(newPath, CFSTR(":"));
        ::CFStringAppend(newPath, currentPath);
    }
    
    return newPath;
}

static CFStringRef
PrependBundlePackagesToEnvironmentPYTHONPATH()
{
    CFObj<CFURLRef> packagesURL( OMCCopyAppletSupportURL(CFSTR("Library/Packages"), true) );
    if (packagesURL == nullptr)
        return nullptr;

    CFObj<CFBooleanRef> isDir;
    if (!::CFURLCopyResourcePropertyForKey(packagesURL, kCFURLIsDirectoryKey, &isDir, nullptr)
        || (isDir == nullptr) || !::CFBooleanGetValue(isDir))
        return nullptr;

    CFObj<CFStringRef> packagesPath = ::CFURLCopyFileSystemPath(packagesURL, kCFURLPOSIXPathStyle);
    if (packagesPath == nullptr)
        return nullptr;

    CFObj<CFStringRef> existing;
    const char *existingPythonPath = ::getenv("PYTHONPATH");
    if (existingPythonPath != nullptr && existingPythonPath[0] != '\0')
    {
        // Not UTF-8 (existing stays NULL): the applet's packages alone. Unlike PATH, whose other
        // folders everything the script runs needs, what the applet's Python needs is its packages.
        existing.Adopt( ::CFStringCreateWithCString(kCFAllocatorDefault, existingPythonPath, kCFStringEncodingUTF8) );
    }

    CFMutableStringRef newPythonPath = ::CFStringCreateMutable(kCFAllocatorDefault, 0);
    ::CFStringAppend(newPythonPath, packagesPath);
    if (existing != nullptr)
    {
        ::CFStringAppend(newPythonPath, CFSTR(":"));
        ::CFStringAppend(newPythonPath, existing);
    }
    return newPythonPath;
}

static inline
CFStringRef GetShellFromScriptExtension(CFStringRef inExt, CFMutableDictionaryRef envVariables)
{
	if(inExt == nullptr)
		return DefaultShell();

    // Export Python env vars whenever the app bundles its own Python distribution,
    // regardless of the script type being executed (e.g. a .sh script calling python3).
    CFStringRef embeddedPythonPath = GetEmbeddedPythonPath();
    if(embeddedPythonPath != nullptr)
    {
        // add pyc cache location to env vars.
        // Per-user (macOS: /var/folders/<...>/T/Pyc, mode 0700; Linux: <cache>/omc/Pyc in a 0700
        // folder) rather than the fixed /tmp/Pyc this used to be, so one account's bytecode cache
        // is no longer a directory another account can create first. For a sandboxed macOS host
        // it lands in that container's tmp, writable where /tmp was not.
        const char *pycachePrefix = OMCGetPythonPycachePrefix();
        if(pycachePrefix != nullptr)
        {
            CFObj<CFStringRef> pycachePrefixStr( ::CFStringCreateWithCString(kCFAllocatorDefault, pycachePrefix, kCFStringEncodingUTF8) );
            if(pycachePrefixStr != nullptr)
                ::CFDictionaryAddValue(envVariables, CFSTR("PYTHONPYCACHEPREFIX"), pycachePrefixStr);
        }
        CFObj<CFStringRef> newPaths = PrependPythonBinDirToEnvironmentPATH(embeddedPythonPath);
        if (newPaths != NULL)
            ::CFDictionaryAddValue(envVariables, CFSTR("PATH"), newPaths);
        CFObj<CFStringRef> newPythonPath = PrependBundlePackagesToEnvironmentPYTHONPATH();
        if (newPythonPath != NULL)
            ::CFDictionaryAddValue(envVariables, CFSTR("PYTHONPATH"), newPythonPath);
    }

	if(kCFCompareEqualTo == ::CFStringCompare(inExt, CFSTR("py"), kCFCompareCaseInsensitive))
	{
		if(embeddedPythonPath == nullptr)
		{
			// external Python: only prepend its bin dir to PATH so the right python3 is found
			CFStringRef pythonToolPath = GetPythonToolPath();
			CFObj<CFStringRef> newPaths = PrependPythonBinDirToEnvironmentPATH(pythonToolPath);
			if (newPaths != NULL)
				::CFDictionaryAddValue(envVariables, CFSTR("PATH"), newPaths);
		}
		return GetPythonToolPath();
	}

	size_t interpreterCount = 0;
	const OMCExtensionAndInterpreter *interpreters = OMCPlatformInterpreters(&interpreterCount);
	for(size_t i = 0; i < interpreterCount; i++)
	{
		if(kCFCompareEqualTo == ::CFStringCompare(inExt, interpreters[i].extension, kCFCompareCaseInsensitive))
			return interpreters[i].interpreter;
	}

	return DefaultShell();
}

static std::string CreateScriptPathAndShell(
								CFBundleRef inExternBundle,
                                CFStringRef inCommandName,
								CFStringRef inCommandID,
								CFObj<CFArrayRef> &ioCustomShell,
                                CFMutableDictionaryRef envVariables,
								const char *inCommand)
{
	CFObj<CFStringRef> scriptFilePath;

    CFBundleRef hostBundle = inExternBundle; // formally supporting extern bundles
    if(hostBundle == nullptr)
    {
        hostBundle = CFBundleGetMainBundle(); // in most cases it will be just applet bundle
    }

    // this should not happen, but...
    if(inCommandID == nullptr)
    {
        assert(inCommandID != nullptr);
        inCommandID = kOMCTopCommandID;
    }
    
    // for historical reasons commandID = 'top!' is assigned early for the main command
    // in the command group without explicit COMMAND_ID
    // it is problematic for multiple command groups in one plist - the comamnd ids are not unique anymore
    // however, for newer shell script execution, it makes more sense to look for for something
    // like a CommandName.main.sh or main.sh script
    if(kCFCompareEqualTo == CFStringCompare(inCommandID, kOMCTopCommandID, 0))
    {
        if(inCommandName != nullptr)
        {
            CFObj<CFStringRef> scriptName = CFStringCreateWithFormat(kCFAllocatorDefault,
                                                                   nullptr,
                                                                   CFSTR("%@.main"),
                                                                   inCommandName);
            scriptFilePath.Adopt(OMCGetScriptPath(hostBundle, scriptName), kCFObjRetain);
        }
        
        if(scriptFilePath == nullptr)
        { // fall back to "main" if we could not find a script for "CommandName.main"
            inCommandID = CFSTR("main");
        }
    }
    
    if(scriptFilePath == nullptr)
    {
        // the idea is to look for file of the same name as command ID within Applet.app/Contents/Resources/Scripts
        scriptFilePath.Adopt(OMCGetScriptPath(hostBundle, inCommandID), kCFObjRetain);
    }

	if(scriptFilePath == nullptr)
	{
		LOG_CSTR( "OMC->CreateScriptPathAndShell: unable to find script file\n" );
		return std::string();
	}

	if(ioCustomShell == nullptr)
	{ // the expected situation, we provide the shell mapping from script extension
		CFObj<CFStringRef> extension = CopyFilenameExtension(scriptFilePath);
		CFMutableArrayRef newShellArray = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
		ioCustomShell.Adopt(newShellArray, kCFObjDontRetain);
		CFStringRef shellPath = GetShellFromScriptExtension(extension, envVariables); //always returns non-null shell
		CFArrayAppendValue(newShellArray, (const void *)shellPath);
	}

	return ACFStringToUTF8(scriptFilePath); //null-safe
}

POpenScriptFileExecutor::POpenScriptFileExecutor(
							const CommandDescription &inCommandDesc,
							CFBundleRef inExternBundleRef,
							CFMutableDictionaryRef inEnviron)
	: POpenExecutor(inCommandDesc, inEnviron),
	mCommandID(inCommandDesc.commandID, kCFObjRetain),
	mExternBundleRef(inExternBundleRef, kCFObjRetain)
{
    if(!inCommandDesc.nameIsDynamic &&
       (inCommandDesc.name != NULL) &&
       ::CFArrayGetCount(inCommandDesc.name) > 0)
    {
        CFTypeRef firstItem = CFArrayGetValueAtIndex(inCommandDesc.name, 0);
        CFStringRef nameStr = ACFType<CFStringRef>::DynamicCast(firstItem);
        mCommandName.Adopt(nameStr, kCFObjRetain);
    }
}

bool
POpenScriptFileExecutor::Execute( const char *inCommand, OSStatus &outError )
{
	std::string pathStr = CreateScriptPathAndShell(mExternBundleRef, mCommandName, mCommandID, mCustomShell, mEnvironmentVariables, inCommand);
	return POpenExecutor::Execute(pathStr.c_str(), outError);
}



POpenScriptFileWithOutputExecutor::POpenScriptFileWithOutputExecutor(
										const CommandDescription &inCommandDesc,
										CFStringRef inDynamicName,
										CFBundleRef inExternBundleRef,
										CFMutableDictionaryRef inEnviron)
	: POpenWithOutputExecutor(inCommandDesc, inDynamicName, inExternBundleRef, inEnviron),
	mCommandID(inCommandDesc.commandID, kCFObjRetain)
{
    if(!inCommandDesc.nameIsDynamic &&
       (inCommandDesc.name != NULL) &&
       ::CFArrayGetCount(inCommandDesc.name) > 0)
    {
        CFTypeRef firstItem = CFArrayGetValueAtIndex(inCommandDesc.name, 0);
        CFStringRef nameStr = ACFType<CFStringRef>::DynamicCast(firstItem);
        mCommandName.Adopt(nameStr, kCFObjRetain);
    }
}

bool
POpenScriptFileWithOutputExecutor::Execute( const char *inCommand, OSStatus &outError )
{
	std::string pathStr = CreateScriptPathAndShell(mExternBundleRef, mCommandName, mCommandID, mCustomShell, mEnvironmentVariables, inCommand);
	return POpenWithOutputExecutor::Execute( pathStr.c_str(), outError );
}


#pragma mark -

bool
SystemExecutor::Execute( const char *inCommand, OSStatus &outError )
{
	outError = noErr;
	if(inCommand != nullptr)
	{
		ProcessOutputString(nullptr); //send one progress notification before we start non-stoppable execution

		TRACE_CSTR("SystemExecutor. Executing silently now\n" );
		// Known limit, accepted (exe_system is not worth reimplementing): system() passes this
		// process's signal dispositions on, so after any command that wrote a child's standard
		// input (the engine then ignores SIGPIPE, see POpenExecutor::Execute) the command runs with
		// SIGPIPE ignored, where omc_popen gives every other command's child the default.
		outError = (OSStatus) system(inCommand);
		if(outError != noErr)
		{
			LOG_CSTR( "OMC->SystemExecutor::Execute. system() returned error = %d\n", (int)outError );
		}
	}
	return true; // ended synchronously. system() is blocking
}

#pragma mark -

AppleScriptExecutor::AppleScriptExecutor(const CommandDescription &inCommandDesc,
										CFStringRef inDynamicName,
										CFBundleRef inExternBundleRef,
										Boolean useOutputWindow)
	: OmcExecutor(),
	mSettingsDict(inCommandDesc.outputWindowOptions, kCFObjRetain),
	mCommandName(inCommandDesc.name, kCFObjRetain),
	mDynamicCommandName(inDynamicName, kCFObjRetain),
	mExternBundleRef(inExternBundleRef, kCFObjRetain),
	mLocalizationTableName(inCommandDesc.localizationTableName, kCFObjRetain),
	mUseOutput(useOutputWindow)
{
}

AppleScriptExecutor::~AppleScriptExecutor()
{
}


bool
AppleScriptExecutor::ExecuteCFString( CFStringRef inCommand, CFStringRef inInputPipe )
{
	this->Retain();//we need to keep us alive during execution. will be balanced by Release() on Finish()

	if(inCommand == nullptr)
	{
		Finish(true, true, noErr);
		return true;
	}

	ProcessOutputString(nullptr); //send one progress notification before we start non-stoppable AS execution

	CFObj<CFStringRef> resultString;
	OSStatus osaErr = OMCRunAppleScript(inCommand, AppleScriptExecutor::StillRunning, this, &resultString);

	if(mUseOutput)
	{
		OutputWindowHandler *theOutput = new OutputWindowHandler(mSettingsDict, mCommandName, mDynamicCommandName, mExternBundleRef, mLocalizationTableName);
		if(theOutput != nullptr)
		{
			mNotifier->AddObserver( theOutput->GetObserver() );
			theOutput->SetText(resultString, true, (osaErr == noErr) );
		}
	}

	ProcessOutputString(resultString);//just in case there is a progress or end notification we need to pass the result
	Finish(true, true, osaErr);//AppleScript execution is synchronous so we finish when it is done
	return true;
}

// While the script runs: let our progress indicator know we are still alive
void
AppleScriptExecutor::StillRunning(void *inContext)
{
	AppleScriptExecutor *theThis = (AppleScriptExecutor *)inContext;
	if(theThis != nullptr)
		theThis->ProcessOutputString(nullptr);
}

/*
void
AppleScriptExecutor::Finish()
{
	if(mOutput != nullptr)
		mOutput->SetExecutor(nullptr);

	OmcExecutor::Finish();
}
*/

#pragma mark -

//use ReleaseEnviron to free the result
char **
CreateEnvironmentList(CFDictionaryRef inEnviron)
{
	if(inEnviron == nullptr)
		return nullptr;

	CFIndex itemCount = ::CFDictionaryGetCount(inEnviron);
	if(itemCount == 0)
		return nullptr;

    std::vector<void *> keyList(itemCount);
    std::vector<void *> valueList(itemCount);
    std::vector<std::string> keyStrings(itemCount);
    std::vector<std::string> valueStrings(itemCount);

	::CFDictionaryGetKeysAndValues(inEnviron, (const void **)keyList.data(), (const void **)valueList.data());
	size_t currItemIndex = 0;
	for(size_t i = 0; i < itemCount; i++)
	{
		CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[i] );
		CFStringRef theValue = ACFType<CFStringRef>::DynamicCast( valueList[i] );
		keyList[i] = nullptr;
		valueList[i] = nullptr;

		if( (theKey != nullptr) && (theValue != nullptr) )
		{
			keyStrings[currItemIndex] = ACFStringToUTF8(theKey);
            if(keyStrings[currItemIndex].length() > 0)
            {
                keyList[currItemIndex] = (void *)keyStrings[currItemIndex].c_str();
                valueStrings[currItemIndex] = ACFStringToUTF8(theValue);
                valueList[currItemIndex] = (void *)valueStrings[currItemIndex].c_str();
                currItemIndex++;
            }
		}
	}
	
	char ** newEnviron = CreateEnviron( (char **)keyList.data(), (char **)valueList.data(), currItemIndex );
	return newEnviron;
}


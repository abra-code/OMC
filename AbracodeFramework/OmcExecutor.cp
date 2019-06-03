/*
 *  OmcExecutor.cp
 *  OnMyCommandCM
 *  Mach-O only
 *  Created by Tomasz Kukielka on Thu Aug 21 2003.
 *  Copyright (c) 2003  Abracode, Inc. All rights reserved.
 *
 */

#include "OmcExecutor.h"
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>
#include "CMUtils.h"
#include "OutputWindowHandler.h"
#include "StAEDesc.h"
#include "OmcTaskManager.h"
#include "OmcTaskNotification.h"
#include <sys/socket.h>
#include "OnMyCommand.h"

static char oneLine[512];
static char fileName[256];

void
AddBundlePathToDict(ACFMutableDict &ioDict, CFStringRef inKey, CFBundleRef inBundle)
{
	CFObj<CFURLRef> bundleURL( ::CFBundleCopyBundleURL(inBundle) );
	if(bundleURL != NULL)
	{
		CFObj<CFStringRef> bundlePath( ::CFURLCopyFileSystemPath(bundleURL, kCFURLPOSIXPathStyle) );
		if(bundlePath != NULL)
			ioDict.SetValue( inKey, (CFStringRef)bundlePath);//retained
	}
}

#pragma mark -

void
OmcExecutor::ReportToManager(OmcTaskManager *inTaskManager, CFIndex inTaskIndex)
{
	if(inTaskManager != NULL )
	{
		mTaskManagerID.Adopt( inTaskManager->GetUniqueID(), kCFObjRetain );
		mNotifier->AddObserver( inTaskManager->GetObserver() );
	}
	mTaskIndex = inTaskIndex;
}

bool
OmcExecutor::ExecuteCFString( CFStringRef inCommand, CFStringRef inInputPipe )
{
	this->Retain();//we need to keep us alive during execution. will be balanced by Release() on Finish()

	if(inCommand == NULL)
	{
		Finish(true, true, noErr);
		return true;
	}

	OSStatus err = noErr;

#ifndef BUILD_DEPUTY
	if(mUseDeputy)
	{
		ACFMutableDict deputyInfo;
		deputyInfo.SetValue( CFSTR("COMMAND"), inCommand);
		deputyInfo.SetValue( CFSTR("STANDARD_INPUT_PIPE"), inInputPipe);
		deputyInfo.SetValue( CFSTR("TASK_MANAGER_ID"), (CFStringRef)mTaskManagerID );
		
		deputyInfo.SetValue( CFSTR("TASK_INDEX"), (CFIndex)mTaskIndex );
		
		CreateDeputyData( deputyInfo );
        CFObj<CFDataRef> deputyData(CFPropertyListCreateData(kCFAllocatorDefault, (CFMutableDictionaryRef)deputyInfo, kCFPropertyListBinaryFormat_v1_0, 0, nullptr));
		err = DelegateTaskToDeputy(deputyData);
		if(err == noErr)
			return false;
	}
#endif

//	DEBUG_CFSTR( inCommand );
	
	bool finishedSynchronously = true;//in error condition finish right away
    std::string theString = CMUtils::CreateUTF8StringFromCFString(inCommand);

	OSStatus resultErr = noErr;

	SetInputString( inInputPipe );
	finishedSynchronously = Execute( theString.c_str(), resultErr );

	if(finishedSynchronously)
		Finish(finishedSynchronously, true, resultErr);
	
	return finishedSynchronously;
}

void
OmcExecutor::Finish(bool wasSynchronous, bool sendNotification, OSStatus inError)
{
	TRACE_CSTR("OmcExecutor::Finish\n");
/*
	if(mIsFinishing)
	{
		TRACE_CSTR("OmcExecutor::Finish - reentry prevented\n");
		return;//prevent re-entry caused by circular notifications
	}

	mIsFinishing = true;
*/

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

//the deputy itself cannot delegate the task to another deputy
//so the following code is not compiled when building the deputy applet

#ifndef BUILD_DEPUTY

OSStatus
OmcExecutor::DelegateTaskToDeputy(CFDataRef inData)
{
	if(mBundleRef == NULL)
		mBundleRef.Adopt( ::CFBundleGetMainBundle(), kCFObjRetain );

	CFObj<CFURLRef> myBundleURL( ::CFBundleCopyBundleURL(mBundleRef) );
	if(myBundleURL == NULL)
		return fnfErr;

	CFObj<CFURLRef> omcDeputyURL( ::CFURLCreateCopyAppendingPathComponent (
									kCFAllocatorDefault,
									myBundleURL,
									CFSTR("Versions/Current/Support/OMCDeputy.app"),
									true) );
	if(omcDeputyURL == NULL)
		return fnfErr;

	CFObj<CFURLRef> deputyAbsoluteURL( ::CFURLCopyAbsoluteURL(omcDeputyURL) );
	if(deputyAbsoluteURL == NULL)
		return fnfErr;
	
	CFObj<CFStringRef> deputyPath( ::CFURLCopyFileSystemPath(deputyAbsoluteURL, kCFURLPOSIXPathStyle) );
	if(deputyPath == NULL)
		return fnfErr;
	
	CFObj<CFStringRef> escapedDeputyPath( CreateEscapedStringCopy(deputyPath, kEscapeWithBackslash) );
	if(escapedDeputyPath == NULL)
		return fnfErr;

	CFObj<CFMutableStringRef> uniquePortName( ::CFStringCreateMutable( kCFAllocatorDefault, 0) );
	if(uniquePortName == NULL)
		return memFullErr;

	::CFStringAppend( uniquePortName, CFSTR("OMCDeputyPort-") );
	
	CFUUIDRef  myUUID = ::CFUUIDCreate(kCFAllocatorDefault);
	if(myUUID != NULL)
	{
		CFStringRef uniqueID = ::CFUUIDCreateString(kCFAllocatorDefault, myUUID);
		CFRelease(myUUID);
		::CFStringAppend( uniquePortName, uniqueID );
		::CFRelease(uniqueID);
	}


	CFObj<CFMutableStringRef> theCommand( ::CFStringCreateMutable( kCFAllocatorDefault, 0) );
	if(theCommand == NULL)
		return memFullErr;

//the deputy is launched with system() call because we want a new instance of this helper each time
	::CFStringAppend( theCommand, escapedDeputyPath );
	::CFStringAppend( theCommand, CFSTR("/Contents/MacOS/OMCDeputy "));//we need to point to the executable inside
//we want to register a unique port each time and this is the parameter passed to the app
	::CFStringAppend( theCommand, uniquePortName);
//the newly launched app will not return becuase it enters the CFRunLoop,
//we have to send it to background so the system call returns immediately
	::CFStringAppend( theCommand, CFSTR(" &"));

    std::string commandStr = CMUtils::CreateUTF8StringFromCFString(theCommand);
	if(commandStr.length() > 0)
	{
		OSStatus err = system( commandStr.c_str() );
		if(err == noErr)
		{
		    CFObj<CFMessagePortRef> remotePort( ::CFMessagePortCreateRemote(kCFAllocatorDefault, uniquePortName) );
		   
		    int tryCount = 0;
		    while( (remotePort == NULL) && (tryCount < 5) )
		    {
		    	TRACE_CSTR("Cannot obtain OMCDeputy port, sleeping one second and trying again\n.");
		    	sleep(1);
		    	remotePort.Adopt( ::CFMessagePortCreateRemote(kCFAllocatorDefault, uniquePortName), kCFObjDontRetain );
		    	tryCount++;
		    }
		    
		    if(remotePort != NULL)
		    {
				//CFDataRef replyData = NULL;
				err = ::CFMessagePortSendRequest(remotePort, 0/*msgid*/, inData, 5/*send timeout*/, 0/*rcv timout*/, NULL/*kCFRunLoopDefaultMode*/, NULL/*replyData*/);
				TRACE_CSTR("Message to OMCDeputy sent and CFMessagePortSendRequest() returned\n.");
				//if(replyData != NULL)
				//	::CFRelease(replyData);
				if( err == kCFMessagePortSuccess)
				{
					return noErr;
				}
				else
				{//could not send the message
					LOG_CSTR( "OMC->OmcExecutor::DelegateTaskToDeputy. Cannot send message to deputy. Trying to kill deputy now.\n" );
					system("killall -9 OMCDeputy");
				}
			}
			else
			{
				LOG_CSTR( "OMC->OmcExecutor::DelegateTaskToDeputy. Could not open the deputy port. Trying to kill deputy now\n" );
				system("killall -9 OMCDeputy");
			}
		}
	}

	return -1;
}

#endif //!BUILD_DEPUTY

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
	if(ioData == NULL)
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

//we don't care about the data here, we only care about the info that it ended
void PopenCFSocketCallback(
		   CFSocketRef s, 
		   CFSocketCallBackType callbackType, 
		   CFDataRef address, 
		   const void *data, 
		   void *info )
{
	POpenExecutor *executor = (POpenExecutor *)info;

	//DEBUG_CSTR("PopenCFSocketCallback called\n");

	if( executor != NULL )
	{
		CFSocketNativeHandle fd = ::CFSocketGetNative( s );
		if(fd < 0)
		{
			executor->Finish(false, true, readErr);
			return; //error
		}
		
		if(callbackType == kCFSocketReadCallBack)
		{
			ssize_t bytesRead = read( fd, oneLine, sizeof(oneLine) );
			if(bytesRead < 0)//error
			{
				executor->Finish(false, true, readErr);
				return;
			}
			else if(bytesRead > 0)
				executor->ProcessOutputData( oneLine, bytesRead );
			else //if( bytesRead == 0 )
				executor->Finish(false, true, noErr);//end of pipe, kill reading
		}
		else if(callbackType == kCFSocketWriteCallBack)
		{
			executor->WriteInputStringChunk();
		}
	}
}


#pragma mark -

POpenExecutor::POpenExecutor(const CommandDescription &inCommandDesc, CFBundleRef inBundle, CFDictionaryRef inEnviron)
	: OmcExecutor(inBundle, inCommandDesc.useDeputy),
	mCustomShell(inCommandDesc.popenShell, kCFObjRetain),
	mEnvironmentVariables(inEnviron, kCFObjRetain),
	mReadSocket(NULL), mWriteSocket(NULL),
	mReadSource(NULL), mWriteSource(NULL),
	mWrittenInputBytesCount(0)
{
	mChildProcessInfo.inputFD = -1;
	mChildProcessInfo.outputFD = -1;
	mChildProcessInfo.pid = 0;
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
                    customShellStrings[currItemIndex] = CMUtils::CreateUTF8StringFromCFString(theValue);
                    shellArgs[currItemIndex] = (char*)customShellStrings[currItemIndex].c_str();
					if(shellArgs[currItemIndex] != nullptr)
						currItemIndex++;
				}
			}
            
			shellArgs[currItemIndex] = nullptr;
		}
	}
	
	ProcessOutputString(nullptr); //send one progress notification before we start the exeuction

	outError = omc_popen(	inCommand, shellArgs.data(), envList,
							wantsToWriteToStdin ? (kOMCPopenRead | kOMCPopenWrite) : kOMCPopenRead,
							&mChildProcessInfo );

	ReleaseEnviron( envList );
	
	if(outError == 0)
	{
		CFSocketContext context;
		context.version = 0;
		context.info = this;
		context.retain = NULL; 
		context.release = NULL; 
		context.copyDescription = NULL;

#if _DEBUG_
		//::CFShow( ::CFRunLoopGetCurrent() );
		CFStringRef outStr = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("PopenExecutor::Execute cfRunLoop=0x%p"), (void *) CFRunLoopGetCurrent() );
		CFShow( outStr );
		CFRelease(outStr);
#endif

		mReadSocket = ::CFSocketCreateWithNative( kCFAllocatorDefault, mChildProcessInfo.outputFD, kCFSocketReadCallBack,
												PopenCFSocketCallback, &context);
		if(mReadSocket != NULL)
		{
			mReadSource = ::CFSocketCreateRunLoopSource(kCFAllocatorDefault, mReadSocket, 0);
			if(mReadSource != NULL)
			{
				::CFRunLoopAddSource( ::CFRunLoopGetCurrent(), mReadSource, kCFRunLoopCommonModes/*kCFRunLoopDefaultMode*/ );
			}
		}
	
		if(wantsToWriteToStdin)
		{
			//set SIGPIPE handler to IGNORE so the host app will not be forced quit if writing to broken pipe happens
			//should we bother remembering the state and restoring after command execution?
			{
				struct sigaction signalState;
				int err = sigaction(SIGPIPE, NULL, &signalState);
				if (err == 0)
				{
					signalState.sa_handler = SIG_IGN;
					err = sigaction(SIGPIPE, &signalState, NULL);
				}
			}
		
			mWriteSocket = ::CFSocketCreateWithNative( kCFAllocatorDefault, mChildProcessInfo.inputFD, kCFSocketWriteCallBack,
													PopenCFSocketCallback, &context);
			if(mWriteSocket != NULL)
			{
				mWriteSource = ::CFSocketCreateRunLoopSource(kCFAllocatorDefault, mWriteSocket, 0);
				if(mWriteSource != NULL)
				{
					::CFRunLoopAddSource( ::CFRunLoopGetCurrent(), mWriteSource, kCFRunLoopCommonModes/*kCFRunLoopDefaultMode*/ );
				}
			}
		}

		return false;
	}
	
	return true; //error condition. finished
}

#ifndef BUILD_DEPUTY

void
POpenExecutor::CreateDeputyData( ACFMutableDict &ioDict )
{
	ioDict.SetValue( CFSTR("EXECUTION_MODE"), CFSTR("exe_silent_popen") );	

	if(mBundleRef != NULL)
		AddBundlePathToDict( ioDict, CFSTR("BUNDLE_PATH"), mBundleRef );

	if(mEnvironmentVariables != NULL)
		ioDict.SetValue( CFSTR("POPEN_SHELL"), (CFTypeRef)(CFArrayRef)mCustomShell );

	if(mEnvironmentVariables != NULL)
		ioDict.SetValue( CFSTR("ENVIRONMENT_VARIABLES"), (CFTypeRef)(CFDictionaryRef)mEnvironmentVariables );
}

#endif //!BUILD_DEPUTY


POpenExecutor::~POpenExecutor()
{
	TRACE_CSTR("POpenExecutor::~POpenExecutor()\n");
	//just to be safe, if it did not go the normal way through Finish(), we need to release the socket

	(void)omc_pclose( mChildProcessInfo.pid );

	if(mReadSocket != NULL)
	{
		::CFSocketInvalidate( mReadSocket );
		::CFRelease( mReadSocket );
		mReadSocket = NULL;
	}

	if(mWriteSocket != NULL)
	{
		::CFSocketInvalidate( mWriteSocket );
		::CFRelease( mWriteSocket );
		mWriteSocket = NULL;
	}

	if( mReadSource != NULL )
	{
		::CFRunLoopRemoveSource( ::CFRunLoopGetCurrent(), mReadSource, kCFRunLoopCommonModes/*kCFRunLoopDefaultMode*/ );
		::CFRelease(mReadSource);
		mReadSource = NULL;
	}

	if( mWriteSource != NULL )
	{
		::CFRunLoopRemoveSource( ::CFRunLoopGetCurrent(), mWriteSource, kCFRunLoopCommonModes/*kCFRunLoopDefaultMode*/ );
		::CFRelease(mWriteSource);
		mWriteSource = NULL;
	}
}

void
POpenExecutor::Finish(bool wasSynchronous, bool sendNotification, OSStatus inError)
{
	TRACE_CSTR("POpenExecutor::Finish\n");

	int pipeResult = 0;

	pipeResult = omc_pclose( mChildProcessInfo.pid );

	if(mReadSocket != NULL)
	{
		::CFSocketInvalidate( mReadSocket );
		::CFRelease( mReadSocket );
		mReadSocket = NULL;
	}

	if(mWriteSocket != NULL)
	{
		::CFSocketInvalidate( mWriteSocket );
		::CFRelease( mWriteSocket );
		mWriteSocket = NULL;
	}

	if( mReadSource != NULL )
	{
		::CFRunLoopRemoveSource( ::CFRunLoopGetCurrent(), mReadSource, kCFRunLoopCommonModes/*kCFRunLoopDefaultMode*/ );
		::CFRelease(mReadSource);
		mReadSource = NULL;
	}

	if( mWriteSource != NULL )
	{
		::CFRunLoopRemoveSource( ::CFRunLoopGetCurrent(), mWriteSource, kCFRunLoopCommonModes/*kCFRunLoopDefaultMode*/ );
		::CFRelease(mWriteSource);
		mWriteSource = NULL;
	}
	
	OmcExecutor::Finish(wasSynchronous, sendNotification, (OSStatus)pipeResult );
}

void
POpenExecutor::SetInputString( CFStringRef inInputPipe )
{
	mInputString = CMUtils::CreateUTF8StringFromCFString(inInputPipe);
	mWrittenInputBytesCount = 0;
}


void
POpenExecutor::CloseWriting()
{
	omc_pclose_write( mChildProcessInfo.pid );
	mChildProcessInfo.inputFD = -1;

	if(mWriteSocket != NULL)
	{
		::CFSocketInvalidate( mWriteSocket );
		::CFRelease( mWriteSocket );
		mWriteSocket = NULL;
	}

	if( mWriteSource != NULL )
	{
		::CFRunLoopRemoveSource( ::CFRunLoopGetCurrent(), mWriteSource, kCFRunLoopCommonModes/*kCFRunLoopDefaultMode*/ );
		::CFRelease(mWriteSource);
		mWriteSource = NULL;
	}
}

void
POpenExecutor::WriteInputStringChunk()
{
	if( (mInputString.length() > 0) && (mWrittenInputBytesCount < mInputString.length()) && (mWriteSocket != NULL) )
	{
		const char *dataToWrite = mInputString.c_str() + mWrittenInputBytesCount;
		size_t byteCount = mInputString.length() - mWrittenInputBytesCount;

		CFSocketNativeHandle fd = ::CFSocketGetNative( mWriteSocket );
		ssize_t bytesWritten = write(fd, dataToWrite, byteCount);
		mWrittenInputBytesCount += bytesWritten;
	}
	
	if( (mWrittenInputBytesCount >= mInputString.length()) || (mWriteSocket == NULL) )
	{
		CloseWriting();

		//release input string early - we cannot write it twice anyway because we close the pipe
		mInputString.resize(0);
		mWrittenInputBytesCount = 0;
	}
}

#pragma mark -


POpenWithOutputExecutor::POpenWithOutputExecutor(const CommandDescription &inCommandDesc, CFStringRef inDynamicName,
												CFBundleRef inBundleRef, CFBundleRef inExternBundleRef,
												CFDictionaryRef inEnviron)
	: POpenExecutor(inCommandDesc, inBundleRef, inEnviron),
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
	if(inCommand == NULL)
		return true;

	TRACE_CSTR("POpenWithOutputExecutor. Executing now\n" );

	OutputWindowHandler *theOutput = new OutputWindowHandler( mSettingsDict, mCommandName, mDynamicCommandName, mBundleRef, mExternBundleRef, mLocalizationTableName);
	mNotifier->AddObserver( theOutput->GetObserver() );
	return POpenExecutor::Execute(inCommand, outError);
}

#ifndef BUILD_DEPUTY

void
POpenWithOutputExecutor::CreateDeputyData( ACFMutableDict &ioDict )
{	
	ioDict.SetValue( CFSTR("EXECUTION_MODE"), CFSTR("exe_popen_with_output_window") );
	if(mCommandName != NULL)
		ioDict.SetValue( CFSTR("NAME"), (CFArrayRef)mCommandName );

	if(mDynamicCommandName != NULL)
		ioDict.SetValue( CFSTR("DYNAMIC_NAME"), (CFStringRef)mDynamicCommandName );//retained
	
	if(mSettingsDict != NULL)
		ioDict.SetValue( CFSTR("OUTPUT_WINDOW_SETTINGS"), (CFDictionaryRef)mSettingsDict );//retained
	
	if(mBundleRef != NULL)
		AddBundlePathToDict( ioDict, CFSTR("BUNDLE_PATH"), mBundleRef );

	if(mExternBundleRef != NULL)
		AddBundlePathToDict( ioDict, CFSTR("EXTERNAL_BUNDLE_PATH"), mExternBundleRef );

	if(mLocalizationTableName != NULL)
		ioDict.SetValue( CFSTR("LOCALIZATION_TABLE_NAME"), (CFStringRef)mLocalizationTableName);//retained

	if(mEnvironmentVariables != NULL)
		ioDict.SetValue( CFSTR("POPEN_SHELL"), (CFTypeRef)(CFArrayRef)mCustomShell );

	if(mEnvironmentVariables != NULL)
		ioDict.SetValue( CFSTR("ENVIRONMENT_VARIABLES"), (CFTypeRef)(CFDictionaryRef)mEnvironmentVariables );
}

#endif

void
POpenWithOutputExecutor::Finish(bool wasSynchronous, bool sendNotification, OSStatus inError)
{
	POpenExecutor::Finish(wasSynchronous, sendNotification, inError);
}

#pragma mark -


bool
SystemExecutor::Execute( const char *inCommand, OSStatus &outError )
{
	outError = noErr;
	if(inCommand != NULL)
	{
		ProcessOutputString(NULL); //send one progress notification before we start non-stoppable execution

		TRACE_CSTR("SystemExecutor. Executing silently now\n" );
		outError = (OSStatus) system(inCommand);
		if(outError != noErr)
		{
			LOG_CSTR( "OMC->SystemExecutor::Execute. system() returned error = %d\n", (int)outError );
		}
	}
	return true; //finished. system() is blocking
}

#ifndef BUILD_DEPUTY

void
SystemExecutor::CreateDeputyData( ACFMutableDict &ioDict )
{
	ioDict.SetValue( CFSTR("EXECUTION_MODE"), CFSTR("exe_silent_system"));
	
	if(mBundleRef != NULL)
		AddBundlePathToDict( ioDict, CFSTR("BUNDLE_PATH"), mBundleRef );
}

#endif

#pragma mark -

AppleScriptExecutor::AppleScriptExecutor(const CommandDescription &inCommandDesc, CFStringRef inDynamicName,
										CFBundleRef inBundleRef, CFBundleRef inExternBundleRef,
										Boolean useOutputWindow)
	: OmcExecutor(inBundleRef, inCommandDesc.useDeputy), mOSAComponent(NULL), mActiveUPP(NULL),
	mSettingsDict(inCommandDesc.outputWindowOptions, kCFObjRetain),
	mCommandName(inCommandDesc.name, kCFObjRetain),
	mDynamicCommandName(inDynamicName, kCFObjRetain),
	mExternBundleRef(inExternBundleRef, kCFObjRetain),
	mLocalizationTableName(inCommandDesc.localizationTableName, kCFObjRetain),
	mUseOutput(useOutputWindow)
{
	if(mUseDeputy == false)
		mOSAComponent = OpenDefaultComponent( kOSAComponentType, kOSAGenericScriptingComponentSubtype );

	mActiveUPP = ::NewOSAActiveUPP( AppleScriptExecutor::OSAActiveProc );
	if( (mActiveUPP != NULL) && (mOSAComponent != NULL) )
	{
		/*OSAError err =*/ ::OSASetActiveProc( mOSAComponent, mActiveUPP, (SRefCon)this );
	}
}

AppleScriptExecutor::~AppleScriptExecutor()
{
	if (mOSAComponent != NULL)
		::CloseComponent(mOSAComponent);
	if(mActiveUPP != NULL)
		::DisposeOSAActiveUPP( mActiveUPP );
}


bool
AppleScriptExecutor::ExecuteCFString( CFStringRef inCommand, CFStringRef inInputPipe )
{
	this->Retain();//we need to keep us alive during execution. will be balanced by Release() on Finish()

	if(inCommand == NULL)
	{
		Finish(true, true, noErr);
		return true;
	}

	OSStatus err = noErr;

#ifndef BUILD_DEPUTY
	if(mUseDeputy)
	{
		ACFMutableDict deputyInfo;
		deputyInfo.SetValue( CFSTR("COMMAND"), inCommand);
		deputyInfo.SetValue( CFSTR("TASK_MANAGER_ID"), (CFStringRef)mTaskManagerID );
		deputyInfo.SetValue( CFSTR("TASK_INDEX"), (CFIndex)mTaskIndex );

		CreateDeputyData( deputyInfo );
        CFObj<CFDataRef> deputyData(CFPropertyListCreateData(kCFAllocatorDefault, (CFMutableDictionaryRef)deputyInfo, kCFPropertyListBinaryFormat_v1_0, 0, nullptr));
		DelegateTaskToDeputy(deputyData);
		if(err == noErr)
		{
			//Finish(); //temp until we teach deputy to talk to manager
			return false;
		}
	}
#endif
	
	if( mOSAComponent == NULL )
		mOSAComponent = OpenDefaultComponent( kOSAComponentType, kOSAGenericScriptingComponentSubtype );

	if( mOSAComponent == NULL )
	{
		Finish(true, true, noErr);
		return true;
	}

	StAEDesc theCommandDesc;

	err = CMUtils::CreateUniTextDescFromCFString(inCommand, theCommandDesc);

	if(err != noErr)
	{
		Finish(true, true, err);
		return true;
	}

	ProcessOutputString(NULL); //send one progress notification before we start non-stoppable AS execution
	
	StAEDesc resultDesc;
	OSAError osaErr = ::OSADoScript(
						mOSAComponent,
						theCommandDesc,
						kOSANullScript,
						typeUnicodeText,
						kOSAModeCompileIntoContext | kOSAModeCanInteract | kOSAModeDisplayForHumans,
						resultDesc);

	if(osaErr != noErr)
	{
		LOG_CSTR("OMC->AppleScriptExecutor::ExecuteCFString. OSADoScript returned error: %d\n", (int)osaErr);
	}

	CFObj<CFStringRef> resultString( CMUtils::CreateCFStringFromAEDesc(resultDesc, kTextReplaceNothing) );

	if(mUseOutput)
	{
//		::CFShow(resultString);
		OutputWindowHandler *theOutput = new OutputWindowHandler(mSettingsDict, mCommandName, mDynamicCommandName, mBundleRef, mExternBundleRef, mLocalizationTableName);
		if(theOutput != NULL)
		{
			mNotifier->AddObserver( theOutput->GetObserver() );
			theOutput->SetText(resultString, true, (osaErr == noErr) );
		}
	}

	ProcessOutputString(resultString);//just in case there is a progress or end notification we need to pass the result
	Finish(true, true, osaErr);//AppleScript execution is synchronous so we finish when it is done
	return true;
}

#ifndef BUILD_DEPUTY

void
AppleScriptExecutor::CreateDeputyData( ACFMutableDict &ioDict )
{
	if(mUseOutput)
		ioDict.SetValue( CFSTR("EXECUTION_MODE"), CFSTR("exe_applescript_with_output_window") );
	else
		ioDict.SetValue( CFSTR("EXECUTION_MODE"), CFSTR("exe_applescript") );
	
	if(mCommandName != NULL)
		ioDict.SetValue( CFSTR("NAME"), (CFArrayRef)mCommandName );//retained

	if(mDynamicCommandName != NULL)
		ioDict.SetValue( CFSTR("DYNAMIC_NAME"), (CFStringRef)mDynamicCommandName );//retained

	if(mSettingsDict != NULL)
		ioDict.SetValue( CFSTR("OUTPUT_WINDOW_SETTINGS"), (CFDictionaryRef)mSettingsDict );//retained

	if(mBundleRef != NULL)
		AddBundlePathToDict( ioDict, CFSTR("BUNDLE_PATH"), mBundleRef );

	if(mExternBundleRef != NULL)
		AddBundlePathToDict( ioDict, CFSTR("EXTERNAL_BUNDLE_PATH"), mExternBundleRef );

	if(mLocalizationTableName != NULL)
		ioDict.SetValue( CFSTR("LOCALIZATION_TABLE_NAME"), (CFStringRef)mLocalizationTableName);//retained
}

#endif

OSErr
AppleScriptExecutor::OSAActiveProc(SRefCon refCon)
{
	AppleScriptExecutor *theThis = (AppleScriptExecutor *)refCon;
	//just let our progress indicator know we are still alive
	if(theThis != NULL)
		theThis->ProcessOutputString(NULL);
	
	Boolean isCanceled = ::CheckEventQueueForUserCancel();
	if(isCanceled)
		return userCanceledErr;
	
	return noErr;
}

/*
void
AppleScriptExecutor::Finish()
{
	if(mOutput != NULL)
		mOutput->SetExecutor(NULL);

	OmcExecutor::Finish();
}
*/

#pragma mark -

//based on code proposed by Peter Silva
//TODO: it would be good to signal errors in all execution modes

bool
ShellScriptExecutor::Execute( const char *inCommand, OSStatus &outError )
{	
	outError = noErr;
	if(inCommand == NULL)
		return true;

	TRACE_CSTR("ShellScriptExecutor. Executing silently now\n" );

	int result = system("test -d /tmp/OMC || mkdir /tmp/OMC && chmod ugo+rw /tmp/OMC");
	
	strcpy(fileName, "/tmp/OMC/OMC_temp_script_XXXXXX");
	int fd = mkstemp(fileName);
	if(fd == -1)
	{
	//	report_error(filename, strerror(errno));
		LOG_CSTR( "OMC->ShellScriptExecutor::Execute. Could not create the temp script file with mkstemp\n" );
		return true;
	}

	//store the temp file path so we can delete it when we finish
    mTempScriptPath.assign(fileName);

	result = fchmod(fd, S_IRWXU);
	if(result != 0)
		return true;

	FILE *fp = fdopen(fd, "w");
	if(fp == NULL)
	{
	//	report_error(filename, strerror(errno));
		LOG_CSTR( "OMC->ShellScriptExecutor::Execute. Could not open the temp script file with fdopen\n" );
		return true;
	}

//	fprintf(fp, inCommand);
	fwrite(inCommand, sizeof(char), strlen(inCommand), fp );

	fclose(fp);

	strcpy(oneLine, "exec ");
	strcat(oneLine, fileName);

	return POpenExecutor::Execute(oneLine, outError);
}

#ifndef BUILD_DEPUTY

void
ShellScriptExecutor::CreateDeputyData( ACFMutableDict &ioDict )
{
	ioDict.SetValue( CFSTR("EXECUTION_MODE"), CFSTR("exe_shell_script") );
	if(mBundleRef != NULL)
		AddBundlePathToDict( ioDict, CFSTR("BUNDLE_PATH"), mBundleRef );

	if(mEnvironmentVariables != NULL)
		ioDict.SetValue( CFSTR("POPEN_SHELL"), (CFTypeRef)(CFArrayRef)mCustomShell );

	if(mEnvironmentVariables != NULL)
		ioDict.SetValue( CFSTR("ENVIRONMENT_VARIABLES"), (CFTypeRef)(CFDictionaryRef)mEnvironmentVariables );
}

#endif

void
ShellScriptExecutor::Finish(bool wasSynchronous, bool sendNotification, OSStatus inError)
{
	TRACE_CSTR("ShellScriptExecutor::Finish\n");
	if(mTempScriptPath.length() > 0)
		unlink(mTempScriptPath.c_str());

	POpenExecutor::Finish(wasSynchronous, sendNotification, inError);
}

#pragma mark -


ShellScriptWithOutputExecutor::ShellScriptWithOutputExecutor(const CommandDescription &inCommandDesc, CFStringRef inDynamicName,
															CFBundleRef inBundleRef, CFBundleRef inExternBundleRef,
															CFDictionaryRef inEnviron)
	: ShellScriptExecutor(inCommandDesc, inBundleRef, inEnviron),
	mSettingsDict(inCommandDesc.outputWindowOptions, kCFObjRetain),
	mCommandName(inCommandDesc.name, kCFObjRetain),
	mDynamicCommandName(inDynamicName, kCFObjRetain),
	mExternBundleRef(inExternBundleRef, kCFObjRetain),
	mLocalizationTableName(inCommandDesc.localizationTableName, kCFObjRetain)
{
}

ShellScriptWithOutputExecutor::~ShellScriptWithOutputExecutor()
{
}

							
bool
ShellScriptWithOutputExecutor::Execute( const char *inCommand, OSStatus &outError  )
{
	outError = noErr;
	if(inCommand == NULL)
		return true;

	TRACE_CSTR("ShellScriptWithOutputExecutor. Executing now\n" );

	int result = system("test -d /tmp/OMC || mkdir /tmp/OMC && chmod ugo+rw /tmp/OMC");
	
	strcpy(fileName, "/tmp/OMC/OMC_temp_script_XXXXXX");
	int fd = mkstemp(fileName);
	if(fd == -1)
	{
	//	report_error(filename, strerror(errno));
		LOG_CSTR( "OMC->ShellScriptWithOutputExecutor::Execute. Could not create the temp script file with mkstemp\n" );
		return true;
	}

	//store the temp file path so we can delete it when we finish
	mTempScriptPath.assign(fileName);
	
	result = fchmod(fd, S_IRWXU);
	if(result != 0)
		return true;

	FILE *fp = fdopen(fd, "w");
	if(fp == NULL)
	{
	//	report_error(filename, strerror(errno));
		LOG_CSTR( "OMC->ShellScriptWithOutputExecutor::Execute. Could not open the temp script file with fdopen\n" );
		return true;
	}

//	fprintf(fp, inCommand);	
	fwrite(inCommand, sizeof(char), strlen(inCommand), fp );
	fclose(fp);

	strcpy(oneLine, "exec ");
	strcat(oneLine, fileName);

	OutputWindowHandler *theOutput = new OutputWindowHandler(mSettingsDict, mCommandName, mDynamicCommandName, mBundleRef, mExternBundleRef, mLocalizationTableName);
	mNotifier->AddObserver( theOutput->GetObserver() );

	return POpenExecutor::Execute(oneLine, outError);
}

#ifndef BUILD_DEPUTY

void
ShellScriptWithOutputExecutor::CreateDeputyData( ACFMutableDict &ioDict )
{
	ioDict.SetValue( CFSTR("EXECUTION_MODE"), CFSTR("exe_shell_script_with_output_window") );

	if(mCommandName != NULL)
		ioDict.SetValue( CFSTR("NAME"), (CFArrayRef)mCommandName);//retained

	if(mDynamicCommandName != NULL)
		ioDict.SetValue( CFSTR("DYNAMIC_NAME"), (CFStringRef)mDynamicCommandName);//retained

	if(mSettingsDict != NULL)
		ioDict.SetValue( CFSTR("OUTPUT_WINDOW_SETTINGS"), (CFDictionaryRef)mSettingsDict);//retained

	if(mBundleRef != NULL)
		AddBundlePathToDict( ioDict, CFSTR("BUNDLE_PATH"), mBundleRef );

	if(mExternBundleRef != NULL)
		AddBundlePathToDict( ioDict, CFSTR("EXTERNAL_BUNDLE_PATH"), mExternBundleRef );

	if(mLocalizationTableName != NULL)
		ioDict.SetValue( CFSTR("LOCALIZATION_TABLE_NAME"), (CFStringRef)mLocalizationTableName);//retained

	if(mEnvironmentVariables != NULL)
		ioDict.SetValue( CFSTR("POPEN_SHELL"), (CFTypeRef)(CFArrayRef)mCustomShell );

	if(mEnvironmentVariables != NULL)
		ioDict.SetValue( CFSTR("ENVIRONMENT_VARIABLES"), (CFTypeRef)(CFDictionaryRef)mEnvironmentVariables );
}

#endif

void
ShellScriptWithOutputExecutor::Finish(bool wasSynchronous, bool sendNotification, OSStatus inError)
{
	ShellScriptExecutor::Finish(wasSynchronous, sendNotification, inError);
}


#pragma mark -

//use ReleaseEnviron to free the result
char **
CreateEnvironmentList(CFDictionaryRef inEnviron)
{
	if(inEnviron == NULL)
		return NULL;

	CFIndex itemCount = ::CFDictionaryGetCount(inEnviron);
	if(itemCount == 0)
		return NULL;

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
		keyList[i] = NULL;
		valueList[i] = NULL;

		if( (theKey != NULL) && (theValue != NULL) )
		{
			keyStrings[currItemIndex] = CMUtils::CreateUTF8StringFromCFString(theKey);
            if(keyStrings[currItemIndex].length() > 0)
            {
                keyList[currItemIndex] = (void *)keyStrings[currItemIndex].c_str();
                valueStrings[currItemIndex] = CMUtils::CreateUTF8StringFromCFString(theValue);
                valueList[currItemIndex] = (void *)valueStrings[currItemIndex].c_str();
                currItemIndex++;
            }
		}
	}
	
	char ** newEnviron = CreateEnviron( (char **)keyList.data(), (char **)valueList.data(), currItemIndex );
	return newEnviron;
}


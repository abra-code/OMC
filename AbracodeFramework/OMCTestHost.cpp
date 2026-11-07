//
//  OMCTestHost.cpp
//  Abracode
//
//  See OMCTestHost.h. Portable: POSIX, CF, the engine's command runner and JSON, and the bridge
//  through OMCActionUIRemoteHost.h's C functions; what differs per platform is in
//  Platform/OMCTestPlatform.h and Platform/OMCTestability.h.
//

#include "OMCTestHost.h"
#include "OMCTestability.h"
#include "OMCTestPlatform.h"
#include "OMCEngineActivity.h"
#include "OMCActionUIRemoteHost.h"
#include "OMCCommandRunner.h"
#include "OMCMainThreadSignal.h"
#include "ACFJSON.h"
#include "ACFType.h"
#include "CFObj.h"
#include <memory>
#include <string>
#include <vector>
#include <errno.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

namespace
{

const char *kTokenFDVariable = "OMC_TEST_TOKEN_FD";
const char *kBridgePathVariable = "OMC_TEST_BRIDGE_PATH";
const char *kTokenLabel = "omc.test";
const int kRefusedExitStatus = 78; // EX_CONFIG
const int kTokenReadTimeoutMilliseconds = 5000;
const size_t kMaxTokenLength = 128;
const size_t kMinTokenLength = 16;

// JSON-RPC error codes, as ActionUIRemote answers them.
const int kInvalidParams = -32602;
const int kHostRefused = 1004;

// What one omc.test.runCommand did. Never freed while the process lives: an observer's callback
// may name a run at any time, and a test session runs a few dozen.
struct TestRun
{
	long					number {0};
	CFObj<CFStringRef>		commandID;
	CFObj<CFTypeRef>		context;
	bool					allowKeyWindow {false};
	bool					dispatchedToWindow {false};
	bool					started {false};
	bool					finished {false};
	bool					canceled {false};
	bool					observerCreated {false};
	// Our own reference: the runner releases the one it is handed once the observer is attached,
	// as the delegate path expects the delegate to keep one (OMCCommandExecutor.mm). Kept for the
	// process's life like the run itself, since the last message may come at any time.
	OMCObserverRef			observer {nullptr};
	OSStatus				status {noErr};
	CFObj<CFMutableStringRef> output;
};

bool sActive = false;
std::vector< std::unique_ptr<TestRun> > sRuns;
long sScheduledRuns = 0;

[[noreturn]] void
RefuseTestLaunch(const char *inReason)
{
	fprintf(stderr, "OMC test launch refused: %s\n", inReason);
	fflush(stderr);
	exit(kRefusedExitStatus);
}

// The descriptor number from the variable: an integer, 3 or above, so stdin, stdout and stderr
// can never be read by mistake.
bool
ParseDescriptor(const char *inText, int &outFD)
{
	if((inText == nullptr) || (inText[0] < '0') || (inText[0] > '9'))
		return false; // digits only: strtol would also take leading spaces and a sign
	char *end = nullptr;
	errno = 0;
	long value = strtol(inText, &end, 10);
	if((errno != 0) || (end == inText) || (*end != 0) || (value < 3) || (value > 1023))
		return false;
	outFD = (int)value;
	return true;
}

bool
IsTokenCharacter(char inChar)
{
	return ((inChar >= 'a') && (inChar <= 'z')) || ((inChar >= 'A') && (inChar <= 'Z')) ||
			((inChar >= '0') && (inChar <= '9')) || (inChar == '-') || (inChar == '_');
}

// Reads the token, waiting at most kTokenReadTimeoutMilliseconds for it, and closes the descriptor
// whatever happens, so nothing this process spawns inherits it.
bool
ReadToken(int inFD, std::string &outToken)
{
	outToken.clear();
	bool ok = true;
	char buffer[kMaxTokenLength + 2];
	size_t length = 0;
	// One deadline for the whole read, so a sender that trickles bytes cannot stretch it.
	struct timespec start;
	clock_gettime(CLOCK_MONOTONIC, &start);
	while(ok)
	{
		struct timespec now;
		clock_gettime(CLOCK_MONOTONIC, &now);
		long elapsed = (long)(now.tv_sec - start.tv_sec) * 1000 + (long)(now.tv_nsec - start.tv_nsec) / 1000000;
		long remaining = kTokenReadTimeoutMilliseconds - elapsed;
		if(remaining <= 0)
		{
			ok = false;
			break;
		}
		struct pollfd waitFor = { inFD, POLLIN, 0 };
		int ready = poll(&waitFor, 1, (int)remaining);
		if(ready < 0)
		{
			if(errno == EINTR)
				continue;
			ok = false;
			break;
		}
		if(ready == 0)
		{
			ok = false; // nothing arrived in time
			break;
		}

		ssize_t count = read(inFD, buffer + length, sizeof(buffer) - length);
		if(count < 0)
		{
			if(errno == EINTR)
				continue;
			ok = false;
			break;
		}
		if(count == 0)
			break; // end of file
		length += (size_t)count;
		if(memchr(buffer, '\n', length) != nullptr)
			break;
		if(length >= sizeof(buffer))
		{
			ok = false; // longer than any token
			break;
		}
	}
	close(inFD);

	if(!ok)
		return false;

	while((length > 0) && ((buffer[length - 1] == '\n') || (buffer[length - 1] == '\r')))
		length--;
	if((length < kMinTokenLength) || (length > kMaxTokenLength))
		return false;
	for(size_t i = 0; i < length; i++)
	{
		if(!IsTokenCharacter(buffer[i]))
			return false;
	}
	outToken.assign(buffer, length);
	return true;
}

#pragma mark - Replies

char *
CopyBytes(CFDataRef inData)
{
	if(inData == nullptr)
		return nullptr;
	CFIndex length = ::CFDataGetLength(inData);
	char *text = (char *)malloc((size_t)length + 1);
	if(text == nullptr)
		return nullptr;
	memcpy(text, ::CFDataGetBytePtr(inData), (size_t)length);
	text[length] = 0;
	return text;
}

// {"result": inResult} as malloc'd JSON text, or NULL when it cannot be written (the bridge then
// answers -32603 and logs it).
char *
CreateResultReply(CFTypeRef inResult)
{
	const void *keys[] = { CFSTR("result") };
	const void *values[] = { (inResult != nullptr) ? inResult : kCFBooleanTrue };
	CFObj<CFDictionaryRef> reply( ::CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks) );
	CFObj<CFDataRef> data( ACFJSONCreateData(reply, nullptr) );
	return CopyBytes(data);
}

char *
CreateErrorReply(int inCode, CFStringRef inMessage)
{
	int code = inCode;
	CFObj<CFNumberRef> codeNumber( ::CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &code) );
	const void *errorKeys[] = { CFSTR("code"), CFSTR("message") };
	const void *errorValues[] = { (CFNumberRef)codeNumber, inMessage };
	CFObj<CFDictionaryRef> error( ::CFDictionaryCreate(kCFAllocatorDefault, errorKeys, errorValues, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks) );
	const void *keys[] = { CFSTR("error") };
	const void *values[] = { (CFDictionaryRef)error };
	CFObj<CFDictionaryRef> reply( ::CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks) );
	CFObj<CFDataRef> data( ACFJSONCreateData(reply, nullptr) );
	return CopyBytes(data);
}

void
SetNumber(CFMutableDictionaryRef ioDict, CFStringRef inKey, long inValue)
{
	long value = inValue;
	CFObj<CFNumberRef> number( ::CFNumberCreate(kCFAllocatorDefault, kCFNumberLongType, &value) );
	::CFDictionarySetValue(ioDict, inKey, number);
}

void
SetBool(CFMutableDictionaryRef ioDict, CFStringRef inKey, bool inValue)
{
	::CFDictionarySetValue(ioDict, inKey, inValue ? kCFBooleanTrue : kCFBooleanFalse);
}

CFMutableDictionaryRef
CreateMutableDict()
{
	return ::CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}

#pragma mark - Runs

void
RunObserverCallback(OmcObserverMessage inMessage, CFIndex inTaskID, CFTypeRef inResult, void *userData)
{
	(void)inTaskID;
	TestRun *run = (TestRun *)userData;
	if(run == nullptr)
		return;

	switch(inMessage)
	{
		case kOmcObserverTaskProgress:
		{
			CFStringRef text = ACFType<CFStringRef>::DynamicCast(inResult);
			if(text != nullptr)
			{
				if(run->output == nullptr)
					run->output.Adopt( ::CFStringCreateMutable(kCFAllocatorDefault, 0) );
				if(run->output != nullptr)
					::CFStringAppend(run->output, text);
			}
		}
		break;

		case kOmcObserverTaskCanceled:
			run->canceled = true;
			OMCNoteEngineActivity();
		break;

		case kOmcObserverAllTasksFinished:
			run->finished = true;
			OMCNoteEngineActivity();
		break;

		default:
		break;
	}
}

OMCObserverRef
CreateRunObserver(void *inHookContext)
{
	TestRun *run = (TestRun *)inHookContext;
	OMCObserverRef observer = OMCCreateObserver(kOmcObserverAllMessages, RunObserverCallback, run);
	if(observer != nullptr)
	{
		run->observerCreated = true;
		OMCRetainObserver(observer);
		run->observer = observer;
	}
	return observer; // +1: the runner adds it to the run and releases this reference
}

bool
DispatchToKeyWindow(void *inHookContext, CFStringRef inCommandNameOrId, CFTypeRef inContext)
{
	TestRun *run = (TestRun *)inHookContext;
	if((run != nullptr) && !run->allowKeyWindow)
		return false;
	bool dispatched = OMCTestPlatformDispatchToKeyWindow(inCommandNameOrId, inContext);
	if(dispatched && (run != nullptr))
		run->dispatchedToWindow = true; // the window runs it; this run observes nothing
	return dispatched;
}

void
StartRun(void *inContext)
{
	TestRun *run = (TestRun *)inContext;
	sScheduledRuns--;
	run->started = true;
	OMCNoteEngineActivity();

	OMCRunHooks hooks;
	hooks.dispatchToKeyWindow = DispatchToKeyWindow;
	hooks.noteRecentFiles = nullptr;
	hooks.createObserver = CreateRunObserver;
	hooks.context = run;

	// The menu's way (OMCCommandMenu), but with no open panel: a test has no one to answer it.
	run->status = OMCRunCommandFromFile(run->commandID, CFSTR("Command.plist"), run->context,
										false, run->allowKeyWindow, nullptr, false, &hooks);
	if(!run->observerCreated)
		run->finished = true; // it never got as far as running anything
	OMCNoteEngineActivity();
}

// The file context from "files": absolute paths only, as CFURLs.
CFArrayRef
CreateFileContext(CFArrayRef inPaths, CFStringRef &outProblem)
{
	outProblem = nullptr;
	CFIndex count = ::CFArrayGetCount(inPaths);
	CFObj<CFMutableArrayRef> urls( ::CFArrayCreateMutable(kCFAllocatorDefault, count, &kCFTypeArrayCallBacks) );
	for(CFIndex i = 0; i < count; i++)
	{
		CFStringRef path = ACFType<CFStringRef>::DynamicCast(::CFArrayGetValueAtIndex(inPaths, i));
		if((path == nullptr) || !::CFStringHasPrefix(path, CFSTR("/")))
		{
			outProblem = CFSTR("files must be absolute paths");
			return nullptr;
		}
		Boolean isDirectory = ::CFStringHasSuffix(path, CFSTR("/"));
		CFObj<CFURLRef> url( ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, path, kCFURLPOSIXPathStyle, isDirectory) );
		if(url == nullptr)
		{
			outProblem = CFSTR("a path in files is not usable");
			return nullptr;
		}
		::CFArrayAppendValue(urls, url);
	}
	return urls.Detach();
}

#pragma mark - Methods

char *
HandleStatus()
{
	CFObj<CFMutableDictionaryRef> result( CreateMutableDict() );
	long active = OMCGetUnfinishedTaskManagerCount();
	SetBool(result, CFSTR("idle"), (active <= 0) && (sScheduledRuns <= 0));
	SetNumber(result, CFSTR("activeCommands"), active);
	SetNumber(result, CFSTR("scheduledRuns"), sScheduledRuns);
	SetNumber(result, CFSTR("activity"), (long)OMCGetEngineActivityCount());
	return CreateResultReply(result);
}

char *
HandleRunCommand(CFDictionaryRef inParams)
{
	CFStringRef commandID = ACFType<CFStringRef>::DynamicCast(::CFDictionaryGetValue(inParams, CFSTR("commandID")));
	if((commandID == nullptr) || (::CFStringGetLength(commandID) == 0))
		return CreateErrorReply(kInvalidParams, CFSTR("commandID: a non-empty string is required"));

	CFTypeRef textValue = ::CFDictionaryGetValue(inParams, CFSTR("text"));
	CFStringRef text = ACFType<CFStringRef>::DynamicCast(textValue);
	if((textValue != nullptr) && (text == nullptr))
		return CreateErrorReply(kInvalidParams, CFSTR("text: must be a string"));

	CFTypeRef filesValue = ::CFDictionaryGetValue(inParams, CFSTR("files"));
	CFArrayRef files = ACFType<CFArrayRef>::DynamicCast(filesValue);
	if((filesValue != nullptr) && (files == nullptr))
		return CreateErrorReply(kInvalidParams, CFSTR("files: must be an array of absolute paths"));

	CFTypeRef keyWindowValue = ::CFDictionaryGetValue(inParams, CFSTR("keyWindow"));
	CFBooleanRef keyWindow = ACFType<CFBooleanRef>::DynamicCast(keyWindowValue);
	if((keyWindowValue != nullptr) && (keyWindow == nullptr))
		return CreateErrorReply(kInvalidParams, CFSTR("keyWindow: must be true or false"));

	std::unique_ptr<TestRun> run(new TestRun());
	run->number = (long)sRuns.size() + 1;
	run->commandID.Adopt(commandID, kCFObjRetain);
	run->allowKeyWindow = (keyWindow != nullptr) && ::CFBooleanGetValue(keyWindow);
	if((files != nullptr) && (::CFArrayGetCount(files) > 0))
	{
		CFStringRef problem = nullptr;
		CFObj<CFArrayRef> urls( CreateFileContext(files, problem) );
		if(urls == nullptr)
			return CreateErrorReply(kInvalidParams, (problem != nullptr) ? problem : CFSTR("files: not usable"));
		run->context.Adopt((CFTypeRef)urls.Detach());
	}
	else if(text != nullptr)
	{
		run->context.Adopt((CFTypeRef)text, kCFObjRetain);
	}

	TestRun *scheduled = run.get();
	if(!OMCMainThreadSignal::RunAfter(0.0, StartRun, scheduled))
		return CreateErrorReply(kHostRefused, CFSTR("the run could not be scheduled"));
	sRuns.push_back(std::move(run));
	sScheduledRuns++;
	OMCNoteEngineActivity();

	CFObj<CFMutableDictionaryRef> result( CreateMutableDict() );
	SetNumber(result, CFSTR("run"), scheduled->number);
	return CreateResultReply(result);
}

CFDictionaryRef
CreateRunRecord(const TestRun &inRun)
{
	CFMutableDictionaryRef record = CreateMutableDict();
	SetNumber(record, CFSTR("run"), inRun.number);
	::CFDictionarySetValue(record, CFSTR("commandID"), inRun.commandID);
	SetBool(record, CFSTR("started"), inRun.started);
	SetBool(record, CFSTR("finished"), inRun.finished);
	SetBool(record, CFSTR("canceled"), inRun.canceled);
	SetBool(record, CFSTR("dispatchedToWindow"), inRun.dispatchedToWindow);
	SetNumber(record, CFSTR("status"), (long)inRun.status);
	::CFDictionarySetValue(record, CFSTR("output"), (inRun.output != nullptr) ? (CFStringRef)inRun.output : CFSTR(""));
	return record;
}

char *
HandleLog(CFDictionaryRef inParams)
{
	CFTypeRef runValue = ::CFDictionaryGetValue(inParams, CFSTR("run"));
	long wanted = 0;
	if(runValue != nullptr)
	{
		CFNumberRef number = ACFType<CFNumberRef>::DynamicCast(runValue);
		if((number == nullptr) || !::CFNumberGetValue(number, kCFNumberLongType, &wanted) || (wanted < 1) || (wanted > (long)sRuns.size()))
			return CreateErrorReply(kInvalidParams, CFSTR("run: not a run number this applet gave"));
	}

	CFObj<CFMutableArrayRef> records( ::CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks) );
	for(const auto &run : sRuns)
	{
		if((wanted != 0) && (run->number != wanted))
			continue;
		CFObj<CFDictionaryRef> record( CreateRunRecord(*run) );
		::CFArrayAppendValue(records, record);
	}
	CFObj<CFMutableDictionaryRef> result( CreateMutableDict() );
	::CFDictionarySetValue(result, CFSTR("runs"), records);
	return CreateResultReply(result);
}

void
QuitNow(void *inContext)
{
	(void)inContext;
	OMCTestPlatformRequestQuit();
}

char *
HandleQuit()
{
	// After the reply has gone out: terminating from inside the bridge's own call would stop the
	// bridge while it is answering.
	if(!OMCMainThreadSignal::RunAfter(0.1, QuitNow, nullptr))
		return CreateErrorReply(kHostRefused, CFSTR("the quit could not be scheduled"));
	CFObj<CFMutableDictionaryRef> result( CreateMutableDict() );
	SetBool(result, CFSTR("quitting"), true);
	return CreateResultReply(result);
}

char *
HandleMethod(void *inContext, const char *inMethod, const char *inParamsJSON)
{
	(void)inContext;
	CFObj<CFDictionaryRef> params;
	if(inParamsJSON != nullptr)
	{
		CFObj<CFDataRef> data( ::CFDataCreate(kCFAllocatorDefault, (const UInt8 *)inParamsJSON, (CFIndex)strlen(inParamsJSON)) );
		CFObj<CFPropertyListRef> parsed( ACFJSONCreatePropertyList(data, kCFPropertyListImmutable, nullptr) );
		CFDictionaryRef dict = ACFType<CFDictionaryRef>::DynamicCast(parsed);
		if(dict != nullptr)
			params.Adopt(dict, kCFObjRetain);
	}
	if(params == nullptr)
		params.Adopt( ::CFDictionaryCreate(kCFAllocatorDefault, nullptr, nullptr, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks) );

	if(strcmp(inMethod, "omc.test.status") == 0)
		return HandleStatus();
	if(strcmp(inMethod, "omc.test.runCommand") == 0)
		return HandleRunCommand(params);
	if(strcmp(inMethod, "omc.test.log") == 0)
		return HandleLog(params);
	if(strcmp(inMethod, "omc.test.quit") == 0)
		return HandleQuit();
	return CreateErrorReply(-32601, CFSTR("Method not found"));
}

const char *kMethods[] = { "omc.test.status", "omc.test.runCommand", "omc.test.log", "omc.test.quit" };

} // namespace

void
OMCTestHostStartIfRequested(void)
{
	const char *fdText = getenv(kTokenFDVariable);
	const char *pathText = getenv(kBridgePathVariable);
	if((fdText == nullptr) && (pathText == nullptr))
		return; // a normal launch

	// Copied before the variables go: unsetenv may free what getenv returned.
	std::string fdString = (fdText != nullptr) ? fdText : "";
	std::string bridgePath = (pathText != nullptr) ? pathText : "";
	unsetenv(kTokenFDVariable);
	unsetenv(kBridgePathVariable);

	int fd = -1;
	bool haveFD = ParseDescriptor(fdString.c_str(), fd);
	std::string token;
	bool haveToken = haveFD && ReadToken(fd, token); // closes the descriptor

	OMCTestSurfaceStatus surface = OMCGetTestSurfaceStatus();
	if(surface != kOMCTestSurface_Allowed)
	{
		// The descriptions read "refused: <why>"; the line already says refused.
		const char *reason = OMCGetTestSurfaceStatusDescription(surface);
		const char *prefix = "refused: ";
		if(strncmp(reason, prefix, strlen(prefix)) == 0)
			reason += strlen(prefix);
		RefuseTestLaunch(reason);
	}
	if(!haveFD)
		RefuseTestLaunch("OMC_TEST_TOKEN_FD must name a descriptor, 3 or above");
	if(!haveToken)
		RefuseTestLaunch("no usable token arrived on OMC_TEST_TOKEN_FD within 5 seconds (16 to 128 characters of A-Z a-z 0-9 - _)");
	if(bridgePath.empty() || (bridgePath[0] != '/'))
		RefuseTestLaunch("OMC_TEST_BRIDGE_PATH must be an absolute path");

	if(!OMCStartActionUIRemoteBridgeAtPath(bridgePath.c_str()))
		RefuseTestLaunch("the ActionUI remote bridge did not start at OMC_TEST_BRIDGE_PATH (see the log)");
	if(!OMCAddActionUIRemoteToken(token.c_str(), kTokenLabel))
		RefuseTestLaunch("the bridge did not accept the token");
	for(const char *method : kMethods)
	{
		if(!OMCRegisterActionUIRemoteMethod(method, HandleMethod, nullptr))
			RefuseTestLaunch("the bridge did not accept the omc.test methods");
	}
	// A click on a control, for a test: what checks the wiring from a control's actionID to its handler.
	if(!OMCEnableActionUIRemotePerformAction())
		RefuseTestLaunch("the bridge did not turn on actionui.performAction");

	sActive = true;
	fprintf(stderr, "OMC test launch: bridge at %s\n", bridgePath.c_str());
	fflush(stderr);
}

bool
OMCTestHostIsActive(void)
{
	return sActive;
}

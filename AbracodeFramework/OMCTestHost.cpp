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
#include "OMCFilePanels.h"
#include "ACFJSON.h"
#include "ACFType.h"
#include "CFObj.h"
#include <deque>
#include <memory>
#include <string>
#include <vector>
#include <errno.h>
#include <limits.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

namespace
{

const char *kTokenFDVariable = "OMC_TEST_TOKEN_FD";
const char *kBridgePathVariable = "OMC_TEST_BRIDGE_PATH";
const char *kPasteboardPrefixVariable = "OMC_TEST_PASTEBOARD_PREFIX";
const size_t kMaxPasteboardPrefixLength = 100;
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
	bool					allowOpenPanel {false};
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
long sSkippedPastes = 0;
std::string sPasteboardPrefix;
CFObj<CFStringRef> sClipboardName; // "<prefix>.general", what the engine reads as the clipboard

// A queued omc.test.answer.
enum class PanelAnswerKind { save, open, cancel };
struct PanelAnswer
{
	PanelAnswerKind		kind {PanelAnswerKind::cancel};
	CFObj<CFArrayRef>	paths; // CFStrings, absolute: one for save, one or more for open
};

std::deque<PanelAnswer> sPanelAnswers;
CFObj<CFMutableArrayRef> sPanelRecords; // what omc.test.panels reports, in order

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

// 1 to kMaxPasteboardPrefixLength characters of [A-Za-z0-9._-], as the pasteboard tool takes them.
bool
IsUsablePasteboardPrefix(const std::string &inPrefix)
{
	if(inPrefix.empty() || (inPrefix.size() > kMaxPasteboardPrefixLength))
		return false;
	for(char c : inPrefix)
	{
		bool usable = ((c >= 'a') && (c <= 'z')) || ((c >= 'A') && (c <= 'Z')) || ((c >= '0') && (c <= '9')) ||
						(c == '.') || (c == '_') || (c == '-');
		if(!usable)
			return false;
	}
	return true;
}

// A prefix of the engine's own for a test launch that brought none: unique to this launch, and
// not derived from the token, which must stay secret.
std::string
MakePasteboardPrefix()
{
	struct timespec now;
	clock_gettime(CLOCK_REALTIME, &now);
	char text[64];
	snprintf(text, sizeof(text), "omc.test.%ld.%lx", (long)getpid(), (unsigned long)now.tv_nsec ^ ((unsigned long)now.tv_sec << 20));
	return std::string(text);
}

// The run's pasteboards, decided once and at the first need. That can come before the launch is
// set up: the engine looks at the clipboard while it builds its menus, before app.will.launch, and
// that look must already go to the run's pasteboard, not the user's clipboard. A launch for a test
// is recognized by its variables then; the launch itself (OMCTestHostStartIfRequested) refuses a
// prefix that is not usable, so an early read only ever uses a usable one, the engine's own when
// the harness's is not. Main thread, as every clipboard read and the launch are.
bool sPasteboardsDecided = false;
bool sPasteboardPrefixRefused = false;

bool
IsTestLaunchRequested()
{
	return (getenv(kTokenFDVariable) != nullptr) || (getenv(kBridgePathVariable) != nullptr);
}

void
DecidePasteboards()
{
	if(sPasteboardsDecided)
		return;
	sPasteboardsDecided = true;

	const char *prefixText = getenv(kPasteboardPrefixVariable);
	std::string prefix = (prefixText != nullptr) ? prefixText : "";
	if(prefix.empty() || !IsUsablePasteboardPrefix(prefix))
	{
		sPasteboardPrefixRefused = (prefixText != nullptr);
		prefix = MakePasteboardPrefix();
	}
	std::string clipboardName = prefix + ".general";
	sClipboardName.Adopt( ::CFStringCreateWithCString(kCFAllocatorDefault, clipboardName.c_str(), kCFStringEncodingUTF8) );
	sPasteboardPrefix = prefix;
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

	// The menu's way (OMCCommandMenu), with the open panel only when the test asked for it: it
	// takes a queued answer like every panel here.
	run->status = OMCRunCommandFromFile(run->commandID, CFSTR("Command.plist"), run->context,
										run->allowOpenPanel, run->allowKeyWindow, nullptr, false, &hooks);
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

#pragma mark - Panels

void
SetStringIfAny(CFMutableDictionaryRef ioDict, CFStringRef inKey, CFStringRef inValue)
{
	if(inValue != nullptr)
		::CFDictionarySetValue(ioDict, inKey, inValue);
}

CFMutableDictionaryRef
CreatePanelRecord(bool inIsSave, CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath,
					CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inFlags)
{
	CFMutableDictionaryRef record = CreateMutableDict();
	::CFDictionarySetValue(record, CFSTR("kind"), inIsSave ? CFSTR("save") : CFSTR("open"));
	SetStringIfAny(record, CFSTR("title"), inClientName);
	SetStringIfAny(record, CFSTR("message"), inMessage);
	SetStringIfAny(record, CFSTR("prompt"), inPrompt);
	SetStringIfAny(record, CFSTR("defaultName"), inDefaultName);
	SetStringIfAny(record, CFSTR("defaultDirectory"), inDefaultDirPath);
	SetStringIfAny(record, CFSTR("identifier"), inIdentifier);
	if(inAllowedContentTypes != nullptr)
		::CFDictionarySetValue(record, CFSTR("allowedContentTypes"), inAllowedContentTypes);
	if(!inIsSave)
	{
		SetBool(record, CFSTR("canChooseFiles"), (inFlags & kOMCFilePanelCanChooseFiles) != 0);
		SetBool(record, CFSTR("canChooseDirectories"), (inFlags & kOMCFilePanelCanChooseDirectories) != 0);
		SetBool(record, CFSTR("allowsMultiple"), (inFlags & kOMCFilePanelAllowMultipleItems) != 0);
	}
	return record;
}

// Whether a path names something, and whether that is a directory (following symlinks, as a panel does).
bool
StatPath(CFStringRef inPath, bool &outIsDirectory)
{
	outIsDirectory = false;
	char path[PATH_MAX];
	if(!::CFStringGetFileSystemRepresentation(inPath, path, sizeof(path)))
		return false;
	struct stat info;
	if(stat(path, &info) != 0)
		return false;
	outIsDirectory = S_ISDIR(info.st_mode);
	return true;
}

CFURLRef
CreateFileURL(CFStringRef inPath, bool inIsDirectory)
{
	return ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, inPath, kCFURLPOSIXPathStyle, inIsDirectory);
}

// Takes the next queued answer for a panel and checks it against what the panel could have given.
// Returns the reason it was refused, or NULL; outURLs is left empty for a cancel or a refusal.
CFStringRef
TakePanelAnswer(bool inIsSave, UInt32 inFlags, CFObj<CFMutableArrayRef> &outURLs)
{
	if(sPanelAnswers.empty())
		return CFSTR("no answer was queued");
	PanelAnswer answer = sPanelAnswers.front();
	sPanelAnswers.pop_front();

	if(answer.kind == PanelAnswerKind::cancel)
		return nullptr;
	if(inIsSave && (answer.kind != PanelAnswerKind::save))
		return CFSTR("the queued answer is for an open panel");
	if(!inIsSave && (answer.kind != PanelAnswerKind::open))
		return CFSTR("the queued answer is for a save panel");

	CFIndex count = ::CFArrayGetCount(answer.paths);
	CFObj<CFMutableArrayRef> urls( ::CFArrayCreateMutable(kCFAllocatorDefault, count, &kCFTypeArrayCallBacks) );
	if(inIsSave)
	{
		CFStringRef path = (CFStringRef)::CFArrayGetValueAtIndex(answer.paths, 0);
		// A save panel names a file: never an existing folder, never a path ending in a slash.
		bool pathIsDirectory = false;
		if(::CFStringHasSuffix(path, CFSTR("/")) || (StatPath(path, pathIsDirectory) && pathIsDirectory))
			return CFSTR("a folder for a save panel");
		CFObj<CFURLRef> url( CreateFileURL(path, false) );
		CFObj<CFURLRef> parent( (url != nullptr) ? ::CFURLCreateCopyDeletingLastPathComponent(kCFAllocatorDefault, url) : nullptr );
		CFObj<CFStringRef> parentPath( (parent != nullptr) ? ::CFURLCopyFileSystemPath(parent, kCFURLPOSIXPathStyle) : nullptr );
		bool parentIsDirectory = false;
		if((parentPath == nullptr) || !StatPath(parentPath, parentIsDirectory) || !parentIsDirectory)
			return CFSTR("the folder of the answered save path does not exist");
		::CFArrayAppendValue(urls, url);
	}
	else
	{
		if((count > 1) && ((inFlags & kOMCFilePanelAllowMultipleItems) == 0))
			return CFSTR("several paths for a panel that takes one");
		for(CFIndex i = 0; i < count; i++)
		{
			CFStringRef path = (CFStringRef)::CFArrayGetValueAtIndex(answer.paths, i);
			bool isDirectory = false;
			if(!StatPath(path, isDirectory))
				return CFSTR("an answered path does not exist");
			if(isDirectory && ((inFlags & kOMCFilePanelCanChooseDirectories) == 0))
				return CFSTR("a folder for a panel that takes only files");
			if(!isDirectory && ((inFlags & kOMCFilePanelCanChooseFiles) == 0))
				return CFSTR("a file for a panel that takes only folders");
			CFObj<CFURLRef> url( CreateFileURL(path, isDirectory) );
			if(url == nullptr)
				return CFSTR("an answered path is not usable");
			::CFArrayAppendValue(urls, url);
		}
	}
	outURLs.Swap(urls);
	return nullptr;
}

// Records the panel and answers it. Returns the chosen URLs (+1), or NULL for canceled.
CFArrayRef
AnswerPanel(bool inIsSave, CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath,
			CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inFlags)
{
	CFObj<CFMutableDictionaryRef> record( CreatePanelRecord(inIsSave, inClientName, inMessage, inDefaultName, inDefaultDirPath,
															inIdentifier, inPrompt, inAllowedContentTypes, inFlags) );
	CFObj<CFMutableArrayRef> urls;
	CFStringRef problem = TakePanelAnswer(inIsSave, inFlags, urls);
	bool answered = (problem == nullptr) && (urls != nullptr) && (::CFArrayGetCount(urls) > 0);
	if(answered)
	{
		CFIndex count = ::CFArrayGetCount(urls);
		CFObj<CFMutableArrayRef> paths( ::CFArrayCreateMutable(kCFAllocatorDefault, count, &kCFTypeArrayCallBacks) );
		for(CFIndex i = 0; i < count; i++)
		{
			CFObj<CFStringRef> path( ::CFURLCopyFileSystemPath((CFURLRef)::CFArrayGetValueAtIndex(urls, i), kCFURLPOSIXPathStyle) );
			if(path != nullptr)
				::CFArrayAppendValue(paths, path);
		}
		::CFDictionarySetValue(record, CFSTR("paths"), paths);
	}
	SetBool(record, CFSTR("canceled"), !answered);
	SetStringIfAny(record, CFSTR("problem"), problem);

	if(sPanelRecords == nullptr)
		sPanelRecords.Adopt( ::CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks) );
	if(sPanelRecords != nullptr)
		::CFArrayAppendValue(sPanelRecords, record);
	OMCNoteEngineActivity();

	if(!answered)
		return nullptr;
	return (CFArrayRef)urls.Detach();
}

// An array of absolute paths, as CFStrings, from a param; NULL with outProblem set when it is not one.
CFArrayRef
CopyAbsolutePaths(CFTypeRef inValue, CFStringRef &outProblem)
{
	outProblem = nullptr;
	CFArrayRef paths = ACFType<CFArrayRef>::DynamicCast(inValue);
	if((paths == nullptr) || (::CFArrayGetCount(paths) == 0))
	{
		outProblem = CFSTR("paths: a non-empty array of absolute paths is required");
		return nullptr;
	}
	CFIndex count = ::CFArrayGetCount(paths);
	for(CFIndex i = 0; i < count; i++)
	{
		CFStringRef path = ACFType<CFStringRef>::DynamicCast(::CFArrayGetValueAtIndex(paths, i));
		if((path == nullptr) || !::CFStringHasPrefix(path, CFSTR("/")))
		{
			outProblem = CFSTR("paths: every path must be absolute");
			return nullptr;
		}
	}
	return (CFArrayRef)::CFRetain(paths);
}

#pragma mark - Methods

char *
HandleAnswer(CFDictionaryRef inParams)
{
	CFStringRef kind = ACFType<CFStringRef>::DynamicCast(::CFDictionaryGetValue(inParams, CFSTR("kind")));
	if(kind == nullptr)
		return CreateErrorReply(kInvalidParams, CFSTR("kind: save, open or cancel is required"));

	PanelAnswer answer;
	if(::CFStringCompare(kind, CFSTR("save"), 0) == kCFCompareEqualTo)
	{
		CFStringRef path = ACFType<CFStringRef>::DynamicCast(::CFDictionaryGetValue(inParams, CFSTR("path")));
		if((path == nullptr) || !::CFStringHasPrefix(path, CFSTR("/")) || (::CFStringGetLength(path) < 2))
			return CreateErrorReply(kInvalidParams, CFSTR("path: an absolute path is required for a save answer"));
		const void *values[] = { path };
		answer.kind = PanelAnswerKind::save;
		answer.paths.Adopt( ::CFArrayCreate(kCFAllocatorDefault, values, 1, &kCFTypeArrayCallBacks) );
	}
	else if(::CFStringCompare(kind, CFSTR("open"), 0) == kCFCompareEqualTo)
	{
		CFStringRef problem = nullptr;
		answer.kind = PanelAnswerKind::open;
		answer.paths.Adopt( CopyAbsolutePaths(::CFDictionaryGetValue(inParams, CFSTR("paths")), problem) );
		if(answer.paths == nullptr)
			return CreateErrorReply(kInvalidParams, (problem != nullptr) ? problem : CFSTR("paths: not usable"));
	}
	else if(::CFStringCompare(kind, CFSTR("cancel"), 0) == kCFCompareEqualTo)
	{
		answer.kind = PanelAnswerKind::cancel;
	}
	else
	{
		return CreateErrorReply(kInvalidParams, CFSTR("kind: must be save, open or cancel"));
	}
	if((answer.kind != PanelAnswerKind::cancel) && (answer.paths == nullptr))
		return CreateErrorReply(kHostRefused, CFSTR("the answer could not be stored"));

	sPanelAnswers.push_back(answer);
	CFObj<CFMutableDictionaryRef> result( CreateMutableDict() );
	SetNumber(result, CFSTR("pending"), (long)sPanelAnswers.size());
	return CreateResultReply(result);
}

char *
HandlePanels(CFDictionaryRef inParams)
{
	CFTypeRef clearValue = ::CFDictionaryGetValue(inParams, CFSTR("clear"));
	CFBooleanRef clear = ACFType<CFBooleanRef>::DynamicCast(clearValue);
	if((clearValue != nullptr) && (clear == nullptr))
		return CreateErrorReply(kInvalidParams, CFSTR("clear: must be true or false"));

	CFObj<CFMutableDictionaryRef> result( CreateMutableDict() );
	if(sPanelRecords != nullptr)
	{
		::CFDictionarySetValue(result, CFSTR("panels"), sPanelRecords);
	}
	else
	{
		CFObj<CFArrayRef> none( ::CFArrayCreate(kCFAllocatorDefault, nullptr, 0, &kCFTypeArrayCallBacks) );
		::CFDictionarySetValue(result, CFSTR("panels"), none);
	}
	SetNumber(result, CFSTR("pending"), (long)sPanelAnswers.size());
	char *reply = CreateResultReply(result); // written out now, before anything is cleared

	if((clear != nullptr) && ::CFBooleanGetValue(clear))
	{
		sPanelRecords.Release();
		sPanelAnswers.clear();
	}
	return reply;
}

char *
HandleStatus()
{
	CFObj<CFMutableDictionaryRef> result( CreateMutableDict() );
	long active = OMCGetUnfinishedTaskManagerCount();
	SetBool(result, CFSTR("idle"), (active <= 0) && (sScheduledRuns <= 0));
	SetNumber(result, CFSTR("activeCommands"), active);
	SetNumber(result, CFSTR("scheduledRuns"), sScheduledRuns);
	SetNumber(result, CFSTR("activity"), (long)OMCGetEngineActivityCount());
	SetNumber(result, CFSTR("skippedPastes"), sSkippedPastes);
	CFObj<CFStringRef> prefix( ::CFStringCreateWithCString(kCFAllocatorDefault, sPasteboardPrefix.c_str(), kCFStringEncodingUTF8) );
	if(prefix != nullptr)
		::CFDictionarySetValue(result, CFSTR("pasteboardPrefix"), prefix);
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

	CFTypeRef openPanelValue = ::CFDictionaryGetValue(inParams, CFSTR("openPanel"));
	CFBooleanRef openPanel = ACFType<CFBooleanRef>::DynamicCast(openPanelValue);
	if((openPanelValue != nullptr) && (openPanel == nullptr))
		return CreateErrorReply(kInvalidParams, CFSTR("openPanel: must be true or false"));

	std::unique_ptr<TestRun> run(new TestRun());
	run->number = (long)sRuns.size() + 1;
	run->commandID.Adopt(commandID, kCFObjRetain);
	run->allowKeyWindow = (keyWindow != nullptr) && ::CFBooleanGetValue(keyWindow);
	run->allowOpenPanel = (openPanel != nullptr) && ::CFBooleanGetValue(openPanel);
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
	if(strcmp(inMethod, "omc.test.answer") == 0)
		return HandleAnswer(params);
	if(strcmp(inMethod, "omc.test.panels") == 0)
		return HandlePanels(params);
	if(strcmp(inMethod, "omc.test.quit") == 0)
		return HandleQuit();
	return CreateErrorReply(-32601, CFSTR("Method not found"));
}

const char *kMethods[] = { "omc.test.status", "omc.test.runCommand", "omc.test.log", "omc.test.answer", "omc.test.panels", "omc.test.quit" };

} // namespace

void
OMCTestHostStartIfRequested(void)
{
	const char *fdText = getenv(kTokenFDVariable);
	const char *pathText = getenv(kBridgePathVariable);
	if((fdText == nullptr) && (pathText == nullptr))
	{
		// A normal launch. The pasteboard tool redirects every pasteboard when it sees this
		// variable, so one inherited from wherever the applet was started must not reach a handler.
		unsetenv(kPasteboardPrefixVariable);
		return;
	}

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

	// The run's own pasteboards: handlers inherit the variable, so the pasteboard tool uses
	// "<prefix>.<name>" for every pasteboard, and the engine reads "<prefix>.general" as the clipboard.
	DecidePasteboards();
	if(sPasteboardPrefixRefused)
		RefuseTestLaunch("OMC_TEST_PASTEBOARD_PREFIX must be 1 to 100 characters of A-Z a-z 0-9 . _ -");
	if(sClipboardName == nullptr)
		RefuseTestLaunch("the test pasteboard name could not be made");
	if(setenv(kPasteboardPrefixVariable, sPasteboardPrefix.c_str(), 1) != 0)
		RefuseTestLaunch("OMC_TEST_PASTEBOARD_PREFIX could not be set for the handlers");

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
	fprintf(stderr, "OMC test launch: bridge at %s, pasteboards %s.*\n", bridgePath.c_str(), sPasteboardPrefix.c_str());
	fflush(stderr);
}

bool
OMCTestHostIsActive(void)
{
	return sActive;
}

CFStringRef
OMCTestHostGetClipboardName(void)
{
	if(sActive)
		return sClipboardName;
	// Before the launch is set up (or while it is): a test launch already reads the run's pasteboard.
	// Once OMCTestHostStartIfRequested has run, the variables are gone, so a normal launch stays here.
	if(sPasteboardsDecided || IsTestLaunchRequested())
	{
		DecidePasteboards();
		return sClipboardName;
	}
	return nullptr;
}

void
OMCTestHostNoteSkippedPaste(void)
{
	sSkippedPastes++;
	OMCNoteEngineActivity();
	fprintf(stderr, "OMC test launch: PASTE_AFTER_EXECUTION skipped (no keystrokes are sent in a test)\n");
	fflush(stderr);
}

CFURLRef
OMCTestHostAnswerSavePanel(CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inFlags)
{
	CFObj<CFArrayRef> urls( AnswerPanel(true, inClientName, inMessage, inDefaultName, inDefaultDirPath, inIdentifier, inPrompt, inAllowedContentTypes, inFlags) );
	if((urls == nullptr) || (::CFArrayGetCount(urls) == 0))
		return nullptr;
	return (CFURLRef)::CFRetain(::CFArrayGetValueAtIndex(urls, 0));
}

CFArrayRef
OMCTestHostAnswerOpenPanel(CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inFlags)
{
	return AnswerPanel(false, inClientName, inMessage, inDefaultName, inDefaultDirPath, inIdentifier, inPrompt, inAllowedContentTypes, inFlags);
}

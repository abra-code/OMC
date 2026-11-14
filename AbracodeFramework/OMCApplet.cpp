//
//  OMCApplet.cpp
//  Abracode
//
//  See OMCApplet.h. The decisions were OMCAppletController.mm's, moved statement for
//  statement; the 0.25 s gathering of opened files uses OMCMainThreadSignal::ScheduleAfter (a
//  newer call cancels the pending one) instead of dispatch_after with a token.
//

#include "OMCApplet.h"
#include "OMCMainThreadSignal.h"
#include "OMCHostInfo.h"
#include "OMCPlatformTypes.h" // noErr
#include <utility>

namespace
{

// While a command call is in progress (a modal open panel included), the app is not reopened
class RunningCommand
{
public:
	explicit RunningCommand(int &ioCount) : mCount(ioCount) { mCount++; }
	~RunningCommand() { mCount--; }
	RunningCommand(const RunningCommand &) = delete;
	RunningCommand &operator=(const RunningCommand &) = delete;
private:
	int &mCount;
};

bool
IsFileURL(CFTypeRef inValue)
{
	if( (inValue == nullptr) || (::CFGetTypeID(inValue) != ::CFURLGetTypeID()) )
		return false;
	CFObj<CFStringRef> scheme( ::CFURLCopyScheme((CFURLRef)inValue) );
	return (scheme != nullptr) && (::CFStringCompare(scheme, CFSTR("file"), kCFCompareCaseInsensitive) == kCFCompareEqualTo);
}

// A file URL with an absolute path: "file:name" is a file URL with no path at all (GLib passes such
// an argument through as given), which no command could use as a file
bool
IsFileURLWithAbsolutePath(CFTypeRef inValue)
{
	if(!IsFileURL(inValue))
		return false;
	CFObj<CFURLRef> absoluteURL( ::CFURLCopyAbsoluteURL((CFURLRef)inValue) );
	CFObj<CFStringRef> path( (absoluteURL != nullptr) ? ::CFURLCopyFileSystemPath(absoluteURL, kCFURLPOSIXPathStyle) : nullptr );
	return (path != nullptr) && ::CFStringHasPrefix(path, CFSTR("/"));
}

// A service's NSSendTypes declaring files in the older way, by pasteboard type: AppletBuilder writes
// "NSFilenamesPboardType" (plist_edit.py), and macOS's OMCService.m takes any service that is not
// for text as one for files
bool
SendsFilesTheOlderWay(CFTypeRef inSendTypes)
{
	if( (inSendTypes == nullptr) || (::CFGetTypeID(inSendTypes) != ::CFArrayGetTypeID()) )
		return false;
	CFIndex typeCount = ::CFArrayGetCount((CFArrayRef)inSendTypes);
	for(CFIndex i = 0; i < typeCount; i++)
	{
		CFTypeRef oneType = ::CFArrayGetValueAtIndex((CFArrayRef)inSendTypes, i);
		if( (oneType != nullptr) && (::CFGetTypeID(oneType) == ::CFStringGetTypeID()) &&
			( (::CFStringCompare((CFStringRef)oneType, CFSTR("NSFilenamesPboardType"), 0) == kCFCompareEqualTo) ||
			  (::CFStringCompare((CFStringRef)oneType, CFSTR("public.file-url"), 0) == kCFCompareEqualTo) ) )
			return true;
	}
	return false;
}

} // namespace

const char *
OMCAppletFileServiceRefusal(CFDictionaryRef inInfo, CFStringRef inCommandID)
{
	if( (inCommandID == nullptr) || (::CFStringGetLength(inCommandID) == 0) )
		return "no command id";
	CFTypeRef services = (inInfo != nullptr) ? ::CFDictionaryGetValue(inInfo, CFSTR("NSServices")) : nullptr;
	if( (services == nullptr) || (::CFGetTypeID(services) != ::CFArrayGetTypeID()) )
		return "the applet declares no services (NSServices in its Info.plist)";
	bool declaredForText = false;
	CFIndex serviceCount = ::CFArrayGetCount((CFArrayRef)services);
	for(CFIndex i = 0; i < serviceCount; i++)
	{
		CFTypeRef service = ::CFArrayGetValueAtIndex((CFArrayRef)services, i);
		if( (service == nullptr) || (::CFGetTypeID(service) != ::CFDictionaryGetTypeID()) )
			continue;
		CFTypeRef userData = ::CFDictionaryGetValue((CFDictionaryRef)service, CFSTR("NSUserData"));
		if( (userData == nullptr) || (::CFGetTypeID(userData) != ::CFStringGetTypeID()) ||
			(::CFStringCompare((CFStringRef)userData, inCommandID, 0) != kCFCompareEqualTo) )
			continue;
		CFTypeRef fileTypes = ::CFDictionaryGetValue((CFDictionaryRef)service, CFSTR("NSSendFileTypes"));
		if( (fileTypes != nullptr) && (::CFGetTypeID(fileTypes) == ::CFArrayGetTypeID()) && (::CFArrayGetCount((CFArrayRef)fileTypes) > 0) )
			return nullptr;
		if(SendsFilesTheOlderWay(::CFDictionaryGetValue((CFDictionaryRef)service, CFSTR("NSSendTypes"))))
			return nullptr;
		declaredForText = true;
	}
	return declaredForText ? "the command is a service for text, not files (no NSSendFileTypes)"
						   : "the applet does not declare the command as a service (NSServices, NSUserData)";
}

OMCApplet::OMCApplet(const OMCAppletActions &inActions)
	: mActions(inActions)
{
}

OMCApplet::~OMCApplet() = default;

bool
OMCApplet::IsOpeningSuppressed() const
{
	return mStartingUp && ((mStartupModifiers & kOMCModifierOption) != 0);
}

void
OMCApplet::DidFinishLaunching()
{
	mStartingUp = false;
	mStartupModifiers = 0;
}

bool
OMCApplet::OpenUntitled()
{
	if(IsOpeningSuppressed())
		return false;

	RunningCommand running(mRunningCommandCount);
	OSStatus err = mActions.runMainCommand(mActions.context, nullptr);
	return (err == noErr);
}

void
OMCApplet::RunMainCommand()
{
	RunningCommand running(mRunningCommandCount);
	(void)mActions.runMainCommand(mActions.context, nullptr);
}

void
OMCApplet::OpenFile(CFURLRef inFileURL)
{
	if(inFileURL != nullptr)
		mActions.noteRecentDocument(mActions.context, inFileURL);

	RunningCommand running(mRunningCommandCount);
	(void)mActions.runMainCommand(mActions.context, inFileURL);
}

void
OMCApplet::OpenFiles(CFArrayRef inFileURLs)
{
	if(inFileURLs == nullptr)
		return;

	CFIndex fileCount = ::CFArrayGetCount(inFileURLs);
	for(CFIndex i = 0; i < fileCount; i++)
	{
		CFTypeRef oneFileURL = ::CFArrayGetValueAtIndex(inFileURLs, i);
		if( (oneFileURL != nullptr) && (::CFGetTypeID(oneFileURL) == ::CFURLGetTypeID()) )
			mActions.noteRecentDocument(mActions.context, (CFURLRef)oneFileURL);
	}

	RunningCommand running(mRunningCommandCount);
	(void)mActions.runMainCommand(mActions.context, inFileURLs);
}

void
OMCApplet::OpenURLs(CFArrayRef inURLs)
{
	if(IsOpeningSuppressed() || (inURLs == nullptr))
		return;

	// Only files are opened here. A URL on the applet's own scheme belongs to HandleURL and its
	// rules, and must not become the main command's file context by another route.
	CFIndex fileCount = 0;
	CFIndex urlCount = ::CFArrayGetCount(inURLs);
	for(CFIndex i = 0; i < urlCount; i++)
	{
		CFTypeRef oneURL = ::CFArrayGetValueAtIndex(inURLs, i);
		if(!IsFileURL(oneURL))
			continue;
		if(mPendingFiles == nullptr)
			mPendingFiles.Adopt( ::CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks) );
		if(mPendingFiles == nullptr)
			return;
		::CFArrayAppendValue(mPendingFiles, oneURL);
		fileCount++;
	}
	if(fileCount == 0)
		return;

	// The newest call wins: destroying the pending one cancels it
	mGatherCall = OMCMainThreadSignal::ScheduleAfter(0.25, OpenGatheredFiles, this);
}

void
OMCApplet::OpenGatheredFiles(void *inContext)
{
	OMCApplet *self = (OMCApplet *)inContext;
	std::unique_ptr<OMCScheduledCall> finishedCall( std::move(self->mGatherCall) ); // ends with this call

	// The timer also fires in a nested run loop of the command a previous gathering is running (a
	// modal dialog, WaitPass). The dispatch_after block it replaced did not: a main-queue block does
	// not run inside another one. Files dropped meanwhile open after that command returns, as before.
	if(self->mOpeningGatheredFiles)
	{
		self->mGatheredFilesWaiting = true;
		return;
	}

	self->mOpeningGatheredFiles = true;
	do
	{
		self->mGatheredFilesWaiting = false;

		CFObj<CFArrayRef> filesToProcess;
		if(self->mPendingFiles != nullptr)
		{
			filesToProcess.Adopt( ::CFArrayCreateCopy(kCFAllocatorDefault, self->mPendingFiles) );
			::CFArrayRemoveAllValues(self->mPendingFiles);
		}

		if( (filesToProcess != nullptr) && (::CFArrayGetCount(filesToProcess) > 0) )
		{
			self->OpenFiles(filesToProcess);
			self->mActions.didOpenGatheredFiles(self->mActions.context);
		}
	}
	// Again for files whose gathering ended during the command, unless a newer gathering is still pending
	while(self->mGatheredFilesWaiting && (self->mGatherCall == nullptr));
	self->mOpeningGatheredFiles = false;
}

void
OMCApplet::HandleURL(CFStringRef inURL)
{
	if(inURL == nullptr)
		return;

	// A URL is untrusted input - any web page, document or application can send one.
	// OMCRunCommandForURL applies the rules: which commands a URL may run and with what context.
	RunningCommand running(mRunningCommandCount);
	mActions.runURL(mActions.context, inURL);
}

OSStatus
OMCApplet::RunService(CFStringRef inCommandID, CFArrayRef inURLs, CFDictionaryRef inInfo, const char **outRefusal)
{
	const char *refusal = nullptr;
	CFObj<CFMutableArrayRef> fileURLs;
	if(mActions.runService == nullptr)
	{
		refusal = "this platform makes no service requests";
	}
	else
	{
		refusal = OMCAppletFileServiceRefusal(inInfo, inCommandID);
	}
	if(refusal == nullptr)
	{
		// Only files: a service on files is never handed a URL on another scheme as a file
		fileURLs.Adopt( ::CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks) );
		CFIndex urlCount = (inURLs != nullptr) ? ::CFArrayGetCount(inURLs) : 0;
		for(CFIndex i = 0; i < urlCount; i++)
		{
			CFTypeRef oneURL = ::CFArrayGetValueAtIndex(inURLs, i);
			if( (fileURLs != nullptr) && IsFileURLWithAbsolutePath(oneURL) )
				::CFArrayAppendValue(fileURLs, oneURL);
		}
		if( (fileURLs == nullptr) || (::CFArrayGetCount(fileURLs) == 0) )
			refusal = "a service runs with files, and none were given";
	}
	if(outRefusal != nullptr)
		*outRefusal = refusal;
	if(refusal != nullptr)
		return errAEEventNotPermitted;

	RunningCommand running(mRunningCommandCount);
	return mActions.runService(mActions.context, inCommandID, fileURLs);
}

bool
OMCApplet::ShouldHandleReopen(bool inHasVisibleWindows, int inHostedWindowCount, long inAppWindowCount) const
{
	if(mRunningCommandCount > 0) //some command is running, do not reopen
		return false;

	if(!inHasVisibleWindows) //we don't trust hasVisibleWindows value, it probably only applies to document windows
	{
		if(inHostedWindowCount > 0) // the framework's hosted windows; hasVisibleWindows misses panels
			return false;
		if(inAppWindowCount == 0)
			return true;
	}
	return false;
}

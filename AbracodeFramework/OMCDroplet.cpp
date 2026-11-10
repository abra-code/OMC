//
//  OMCDroplet.cpp
//  Abracode
//
//  See OMCDroplet.h. The decisions were OMCDropletController.mm's, moved statement for
//  statement; the 0.25 s gathering of opened files uses OMCMainThreadSignal::ScheduleAfter (a
//  newer call cancels the pending one) instead of dispatch_after with a token.
//

#include "OMCDroplet.h"
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

} // namespace

OMCDroplet::OMCDroplet(const OMCDropletActions &inActions)
	: mActions(inActions)
{
}

OMCDroplet::~OMCDroplet() = default;

bool
OMCDroplet::IsOpeningSuppressed() const
{
	return mStartingUp && ((mStartupModifiers & kOMCModifierOption) != 0);
}

void
OMCDroplet::DidFinishLaunching()
{
	mStartingUp = false;
	mStartupModifiers = 0;
}

bool
OMCDroplet::OpenUntitled()
{
	if(IsOpeningSuppressed())
		return false;

	RunningCommand running(mRunningCommandCount);
	OSStatus err = mActions.runMainCommand(mActions.context, nullptr);
	return (err == noErr);
}

void
OMCDroplet::RunMainCommand()
{
	RunningCommand running(mRunningCommandCount);
	(void)mActions.runMainCommand(mActions.context, nullptr);
}

void
OMCDroplet::OpenFile(CFURLRef inFileURL)
{
	if(inFileURL != nullptr)
		mActions.noteRecentDocument(mActions.context, inFileURL);

	RunningCommand running(mRunningCommandCount);
	(void)mActions.runMainCommand(mActions.context, inFileURL);
}

void
OMCDroplet::OpenFiles(CFArrayRef inFileURLs)
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
OMCDroplet::OpenURLs(CFArrayRef inURLs)
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
OMCDroplet::OpenGatheredFiles(void *inContext)
{
	OMCDroplet *self = (OMCDroplet *)inContext;
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
OMCDroplet::HandleURL(CFStringRef inURL)
{
	if(inURL == nullptr)
		return;

	// A URL is untrusted input - any web page, document or application can send one.
	// OMCRunCommandForURL applies the rules: which commands a URL may run and with what context.
	RunningCommand running(mRunningCommandCount);
	mActions.runURL(mActions.context, inURL);
}

bool
OMCDroplet::ShouldHandleReopen(bool inHasVisibleWindows, int inHostedWindowCount, long inAppWindowCount) const
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

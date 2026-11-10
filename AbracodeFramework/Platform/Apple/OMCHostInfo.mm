//
//  OMCHostInfo.mm
//  Abracode
//
//  The macOS implementation of Platform/OMCHostInfo.h: NSWorkspace, NSRunningApplication,
//  NSProcessInfo and the current CGEvent flags.
//

#import <Cocoa/Cocoa.h>
#include "OMCHostInfo.h"
#include "CFObj.h"

CFStringRef OMCCopyFrontAppName()
{
    NSRunningApplication *frontmostApplication = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *appName = [frontmostApplication localizedName];
    return (CFStringRef)CFBridgingRetain(appName);
}

CFStringRef OMCCopyHostAppName()
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *appName = [mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if(appName == nil)
        appName = [mainBundle objectForInfoDictionaryKey:@"CFBundleName"];
    return (CFStringRef)CFBridgingRetain(appName);
}

CFStringRef OMCCopyFrontAppBundleIdentifier()
{
    NSRunningApplication *frontmostApplication = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *appBundleID = [frontmostApplication bundleIdentifier];
    return (CFStringRef)CFBridgingRetain(appBundleID);
}

pid_t OMCGetFrontAppPID()
{
    NSRunningApplication *frontmostApplication = [[NSWorkspace sharedWorkspace] frontmostApplication];
    return [frontmostApplication processIdentifier];
}

CFStringRef OMCCopyAppNameForPID(pid_t pid)
{
    NSRunningApplication *pidApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if(pidApplication != nil)
    {
        NSString *appName = [pidApplication localizedName];
        return (CFStringRef)CFBridgingRetain(appName);
    }

    return nullptr;
}

bool OMCRunningInRegularGUIApp()
{
    NSRunningApplication *currentApp = [NSRunningApplication currentApplication];
    NSApplicationActivationPolicy appPolicy = [currentApp activationPolicy];
    return (appPolicy == NSApplicationActivationPolicyRegular);
}

void OMCRefreshFileInFinder(CFStringRef filePath)
{
    //Apple docs say the usage of this API is "discouraged" but it is not formally deprecated (?)
    //let's give it a shot - if it works: great; if not, not a big deal, this is not critical
    if(filePath != nullptr)
    {
        [[NSWorkspace sharedWorkspace] noteFileSystemChanged:(__bridge NSString*)filePath];
    }
}

void
OMCGetOperatingSystemVersion(long* outMajorVersion, long* outMinorVersion, long* outPatchVersion)
{
    NSOperatingSystemVersion osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    *outMajorVersion = osVersion.majorVersion;
    *outMinorVersion = osVersion.minorVersion;
    *outPatchVersion = osVersion.patchVersion;
}

OMCModifierKeys
OMCGetKeyboardModifiers()
{
	CGEventFlags flags = 0;
	CFObj<CGEventRef> eventRef( CGEventCreate(nullptr /*default event source*/) );
	if(eventRef != nullptr)
		flags = CGEventGetFlags(eventRef);

	OMCModifierKeys outModifiers = 0;
	if((flags & kCGEventFlagMaskAlphaShift) != 0)
		outModifiers |= kOMCModifierCapsLock;
	if((flags & kCGEventFlagMaskShift) != 0)
		outModifiers |= kOMCModifierShift;
	if((flags & kCGEventFlagMaskControl) != 0)
		outModifiers |= kOMCModifierControl;
	if((flags & kCGEventFlagMaskAlternate) != 0)
		outModifiers |= kOMCModifierOption;
	if((flags & kCGEventFlagMaskCommand) != 0)
		outModifiers |= kOMCModifierCommand;
	return outModifiers;
}

// Brings this process to the front if it is not there already, and the previous front app back
// at the end of the scope
StSwitchToFront::StSwitchToFront(bool inRestore /*= true*/) noexcept
{
    @autoreleasepool
    {
        NSRunningApplication *currentApp = [NSRunningApplication currentApplication];
        BOOL isCurrAppActive = [currentApp isActive];
        if(!isCurrAppActive)
        {
            if(inRestore)
            {
                NSRunningApplication *frontmostApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
                mPreviousFrontAppPID = [frontmostApp processIdentifier];
            }
            /*BOOL isOK =*/ [currentApp activateWithOptions:NSApplicationActivateAllWindows];
        }
    }
}

StSwitchToFront::~StSwitchToFront(void) noexcept
{
    @autoreleasepool
    {
        if(mPreviousFrontAppPID != 0)
        {
            NSRunningApplication *previousFrontApp = [NSRunningApplication runningApplicationWithProcessIdentifier:mPreviousFrontAppPID];
            if(previousFrontApp != nil)
            {
                /*BOOL isOK =*/ [previousFrontApp activateWithOptions:NSApplicationActivateAllWindows];
            }
        }
    }
}

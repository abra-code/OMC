#include "OMCHelpers.h"
#include "CFObj.h"

CFStringRef CopyFrontAppName()
{
    NSRunningApplication *frontmostApplication = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *appName = [frontmostApplication localizedName];
    return (CFStringRef)CFBridgingRetain(appName);
}


CFStringRef CopyHostAppName()
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *appName = [mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if(appName == nil)
        appName = [mainBundle objectForInfoDictionaryKey:@"CFBundleName"];
    return (CFStringRef)CFBridgingRetain(appName);
}


CFStringRef CopyFrontAppBundleIdentifier()
{
    NSRunningApplication *frontmostApplication = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *appBundleID = [frontmostApplication bundleIdentifier];
    return (CFStringRef)CFBridgingRetain(appBundleID);
}

pid_t GetFrontAppPID()
{
    NSRunningApplication *frontmostApplication = [[NSWorkspace sharedWorkspace] frontmostApplication];
    return [frontmostApplication processIdentifier];
}

CFStringRef CopyAppNameForPID(pid_t pid)
{
    NSRunningApplication *pidApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if(pidApplication != nil)
    {
        NSString *appName = [pidApplication localizedName];
        return (CFStringRef)CFBridgingRetain(appName);
    }

    return nullptr;
}


bool RunningInRegularGUIApp()
{
    NSRunningApplication *currentApp = [NSRunningApplication currentApplication];
    NSApplicationActivationPolicy appPolicy = [currentApp activationPolicy];
    return (appPolicy == NSApplicationActivationPolicyRegular);
}

void RefreshFileInFinder(CFStringRef filePath)
{
    //Apple docs say the usage of this API is "discouraged" but it is not formally deprecated (?)
    //let's give it a shot - if it works: great; if not, not a big deal, this is not critical
    if(filePath != nullptr)
    {
        [[NSWorkspace sharedWorkspace] noteFileSystemChanged:(__bridge NSString*)filePath];
    }
}

void
GetOperatingSystemVersion(long* outMajorVersion, long* outMinorVersion, long* outPatchVersion)
{
    NSOperatingSystemVersion osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    *outMajorVersion = osVersion.majorVersion;
    *outMinorVersion = osVersion.minorVersion;
    *outPatchVersion = osVersion.patchVersion;
}

CGEventFlags
GetKeyboardModifiers()
{
	CGEventFlags outModifiers = 0;
	CGEventRef eventRef = CGEventCreate(nullptr /*default event source*/);
	if(eventRef != nullptr)
	{
		outModifiers = CGEventGetFlags(eventRef);
		CFRelease(eventRef);
	}
	return outModifiers;
}


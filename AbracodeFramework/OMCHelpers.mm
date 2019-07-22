#include "OMCHelpers.h"
#include "CFObj.h"

CFStringRef CopyFrontAppName()
{
    @autoreleasepool
    {
        NSRunningApplication *frontmostApplication = [[NSWorkspace sharedWorkspace] frontmostApplication];
        NSString *appName = [frontmostApplication localizedName];
        [appName retain];
        return (CFStringRef)appName;
   }
}


CFStringRef CopyHostAppName()
{
    @autoreleasepool
    {
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *appName = [mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        if(appName == nil)
            appName = [mainBundle objectForInfoDictionaryKey:@"CFBundleName"];
        [appName retain];
        return (CFStringRef)appName;
    }
}


CFStringRef CopyFrontAppBundleIdentifier()
{
    @autoreleasepool
    {
        NSRunningApplication *frontmostApplication = [[NSWorkspace sharedWorkspace] frontmostApplication];
        NSString *appBundleID = [frontmostApplication bundleIdentifier];
        [appBundleID retain];
        return (CFStringRef)appBundleID;
    }
}

pid_t GetFrontAppPID()
{
    @autoreleasepool
    {
        NSRunningApplication *frontmostApplication = [[NSWorkspace sharedWorkspace] frontmostApplication];
        return [frontmostApplication processIdentifier];
    }
}

CFStringRef CopyAppNameForPID(pid_t pid)
{
    @autoreleasepool
    {
        NSRunningApplication *pidApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if(pidApplication != nil)
        {
            NSString *appName = [pidApplication localizedName];
            [appName retain];
            return (CFStringRef)appName;
        }
    }
    return nullptr;
}


bool RunningInRegularGUIApp()
{
    @autoreleasepool
    {
        NSRunningApplication *currentApp = [NSRunningApplication currentApplication];
        NSApplicationActivationPolicy appPolicy = [currentApp activationPolicy];
        return (appPolicy == NSApplicationActivationPolicyRegular);
    }
}

void RefreshFileInFinder(CFStringRef filePath)
{
    @autoreleasepool
    {
        //Apple docs say the usage of this API is "discouraged" but it is not formally deprecated (?)
        //let's give it a shot - if it works: great; if not, not a big deal, this is not critical
        if(filePath != nullptr)
            [[NSWorkspace sharedWorkspace] noteFileSystemChanged:(NSString*)filePath];
    }
}

void
GetOperatingSystemVersion(long* outMajorVersion, long* outMinorVersion, long* outPatchVersion)
{
    @autoreleasepool
    {
        NSOperatingSystemVersion osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
        *outMajorVersion = osVersion.majorVersion;
        *outMinorVersion = osVersion.minorVersion;
        *outPatchVersion = osVersion.patchVersion;
    }
}


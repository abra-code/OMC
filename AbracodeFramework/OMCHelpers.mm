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

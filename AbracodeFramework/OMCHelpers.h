
#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h> // CGEventFlags
#include <unistd.h>

#ifdef __cplusplus
extern "C" {
#endif

CFStringRef CopyHostAppName();
CFStringRef CopyFrontAppName();
CFStringRef CopyFrontAppBundleIdentifier();
pid_t GetFrontAppPID();
CFStringRef CopyAppNameForPID(pid_t pid);
bool RunningInRegularGUIApp();

void RefreshFileInFinder(CFStringRef filePath);
void GetOperatingSystemVersion(long* outMajorVersion, long* outMinorVersion, long* outPatchVersion);

CGEventFlags GetKeyboardModifiers();

#ifdef __cplusplus
}
#endif


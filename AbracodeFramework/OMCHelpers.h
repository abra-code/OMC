
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

CFStringRef CopyHostAppName();
CFStringRef CopyFrontAppName();
CFStringRef CopyFrontAppBundleIdentifier();
pid_t GetFrontAppPID();
CFStringRef CopyAppNameForPID(pid_t pid);

void RefreshFileInFinder(CFStringRef filePath);

#ifdef __cplusplus
}
#endif


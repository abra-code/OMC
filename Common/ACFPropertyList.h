#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

CFPropertyListRef CreatePropertyList(CFURLRef plistURL, CFPropertyListMutabilityOptions mutabilityOptions);
bool WritePropertyList(CFPropertyListRef propertyList, CFURLRef plistURL, CFPropertyListFormat plistFormat);

// Resolves the applet's command description file inside a bundle's Resources directory.
// inFileName may be a full name ("Command.plist"), a bare base name, or NULL (defaults to
// "Command"); any extension on inFileName is ignored. The JSON form ("Command.json") is
// preferred over the plist form ("Command.plist") when both are present, so an applet can
// ship either format. Returns a +1 CFURLRef the caller must release, or NULL if neither exists.
CFURLRef CopyCommandFileURLInBundle(CFBundleRef inBundle, CFStringRef inFileName);

#ifdef __cplusplus
}
#endif



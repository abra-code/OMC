#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// The serialization format of a property list file. Distinct from CFPropertyListFormat
// because JSON is not one of its cases, and because "unknown" is a useful answer for a
// file that does not exist yet.
typedef enum ACFPropertyListFormat
{
	kACFPropertyListFormat_unknown = 0,
	kACFPropertyListFormat_xml,
	kACFPropertyListFormat_binary,
	kACFPropertyListFormat_json
} ACFPropertyListFormat;

// Reads a property list file. The format is taken from the file name extension when that
// extension is one we know (".json" or ".plist"); for any other extension the file's own
// content decides, so a JSON document named "project.pkgbuilderproj" reads as JSON.
CFPropertyListRef CreatePropertyList(CFURLRef plistURL, CFPropertyListMutabilityOptions mutabilityOptions);

// As CreatePropertyList, and additionally reports the format the file turned out to be in,
// so a caller that writes the file back can preserve it. On failure, and for a file that
// does not exist, *outFormat is the best guess from the extension alone (never "unknown",
// so it is always usable as a write format). outFormat may be NULL.
CFPropertyListRef CreatePropertyListAndFormat(CFURLRef plistURL, CFPropertyListMutabilityOptions mutabilityOptions,
												ACFPropertyListFormat *outFormat);

// Writes a property list file in the given format. Pass kACFPropertyListFormat_unknown to
// derive the format from the file name extension, which yields XML for an extension we do
// not know - the only reasonable default for a file with no content to go on.
bool WritePropertyList(CFPropertyListRef propertyList, CFURLRef plistURL, ACFPropertyListFormat plistFormat);

// Resolves the applet's command description file inside a bundle's Resources directory.
// inFileName may be a full name ("Command.plist"), a bare base name, or NULL (defaults to
// "Command"); any extension on inFileName is ignored. The JSON form ("Command.json") is
// preferred over the plist form ("Command.plist") when both are present, so an applet can
// ship either format. Returns a +1 CFURLRef the caller must release, or NULL if neither exists.
CFURLRef CopyCommandFileURLInBundle(CFBundleRef inBundle, CFStringRef inFileName);

#ifdef __cplusplus
}
#endif



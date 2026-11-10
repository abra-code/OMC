//
//  OMCAppletSupportURL.h
//
//  A file or folder inside the applet's own bundle, by its path in the bundle's support files folder:
//  the folder that holds Info.plist, Library and the executable's folder. macOS: Applet.app/Contents.
//  Linux: the bundle itself for the flat layout, Contents for a Contents layout, as CoreFoundation
//  finds them (~/git/AppleCoreLibrariesForLinux/build/probe/cfbundle-layout, 2026-11-09). So no
//  "Contents/" in the engine's own paths: "Library/Python/bin/python3", not
//  "Contents/Library/Python/bin/python3".
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include "CFObj.h"

// The absolute URL of inRelativePath inside the main bundle's support files folder, or NULL when there is no
// main bundle. Whether the item exists is the caller's to check. The caller releases the result.
inline CFURLRef OMCCopyAppletSupportURL(CFStringRef inRelativePath, bool inIsDirectory)
{
	CFBundleRef mainBundle = ::CFBundleGetMainBundle();
	if(mainBundle == nullptr)
		return nullptr;
	CFObj<CFURLRef> supportURL( ::CFBundleCopySupportFilesDirectoryURL(mainBundle) );
	if(supportURL == nullptr)
		return nullptr;
	// CF returns "Contents/" relative to the bundle URL for a Contents layout, and
	// CFURLCopyFileSystemPath of a relative URL is the relative path, so resolve it first
	CFObj<CFURLRef> absoluteSupportURL( ::CFURLCopyAbsoluteURL(supportURL) );
	if(absoluteSupportURL == nullptr)
		return nullptr;
	return ::CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, absoluteSupportURL, inRelativePath, inIsDirectory);
}

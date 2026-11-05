//
//  ACFPath.h
//
//  Path string rules as NSString applied them on macOS, in plain CF so they build on Linux.
//  Shared by AbracodeFramework (OMCStrings) and the command line tools (ACFPropertyList).
//  OMCStringsFoundationParityTests compares each with the NSString method it replaces.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// What NSString's path methods (stringByExpandingTildeInPath, stringByDeletingPathExtension)
// do to every path: runs of "/" become one, and a trailing "/" goes, except for the root itself.
// "." and ".." stay. Retained result; NULL for NULL.
CFStringRef ACFPathCreateWithStandardSlashes(CFStringRef inPath);

// The extension of the last path component, as NSString's pathExtension. Retained result
// (empty when there is none); NULL for NULL.
CFStringRef ACFPathCopyExtension(CFStringRef inPath);

// As NSString's stringByDeletingPathExtension: the path with standard slashes, minus "." and the
// extension ACFPathCopyExtension finds, if any. Retained result; NULL for NULL.
CFStringRef ACFPathCreateDeletingExtension(CFStringRef inPath);

#ifdef __cplusplus
}
#endif

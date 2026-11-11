//
//  OMCFilePropertiesPlatform.h (Linux)
//
//  What the engine asks of a file: its kind, whether it is executable, its display name. The
//  platform half, with a macOS file of the same name in Common/Apple, chosen by the include path
//  like OMCFileModePlatform.h. C++ only.
//
//  Linux: POSIX calls on the URL's path. CFURL's resource properties are not usable from the
//  engine there: the applet launch test crashed in them (a file handed to the applet: a call
//  through a null function pointer under CFDictionaryGetValueIfPresent, on the dictionary
//  CFURLCopyResourcePropertiesForKeys returned). The answers are those of the
//  macOS properties: a symbolic link at the URL is not followed, so it is neither a regular file
//  nor a folder; Linux has no packages.
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include "CFObj.h"
#include <fcntl.h>
#include <limits.h>
#include <sys/stat.h>
#include <unistd.h>

// The path of a file URL, or false (for another scheme too: CFURLGetFileSystemRepresentation would
// give an http URL's path, which names no local file; macOS's properties answer false for it)
static inline bool OMCPlatformFilePath(CFURLRef inURL, char (&outPath)[PATH_MAX])
{
    if(inURL == nullptr)
        return false;
    CFObj<CFStringRef> urlScheme(CFURLCopyScheme(inURL));
    if((urlScheme == nullptr) || (CFStringCompare(urlScheme, CFSTR("file"), kCFCompareCaseInsensitive) != kCFCompareEqualTo))
        return false;
    return CFURLGetFileSystemRepresentation(inURL, true, (UInt8 *)outPath, PATH_MAX);
}

// A regular file, a folder, a package (always false on Linux); not following a symbolic link at
// the URL. Each stays as it was when it cannot be read.
static inline void OMCPlatformGetFileKinds(CFURLRef inURL, bool &outIsRegularFile, bool &outIsDirectory, bool &outIsPackage)
{
    char path[PATH_MAX];
    struct stat info;
    if(!OMCPlatformFilePath(inURL, path) || (lstat(path, &info) != 0))
        return;
    outIsRegularFile = S_ISREG(info.st_mode);
    outIsDirectory = S_ISDIR(info.st_mode);
    outIsPackage = false;
}

// A folder (not following a symbolic link at the URL)
static inline bool OMCPlatformIsDirectory(CFURLRef inURL)
{
    char path[PATH_MAX];
    struct stat info;
    return OMCPlatformFilePath(inURL, path) && (lstat(path, &info) == 0) && S_ISDIR(info.st_mode);
}

// The current process may execute the file (or search the folder), by its effective user and
// group, as kCFURLIsExecutableKey on macOS
static inline bool OMCPlatformIsExecutable(CFURLRef inURL)
{
    char path[PATH_MAX];
    return OMCPlatformFilePath(inURL, path) && (faccessat(AT_FDCWD, path, X_OK, AT_EACCESS) == 0);
}

// The name the system shows for the file (+1), or NULL: the last path component
static inline CFStringRef OMCPlatformCopyFileDisplayName(CFURLRef inURL)
{
    return (inURL != nullptr) ? CFURLCopyLastPathComponent(inURL) : nullptr;
}

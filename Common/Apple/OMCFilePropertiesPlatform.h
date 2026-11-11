//
//  OMCFilePropertiesPlatform.h (Apple)
//
//  What the engine asks of a file: its kind, whether it is executable, its display name. The
//  platform half, with a Linux file of the same name in Common/Linux, chosen by the include path
//  like OMCFileModePlatform.h. C++ only.
//
//  macOS: CFURL's resource properties, as the engine has always asked them.
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include "CFObj.h"
#include "ACFDict.h"

// A regular file, a folder, a package (a folder shown as a file); not following a symbolic link
// at the URL. Each stays as it was when it cannot be read.
static inline void OMCPlatformGetFileKinds(CFURLRef inURL, bool &outIsRegularFile, bool &outIsDirectory, bool &outIsPackage)
{
    const void *keys[] = { kCFURLIsRegularFileKey, kCFURLIsDirectoryKey, kCFURLIsPackageKey };
    CFObj<CFArrayRef> propertyKeys(CFArrayCreate(kCFAllocatorDefault, keys, sizeof(keys)/sizeof(const void *), &kCFTypeArrayCallBacks));
    CFObj<CFDictionaryRef> fileProperties(CFURLCopyResourcePropertiesForKeys(inURL, propertyKeys, nullptr));
    ACFDict propertyDict(fileProperties);
    propertyDict.GetValue(kCFURLIsRegularFileKey, outIsRegularFile);
    propertyDict.GetValue(kCFURLIsDirectoryKey, outIsDirectory);
    propertyDict.GetValue(kCFURLIsPackageKey, outIsPackage);
}

// A folder (not following a symbolic link at the URL)
static inline bool OMCPlatformIsDirectory(CFURLRef inURL)
{
    CFObj<CFBooleanRef> isDirectory;
    return CFURLCopyResourcePropertyForKey(inURL, kCFURLIsDirectoryKey, &isDirectory, nullptr) &&
           (isDirectory != nullptr) && CFBooleanGetValue(isDirectory);
}

// The current process may execute the file (or search the folder)
static inline bool OMCPlatformIsExecutable(CFURLRef inURL)
{
    CFObj<CFErrorRef> error;
    CFObj<CFBooleanRef> isExecutable;
    return CFURLCopyResourcePropertyForKey(inURL, kCFURLIsExecutableKey, &isExecutable, &error) &&
           (isExecutable != nullptr) && CFBooleanGetValue(isExecutable);
}

// The name the system shows for the file (+1), or NULL
static inline CFStringRef OMCPlatformCopyFileDisplayName(CFURLRef inURL)
{
    CFStringRef displayName = nullptr;
    if(CFURLCopyResourcePropertyForKey(inURL, kCFURLLocalizedNameKey, &displayName, nullptr))
        return displayName;
    return nullptr;
}

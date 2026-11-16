//
//  StandardDirectories.h
//  Abracode
//
//  The current user's standard folders, which each platform places differently.
//  Implemented in Platform/Apple/StandardDirectories.m (~/Library); a Linux implementation
//  will use the XDG folders. The engine includes only this header.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// The folder of per-user preference files (macOS: ~/Library/Preferences).
// Caller releases the result; NULL when the folder cannot be found.
CFURLRef OMCCopyPreferencesDirURL(void);

// The folder of per-user application support data (macOS: ~/Library/Application Support),
// created if it does not exist. Caller releases the result; NULL when it cannot be found.
CFURLRef OMCCopyApplicationSupportDirURL(void);

#ifdef __cplusplus
}
#endif

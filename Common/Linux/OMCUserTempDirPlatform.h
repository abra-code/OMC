//
//  OMCUserTempDirPlatform.h (Linux)
//
//  Where the engine keeps its per-user temporary files: the platform half of OMCEngineTempDir.h.
//  Header-only, as the macOS file of the same name in Common/Apple. Not built yet: the Linux
//  port has no build.
//
//  Never /tmp (decided 2026-11-09, OMC/Private/linux_port_plan_review.md D5): it is shared by
//  every user, so a folder someone else made there first could stand in for ours. $TMPDIR is not
//  used either: on Linux it is usually unset, or /tmp.
//

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>    // snprintf
#include <stdlib.h>   // getenv
#include <string.h>   // strlen, memcpy
#include <errno.h>
#include <sys/stat.h> // mkdir
#include <limits.h>   // PATH_MAX
#include "OMCPrivateDirectory.h"

static inline bool OMCPlatformCopyPath(const char *inPath, char *outBuf, size_t bufSize)
{
    size_t len = strlen(inPath);
    if((len == 0) || (len + 1 > bufSize))
        return false;
    memcpy(outBuf, inPath, len + 1);
    return true;
}

// Makes the folder with mode 0700 unless it exists. True when it exists afterwards (as anything:
// the caller checks the folder it ends up using).
static inline bool OMCPlatformMakeDir(const char *inPath)
{
    if(mkdir(inPath, S_IRWXU) == 0)
        return true;
    return (errno == EEXIST);
}

// The per-user temporary folder the engine and the tools it spawns share: $XDG_RUNTIME_DIR
// (per user, mode 0700, made by the login manager and removed at logout), else
// <cache>/omc/tmp, made with mode 0700, where <cache> is $XDG_CACHE_HOME or ~/.cache. Either is
// used only when it is private and on a path no other user can change
// (OMCIsPrivateDirectoryOnSafePath): <cache> may be a link into a folder another user owns, who
// could otherwise replace our folders after they were checked.
static inline bool OMCPlatformUserTempDir(char *outBuf, size_t bufSize)
{
    if((outBuf == NULL) || (bufSize == 0))
        return false;
    outBuf[0] = '\0';

    const char *runtimeDir = getenv("XDG_RUNTIME_DIR");
    if((runtimeDir != NULL) && (runtimeDir[0] == '/') && OMCIsPrivateDirectoryOnSafePath(runtimeDir))
        return OMCPlatformCopyPath(runtimeDir, outBuf, bufSize);

    char cacheDir[PATH_MAX];
    const char *cacheHome = getenv("XDG_CACHE_HOME");
    int n;
    if((cacheHome != NULL) && (cacheHome[0] == '/'))
    {
        n = snprintf(cacheDir, sizeof(cacheDir), "%s", cacheHome);
    }
    else
    {
        const char *home = getenv("HOME");
        if((home == NULL) || (home[0] != '/'))
            return false;
        n = snprintf(cacheDir, sizeof(cacheDir), "%s/.cache", home);
    }
    if((n < 0) || ((size_t)n >= sizeof(cacheDir)))
        return false;

    char omcDir[PATH_MAX];
    n = snprintf(omcDir, sizeof(omcDir), "%s/omc", cacheDir);
    if((n < 0) || ((size_t)n >= sizeof(omcDir)))
        return false;
    char tmpDir[PATH_MAX];
    n = snprintf(tmpDir, sizeof(tmpDir), "%s/tmp", omcDir);
    if((n < 0) || ((size_t)n >= sizeof(tmpDir)))
        return false;

    if(!OMCPlatformMakeDir(cacheDir) || !OMCPlatformMakeDir(omcDir) || !OMCPlatformMakeDir(tmpDir))
        return false;
    if(!OMCIsPrivateDirectoryOnSafePath(tmpDir))
        return false;
    return OMCPlatformCopyPath(tmpDir, outBuf, bufSize);
}

// A per-user temporary folder another app of the same user can read: on Linux every app of the
// user sees the same folders, so the same one.
static inline bool OMCPlatformUserTempDirForOtherApps(char *outBuf, size_t bufSize)
{
    return OMCPlatformUserTempDir(outBuf, bufSize);
}

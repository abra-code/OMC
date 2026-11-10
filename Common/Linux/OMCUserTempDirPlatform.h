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
#include <errno.h>
#include <sys/stat.h> // mkdir
#include <limits.h>   // PATH_MAX
#include "OMCPrivateDirectory.h"

// Makes the folder with mode 0700 unless it exists. True when it exists afterwards (as anything:
// the caller checks the folder it ends up using).
static inline bool OMCPlatformMakeDir(const char *inPath)
{
    if(mkdir(inPath, S_IRWXU) == 0)
        return true;
    return (errno == EEXIST);
}

// The path of the user's cache folder: $XDG_CACHE_HOME when it is absolute, else ~/.cache.
// Neither made nor checked here. False when there is no absolute home or the path does not fit.
static inline bool OMCPlatformUserCacheDirPath(char *outBuf, size_t bufSize)
{
    if((outBuf == NULL) || (bufSize == 0))
        return false;
    outBuf[0] = '\0';

    const char *cacheHome = getenv("XDG_CACHE_HOME");
    int n;
    if((cacheHome != NULL) && (cacheHome[0] == '/'))
    {
        n = snprintf(outBuf, bufSize, "%s", cacheHome);
    }
    else
    {
        const char *home = getenv("HOME");
        if((home == NULL) || (home[0] != '/'))
            return false;
        n = snprintf(outBuf, bufSize, "%s/.cache", home);
    }
    if((n < 0) || ((size_t)n >= bufSize))
    {
        outBuf[0] = '\0';
        return false;
    }
    return true;
}

// The engine's own folder in the user's cache folder, <cache>/omc, made with mode 0700 (and
// <cache> too, when missing) and used only when private and on a path no other user can change
// (OMCResolvePrivateDirectoryOnSafePath). outBuf gets the resolved path, the one checked.
static inline bool OMCPlatformEngineCacheDir(char *outBuf, size_t bufSize)
{
    if((outBuf == NULL) || (bufSize == 0))
        return false;
    outBuf[0] = '\0';

    char cacheDir[PATH_MAX];
    if(!OMCPlatformUserCacheDirPath(cacheDir, sizeof(cacheDir)))
        return false;
    char omcDir[PATH_MAX];
    int n = snprintf(omcDir, sizeof(omcDir), "%s/omc", cacheDir);
    if((n < 0) || ((size_t)n >= sizeof(omcDir)))
        return false;

    if(!OMCPlatformMakeDir(cacheDir) || !OMCPlatformMakeDir(omcDir))
        return false;
    return OMCResolvePrivateDirectoryOnSafePath(omcDir, outBuf, bufSize);
}

// The per-user temporary folder the engine and the tools it spawns share: $XDG_RUNTIME_DIR
// (per user, mode 0700, made by the login manager and removed at logout), else
// <cache>/omc/tmp, made with mode 0700, where <cache> is $XDG_CACHE_HOME or ~/.cache. Either is
// used only when it is private and on a path no other user can change
// (OMCResolvePrivateDirectoryOnSafePath): <cache> may be a link into a folder another user owns,
// who could otherwise replace our folders after they were checked. The path given back is the
// resolved one, the path that was checked, with no links left in it.
static inline bool OMCPlatformUserTempDir(char *outBuf, size_t bufSize)
{
    if((outBuf == NULL) || (bufSize == 0))
        return false;
    outBuf[0] = '\0';

    const char *runtimeDir = getenv("XDG_RUNTIME_DIR");
    if((runtimeDir != NULL) && (runtimeDir[0] == '/') && OMCResolvePrivateDirectoryOnSafePath(runtimeDir, outBuf, bufSize))
        return true;

    char cacheDir[PATH_MAX];
    if(!OMCPlatformUserCacheDirPath(cacheDir, sizeof(cacheDir)))
        return false;

    char omcDir[PATH_MAX];
    int n = snprintf(omcDir, sizeof(omcDir), "%s/omc", cacheDir);
    if((n < 0) || ((size_t)n >= sizeof(omcDir)))
        return false;
    char tmpDir[PATH_MAX];
    n = snprintf(tmpDir, sizeof(tmpDir), "%s/tmp", omcDir);
    if((n < 0) || ((size_t)n >= sizeof(tmpDir)))
        return false;

    if(!OMCPlatformMakeDir(cacheDir) || !OMCPlatformMakeDir(omcDir) || !OMCPlatformMakeDir(tmpDir))
        return false;
    return OMCResolvePrivateDirectoryOnSafePath(tmpDir, outBuf, bufSize);
}

// A per-user temporary folder another app of the same user can read: on Linux every app of the
// user sees the same folders, so the same one.
static inline bool OMCPlatformUserTempDirForOtherApps(char *outBuf, size_t bufSize)
{
    return OMCPlatformUserTempDir(outBuf, bufSize);
}

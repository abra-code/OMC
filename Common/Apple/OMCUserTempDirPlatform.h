//
//  OMCUserTempDirPlatform.h (macOS)
//
//  Where the engine keeps its per-user temporary files: the platform half of OMCEngineTempDir.h.
//  Header-only, because the helper tools (omc_dialog_control, omc_next_command) include
//  OMCEngineTempDir.h without linking the framework. The Linux file of the same name is in
//  Common/Linux; each target's USER_HEADER_SEARCH_PATHS names one of the two folders.
//
//  Never /tmp: it is shared by every user, so a folder someone else made there first could
//  stand in for ours. When neither place below is known, there is no temporary folder.
//

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>   // getenv
#include <string.h>   // strlen, memcpy
#include <unistd.h>   // confstr
#include <limits.h>   // PATH_MAX

static inline bool OMCPlatformCopyPath(const char *inPath, char *outBuf, size_t bufSize)
{
    size_t len = strlen(inPath);
    if((len == 0) || (len + 1 > bufSize))
        return false;
    memcpy(outBuf, inPath, len + 1);
    return true;
}

// The per-user temporary folder the engine and the tools it spawns share: $TMPDIR first,
// because it is inherited from parent to child and, in a sandboxed app, is its container's
// temp folder; else the user's own temporary folder (confstr). Both are private to the user.
static inline bool OMCPlatformUserTempDir(char *outBuf, size_t bufSize)
{
    if((outBuf == NULL) || (bufSize == 0))
        return false;
    outBuf[0] = '\0';

    const char *tmp = getenv("TMPDIR");
    if((tmp != NULL) && (tmp[0] != '\0'))
        return OMCPlatformCopyPath(tmp, outBuf, bufSize);

    char confBuf[PATH_MAX];
    size_t n = confstr(_CS_DARWIN_USER_TEMP_DIR, confBuf, sizeof(confBuf));
    if((n > 0) && (n <= sizeof(confBuf)))
        return OMCPlatformCopyPath(confBuf, outBuf, bufSize);
    return false;
}

// A per-user temporary folder another app of the same user can read, for a file Terminal or
// iTerm reads (the environment setup script): the user's own temporary folder first, because a
// sandboxed app's $TMPDIR is its container, which another app cannot read; else $TMPDIR.
static inline bool OMCPlatformUserTempDirForOtherApps(char *outBuf, size_t bufSize)
{
    if((outBuf == NULL) || (bufSize == 0))
        return false;
    outBuf[0] = '\0';

    char confBuf[PATH_MAX];
    size_t n = confstr(_CS_DARWIN_USER_TEMP_DIR, confBuf, sizeof(confBuf));
    if((n > 0) && (n <= sizeof(confBuf)))
        return OMCPlatformCopyPath(confBuf, outBuf, bufSize);

    const char *tmp = getenv("TMPDIR");
    if((tmp != NULL) && (tmp[0] != '\0'))
        return OMCPlatformCopyPath(tmp, outBuf, bufSize);
    return false;
}

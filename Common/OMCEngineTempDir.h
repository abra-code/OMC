//
//  OMCEngineTempDir.h
//
//  Single source of truth for the engine's private IPC directory and the file paths used to
//  pass data between Abracode.framework (running inside the OMC app) and the helper tools it
//  spawns as descendants: omc_dialog_control and omc_next_command.
//
//  These files are an INTERNAL engine contract. User command scripts must not read, write or
//  rely on them.
//
//  The directory is the per-user temporary directory ($TMPDIR), which is private to the user
//  (mode 0700) - unlike the previous shared, world-writable /tmp/OMC (created 0777 without the
//  sticky bit), which let any local user delete or replace these files, or pre-plant a symlink.
//
//  Why this is also correct under the App Sandbox: the helper tools are spawned as descendants
//  of the OMC app (through omc_popen, which propagates the parent environment to the child), so
//  they inherit the app's $TMPDIR - including, under the sandbox, the app's redirected container
//  temp dir. The framework and the tools therefore resolve the SAME directory in every regime,
//  while an unrelated process (e.g. Terminal) cannot reach it. (This is the opposite of the
//  "source a script in Terminal" case, where Terminal is a separate app and could not.)
//
//  Where that folder is depends on the platform: OMCUserTempDirPlatform.h, in Common/Apple and
//  Common/Linux (each target's USER_HEADER_SEARCH_PATHS names one). Neither falls back to /tmp.
//  The engine's own "OMC" folder in it is used only when it is a folder (not a symbolic link)
//  owned by the current user that no one else may enter (decided 2026-11-09,
//  OMC/Private/linux_port_plan_review.md D5): one that another user made first, or replaced with
//  a link, is refused, and the engine's files are not written or read there.
//
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>   // getenv
#include <string.h>   // strlen, memcpy
#include <stdio.h>    // snprintf
#include <unistd.h>   // geteuid
#include <sys/stat.h> // mkdir, lstat
#include <errno.h>
#include <limits.h>   // PATH_MAX
#include "OMCPrivateDirectory.h"
#include "OMCUserTempDirPlatform.h"

// Writes the per-user temp directory path (no trailing slash) into outBuf: the platform's
// (OMCUserTempDirPlatform.h; macOS: $TMPDIR, which children inherit and which is a sandboxed
// app's container temp, else confstr(_CS_DARWIN_USER_TEMP_DIR); Linux: $XDG_RUNTIME_DIR, else
// ~/.cache/omc/tmp), so the framework and its child tools always agree. No /tmp fallback.
// Returns true on success (outBuf populated and non-empty).
static inline bool OMCGetUserTempDir(char *outBuf, size_t bufSize)
{
    if((outBuf == NULL) || (bufSize == 0))
        return false;

    outBuf[0] = '\0';

    char platformDir[PATH_MAX];
    if(!OMCPlatformUserTempDir(platformDir, sizeof(platformDir)))
        return false;
    const char *tmp = platformDir;

    // copy without any trailing slash(es) for consistent path building below
    size_t len = strlen(tmp);
    while((len > 1) && (tmp[len - 1] == '/'))
        len--;

    if(len + 1 > bufSize) // +1 for the null terminator
        return false;

    memcpy(outBuf, tmp, len);
    outBuf[len] = '\0';
    return true;
}

// Builds "<per-user temp dir>/OMC/<leafName>" into outBuf. Engine files are grouped under an
// "OMC" subdirectory for tidiness/debuggability. If inCreateDir is true the OMC subdirectory
// is created with mode 0700 (private to the current user - never world-writable). Readers pass
// inCreateDir = false; writers pass true. Either way an existing OMC folder must be private
// (OMCIsPrivateDirectory), and a writer's must exist afterwards; a reader may find none (then
// there is nothing to read). Returns true on success.
static inline bool OMCGetEngineTempFilePath(const char *leafName, bool inCreateDir, char *outBuf, size_t bufSize)
{
    if((leafName == NULL) || (outBuf == NULL) || (bufSize == 0))
        return false;

    char dir[PATH_MAX];
    if(!OMCGetUserTempDir(dir, sizeof(dir)))
        return false;

    char omcDir[PATH_MAX];
    int dn = snprintf(omcDir, sizeof(omcDir), "%s/OMC", dir);
    if((dn < 0) || ((size_t)dn >= sizeof(omcDir)))
        return false;

    if(inCreateDir)
    {
        // 0700: private to the current user. No-op (EEXIST) if it already exists; checked below.
        (void)mkdir(omcDir, S_IRWXU);
        if(!OMCIsPrivateDirectory(omcDir))
            return false;
    }
    else
    {
        struct stat info;
        if(lstat(omcDir, &info) == 0)
        {
            if(!OMCIsPrivateDirectory(omcDir))
                return false;
        }
        else if(errno != ENOENT)
        {
            return false;
        }
    }

    int n = snprintf(outBuf, bufSize, "%s/%s", omcDir, leafName);
    return (n > 0) && ((size_t)n < bufSize);
}

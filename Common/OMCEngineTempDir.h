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
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>   // getenv
#include <string.h>   // strlen, memcpy
#include <stdio.h>    // snprintf
#include <unistd.h>   // confstr
#include <sys/stat.h> // mkdir
#include <limits.h>   // PATH_MAX

// Writes the per-user temp directory path (no trailing slash) into outBuf.
// Resolution order, chosen so the framework and its child tools always agree:
//   1. $TMPDIR   - inherited parent->child, and sandbox-correct (container temp when sandboxed)
//   2. confstr(_CS_DARWIN_USER_TEMP_DIR) - canonical per-user temp if $TMPDIR is unset
//   3. /tmp      - last-resort fallback
// Returns true on success (outBuf populated and non-empty).
static inline bool OMCGetUserTempDir(char *outBuf, size_t bufSize)
{
    if((outBuf == NULL) || (bufSize == 0))
        return false;

    outBuf[0] = '\0';

    const char *tmp = getenv("TMPDIR");
    char confBuf[PATH_MAX];
    if((tmp == NULL) || (tmp[0] == '\0'))
    {
        size_t n = confstr(_CS_DARWIN_USER_TEMP_DIR, confBuf, sizeof(confBuf));
        if((n > 0) && (n <= sizeof(confBuf)))
            tmp = confBuf;
        else
            tmp = "/tmp";
    }

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
// inCreateDir = false; writers pass true. Returns true on success.
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
        // 0700: private to the current user. No-op (EEXIST) if it already exists.
        (void)mkdir(omcDir, S_IRWXU);
    }

    int n = snprintf(outBuf, bufSize, "%s/%s", omcDir, leafName);
    return (n > 0) && ((size_t)n < bufSize);
}

//
//  OMCPrivateDirectory.h
//
//  Whether a folder is the current user's alone, for the engine's per-user temporary files
//  (OMCEngineTempDir.h, OMCUserTempDirPlatform.h). Header-only and portable (POSIX).
//

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>   // realpath
#include <string.h>   // strlen, memcpy
#include <unistd.h>   // geteuid
#include <sys/stat.h> // lstat
#include <limits.h>   // PATH_MAX

// True when inPath is a folder (not a symbolic link to one) owned by the current user that no
// one else may read, write or enter. Trailing slashes are ignored: lstat("link/") would follow
// a link, so they are stripped first.
static inline bool OMCIsPrivateDirectory(const char *inPath)
{
    if((inPath == NULL) || (inPath[0] == '\0'))
        return false;
    size_t len = strlen(inPath);
    while((len > 1) && (inPath[len - 1] == '/'))
        len--;
    char path[PATH_MAX];
    if(len >= sizeof(path))
        return false;
    memcpy(path, inPath, len);
    path[len] = '\0';

    struct stat info;
    if(lstat(path, &info) != 0)
        return false;
    return S_ISDIR(info.st_mode) && (info.st_uid == geteuid()) && ((info.st_mode & (S_IRWXG | S_IRWXO)) == 0);
}

// True when inPath leads to a private folder (OMCIsPrivateDirectory) along folders no other user
// can change: after resolving every symbolic link (realpath), each folder above it is owned by
// the current user or by root and is not writable by group or others. Otherwise whoever owns or
// may write a folder above could rename the private folder after it was checked and put their
// own in its place.
static inline bool OMCIsPrivateDirectoryOnSafePath(const char *inPath)
{
    if((inPath == NULL) || (inPath[0] == '\0'))
        return false;
    char resolved[PATH_MAX];
    if(realpath(inPath, resolved) == NULL)
        return false;
    if(!OMCIsPrivateDirectory(resolved))
        return false;

    uid_t user = geteuid();
    size_t len = strlen(resolved);
    // Each folder above: the prefix up to each "/" after the first character, and "/" itself
    for(size_t end = len; end > 0; )
    {
        while((end > 0) && (resolved[end - 1] != '/'))
            end--;
        if(end == 0)
            break;
        size_t parentLen = (end > 1) ? (end - 1) : 1; // "/a/b" -> "/a" -> "/"
        char parent[PATH_MAX];
        memcpy(parent, resolved, parentLen);
        parent[parentLen] = '\0';

        struct stat info;
        if(lstat(parent, &info) != 0)
            return false;
        if(!S_ISDIR(info.st_mode))
            return false;
        if((info.st_uid != user) && (info.st_uid != 0))
            return false;
        if((info.st_mode & (S_IWGRP | S_IWOTH)) != 0)
            return false;

        if(parentLen == 1)
            break;
        end = parentLen;
    }
    return true;
}

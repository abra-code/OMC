//
//  OMCFileModePlatform.h (Linux)
//
//  The modes an atomic write (ACFPropertyList.cpp) gives the file that replaces a path: the
//  platform half, with a macOS file of the same name in Common/Apple, chosen by the include path
//  like OMCUserTempDirPlatform.h.
//
//  Linux: a symbolic link's own mode is always 0777, so keeping it, as macOS does, would make the
//  file written through a link world-writable. A link is replaced by a new file (its target is
//  left alone, as on macOS) whose mode is the target's read and write bits, never looser than 0666
//  less the umask: a link to a private file gives a private file, and no execute or set-ID bit is
//  copied from a file the writer may not own. A dangling link gives 0666 less the umask. A path
//  that is not a link keeps its mode, as on macOS.
//

#pragma once

#include <stdbool.h>
#include <sys/stat.h>

// *outCreateMode: the mode the new file is created with (the umask applies), so its bytes are
// never in a file looser than the one it replaces. True when the new file then gets exactly
// *outKeptMode (permission and set-ID bits) after writing; false when nothing is at inPath or it
// is a symbolic link, and the new file keeps its creation mode.
static inline bool OMCPlatformAtomicWriteModes(const char *inPath, mode_t *outCreateMode, mode_t *outKeptMode)
{
    struct stat existing;
    if(lstat(inPath, &existing) != 0)
    {
        *outCreateMode = 0666;
        return false;
    }
    if(S_ISLNK(existing.st_mode))
    {
        struct stat target;
        *outCreateMode = ((stat(inPath, &target) == 0) && S_ISREG(target.st_mode)) ? (target.st_mode & 0666) : 0666;
        return false;
    }
    *outCreateMode = existing.st_mode & 0777;
    *outKeptMode = existing.st_mode & 07777;
    return true;
}

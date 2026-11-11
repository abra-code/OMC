//
//  OMCFileModePlatform.h (Apple)
//
//  The modes an atomic write (ACFPropertyList.cpp) gives the file that replaces a path: the
//  platform half, with a Linux file of the same name in Common/Linux, chosen by the include path
//  like OMCUserTempDirPlatform.h.
//
//  macOS: NSData's atomic write keeps the mode the path has, taken with lstat, so a symbolic link
//  at the path gives the link's own mode, 0755 on macOS. Kept for parity with Foundation.
//

#pragma once

#include <stdbool.h>
#include <sys/stat.h>

// *outCreateMode: the mode the new file is created with (the umask applies), so its bytes are
// never in a file looser than the one it replaces. True when the new file then gets exactly
// *outKeptMode (permission and set-ID bits) after writing; false when nothing is at inPath, and
// the new file keeps 0666 less the umask.
static inline bool OMCPlatformAtomicWriteModes(const char *inPath, mode_t *outCreateMode, mode_t *outKeptMode)
{
    struct stat existing;
    if(lstat(inPath, &existing) != 0)
    {
        *outCreateMode = 0666;
        return false;
    }
    *outCreateMode = existing.st_mode & 0777;
    *outKeptMode = existing.st_mode & 07777;
    return true;
}

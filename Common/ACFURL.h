#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Removes the file at fileURL (a file or a symbolic link; not a folder). Returns true on success.
bool DeleteFile(CFURLRef fileURL);

#ifdef __cplusplus
}
#endif

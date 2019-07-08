#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

bool DeleteFile(CFURLRef fileURL);

CFURLRef CopyPreferencesDirURL();
CFURLRef CopyApplicationSupportDirURL();

#ifdef __cplusplus
}
#endif



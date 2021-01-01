#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

bool DeleteFile(CFURLRef fileURL);

CFURLRef CopyPreferencesDirURL(void);
CFURLRef CopyApplicationSupportDirURL(void);

#ifdef __cplusplus
}
#endif



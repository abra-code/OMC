#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

CFPropertyListRef CreatePropertyList(CFURLRef plistURL, CFPropertyListMutabilityOptions mutabilityOptions);
bool WritePropertyList(CFPropertyListRef propertyList, CFURLRef plistURL, CFPropertyListFormat plistFormat);

#ifdef __cplusplus
}
#endif



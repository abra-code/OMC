#include "ACFPropertyList.h"
#include "CFObj.h"
#import <Foundation/Foundation.h>

static BOOL IsJSONURL(CFURLRef url)
{
    if (url == NULL)
        return NO;
    BOOL isJSON = NO;
    CFObj<CFStringRef> ext(::CFURLCopyPathExtension(url));
    if (ext != NULL)
    {
        isJSON = (CFStringCompare(ext, CFSTR("json"), kCFCompareCaseInsensitive) == kCFCompareEqualTo);
    }
    return isJSON;
}

CFPropertyListRef CreatePropertyList(CFURLRef plistURL, CFPropertyListMutabilityOptions mutabilityOptions)
{
    if (IsJSONURL(plistURL))
    {
        NSData* data = [NSData dataWithContentsOfURL:(__bridge NSURL *)plistURL];
        if (data == nil)
            return NULL;

        NSJSONReadingOptions options = NSJSONReadingAllowFragments;
        if (mutabilityOptions != kCFPropertyListImmutable)
            options |= NSJSONReadingMutableContainers;

        NSError* error = nil;
        id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:options error:&error];
        if (jsonObject == nil)
        {
            fprintf(stderr, "Error: failed to parse JSON: %s\n", error.localizedDescription.UTF8String);
            return NULL;
        }
        return (__bridge_retained CFTypeRef)jsonObject;
    }

	CFPropertyListRef thePlist = NULL;
    NSData* plistData = [NSData dataWithContentsOfURL:(__bridge NSURL *)plistURL];
    if(plistData != nil)
    {
        thePlist = CFPropertyListCreateWithData(kCFAllocatorDefault, (__bridge CFDataRef)plistData, mutabilityOptions, NULL, NULL);
    }

	return thePlist;
}

bool
WritePropertyList(CFPropertyListRef propertyList, CFURLRef plistURL, CFPropertyListFormat plistFormat)
{
	bool isOK = false;
    if (IsJSONURL(plistURL))
    {
        if (propertyList == NULL || plistURL == NULL) return false;

        id jsonObject = (__bridge id)propertyList;
        NSError* error = nil;
        NSData* jsonData = nil;

        if ([NSJSONSerialization isValidJSONObject:jsonObject])
        {
            jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
        }
        else
        {
            // Scalar fragment root: NSJSONWritingFragmentsAllowed = (1UL << 2), available macOS 13+
            NSJSONWritingOptions fragOpts = NSJSONWritingPrettyPrinted | (NSJSONWritingOptions)(1UL << 2);
            jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject
                                                       options:fragOpts
                                                         error:&error];
        }

        if (jsonData == nil)
        {
            fprintf(stderr, "Error: failed to serialize JSON: %s\n", error.localizedDescription.UTF8String);
            return false;
        }
        isOK = (bool)[jsonData writeToURL:(__bridge NSURL *)plistURL
                                  options:NSDataWritingAtomic
                                    error:NULL];
        return isOK;
    }

    CFDataRef plistData = NULL;
    if(propertyList != NULL)
    {
        plistData = CFPropertyListCreateData(kCFAllocatorDefault, propertyList, plistFormat, 0, NULL);
    }

    if(plistData != NULL)
	{
        NSData *__strong nsData = (NSData *)CFBridgingRelease(plistData);
        isOK = (bool)[nsData writeToURL:(__bridge NSURL *)plistURL
                                options:NSDataWritingAtomic
                                  error:NULL];
	}
	return isOK;
}

#include "ACFPropertyList.h"
#import <Foundation/Foundation.h>

CFPropertyListRef CreatePropertyList(CFURLRef plistURL, CFPropertyListMutabilityOptions mutabilityOptions)
{
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
    CFDataRef plistData = NULL;

    if(propertyList != NULL)
    {
        plistData = CFPropertyListCreateData(kCFAllocatorDefault, propertyList, plistFormat, 0, NULL);
    }
    
    if(plistData != NULL)
	{
        NSData *__strong nsData = (NSData *)CFBridgingRelease(plistData);
        isOK = (bool)[nsData writeToURL:(__bridge NSURL *)plistURL
                                options:0
                                  error:NULL];
	}
	return isOK;
}

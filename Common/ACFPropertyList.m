#include "ACFPropertyList.h"
#import <Foundation/Foundation.h>

CFPropertyListRef CreatePropertyList(CFURLRef plistURL, CFPropertyListMutabilityOptions mutabilityOptions)
{
	CFPropertyListRef thePlist = NULL;

	@autoreleasepool
	{
		NSData* plistData = [NSData dataWithContentsOfURL:(NSURL *)plistURL];
		if(plistData != NULL)
    		thePlist = CFPropertyListCreateWithData(kCFAllocatorDefault, (CFDataRef)plistData, mutabilityOptions, NULL, NULL);
	}

	return thePlist;
}

bool
WritePropertyList(CFPropertyListRef propertyList, CFURLRef plistURL, CFPropertyListFormat plistFormat)
{
	bool isOK = false;
    CFDataRef plistData = NULL;

    if(propertyList != NULL)
       plistData = CFPropertyListCreateData(kCFAllocatorDefault, propertyList, plistFormat, 0, NULL);

    if(plistData != NULL)
	{
		@autoreleasepool
		{
			isOK = (bool)[(NSData *)plistData
							writeToURL:(NSURL *)plistURL
							options:0
							error:NULL];
		}
		CFRelease(plistData);
	}
	return isOK;
}

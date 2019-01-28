//**************************************************************************************
// Filename:	CMUtilsBundleResource.cp
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
//
// Copyright © 2002-2007 Abracode, Inc.  All rights reserved.
//
// Description:	static utilities for Contextual Menu Plugins
//
//
//**************************************************************************************

#include "CMUtils.h"
#include "CFObj.h"
#include "ACFType.h"

CFBundleRef
CMUtils::CFBundleCreate(CFURLRef inBundleURL)
{
	if(inBundleURL == NULL)
		return NULL;

	FSRef newBundleRef;
	Boolean bundleExists = ::CFURLGetFSRef( inBundleURL, &newBundleRef );
	if( !bundleExists )
		return NULL;

	CFArrayRef allLoadedBundles = ::CFBundleGetAllBundles();
	if(allLoadedBundles == NULL)
		return ::CFBundleCreate(kCFAllocatorDefault, inBundleURL);

	CFObj<CFStringRef> newBundleName( ::CFURLCopyLastPathComponent(inBundleURL) );
	if(newBundleName == NULL)
		return NULL;

	FSRef oneBundleRef;
	CFBundleRef oneBundle, foundBundle = NULL;
	CFIndex bundleCount = ::CFArrayGetCount( allLoadedBundles );

	for(CFIndex i = 0; i < bundleCount; i++)
	{
		oneBundle = ACFType<CFBundleRef>::DynamicCast( ::CFArrayGetValueAtIndex( allLoadedBundles, i ) );
		if( oneBundle != NULL )
		{
			CFObj<CFURLRef> oneBundleURL( ::CFBundleCopyBundleURL(oneBundle) );
			if(oneBundleURL != NULL)
			{
				CFObj<CFStringRef> oneBundleName( ::CFURLCopyLastPathComponent( oneBundleURL ) );
				if( oneBundleName != NULL )
				{
					if(::CFStringCompare( newBundleName, oneBundleName, kCFCompareCaseInsensitive ) == kCFCompareEqualTo)
					{
						bundleExists = ::CFURLGetFSRef( oneBundleURL, &oneBundleRef );
						if( bundleExists && (::FSCompareFSRefs( &newBundleRef, &oneBundleRef ) == noErr) )
						{
							foundBundle = oneBundle;
						}
					}
				}
			}
			
			if(foundBundle != NULL)
				break;
		}
	}

	if(foundBundle != NULL)
	{
		::CFRetain(foundBundle);
		return foundBundle;
	}
		
	return ::CFBundleCreate(kCFAllocatorDefault, inBundleURL);
}

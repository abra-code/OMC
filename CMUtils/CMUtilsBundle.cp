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
	if(inBundleURL == nullptr)
		return nullptr;

    CFObj<CFURLRef> absoluteBundleURL = CFURLCopyAbsoluteURL(inBundleURL);
    if(absoluteBundleURL == nullptr)
        return nullptr;

	return ::CFBundleCreate(kCFAllocatorDefault, absoluteBundleURL);
}

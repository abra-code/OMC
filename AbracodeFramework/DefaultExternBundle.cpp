/*
 *  DefaultExternBundle.cpp
 *  OMCApplet
 *
 *  Created by Tomasz Kukielka on 9/8/06.
 *  Copyright 2006 Abracode. All rights reserved.
 *
 */

#include "DefaultExternBundle.h"
#include "CMUtils.h"
#include "CFObj.h"
#include "ACFURL.h"


extern "C"
{

CFURLRef
CreateDefaultExternBundleURL(CFArrayRef inCommandName)
{
	if(inCommandName == NULL)
		return NULL;
	
	CFObj<CFStringRef> staticName( ::CFStringCreateByCombiningStrings( kCFAllocatorDefault, inCommandName, CFSTR("") ) );
	CFObj<CFMutableStringRef> bundleName( ::CFStringCreateMutableCopy( kCFAllocatorDefault, ::CFStringGetLength(staticName) + 4, staticName) );
	if(bundleName == NULL)
		return NULL;
		
	::CFStringAppend( bundleName, CFSTR(".omc") );

	CFObj<CFURLRef> appSupportURL( CopyApplicationSupportDirURL() );
	if(appSupportURL == NULL)
		return NULL;

	CFObj<CFURLRef> omcSupportURL( ::CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, appSupportURL, CFSTR("OnMyCommand"), true /*isDirectory*/) );
	if(omcSupportURL == NULL)
		return NULL;

	return ::CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, omcSupportURL, bundleName, true /*isDirectory*/);
}


//caller responsible for releasing the result if not NULL
//look for ~/Libarary/Application Support/OnMyCommand/CommandName.omc bundle
CFBundleRef
CreateDefaultExternBundleRef(CFArrayRef inCommandName)
{
	CFObj<CFURLRef> externBundleURL( CreateDefaultExternBundleURL(inCommandName) );
	if(externBundleURL == NULL)
		return NULL;

	return CMUtils::CFBundleCreate(externBundleURL);//may be NULL if bundle does not exist, it is fine.
}


CFStringRef
CreateDefaultExternBundleString(CFArrayRef inCommandName)
{
	CFObj<CFURLRef> externBundleURL( CreateDefaultExternBundleURL(inCommandName) );
	if(externBundleURL == NULL)
		return NULL;

	return ::CFURLCopyFileSystemPath(externBundleURL, kCFURLPOSIXPathStyle);
}

};//extern "C"

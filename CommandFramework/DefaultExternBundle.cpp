/*
 *  DefaultExternBundle.cpp
 *  OMCApplet
 *
 *  Created by Tomasz Kukielka on 9/8/06.
 *  Copyright 2006 Abracode. All rights reserved.
 *
 */

#include "DefaultExternBundle.h"
#include "CFObj.h"
#include "StandardDirectories.h"
#include "ACFPropertyList.h"


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

	CFObj<CFURLRef> appSupportURL( OMCCopyApplicationSupportDirURL() );
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

	return CreateBundleFromURL(externBundleURL);//may be NULL if bundle does not exist, it is fine.
}


CFStringRef
CreateDefaultExternBundleString(CFArrayRef inCommandName)
{
	CFObj<CFURLRef> externBundleURL( CreateDefaultExternBundleURL(inCommandName) );
	if(externBundleURL == NULL)
		return NULL;

	return ::CFURLCopyFileSystemPath(externBundleURL, kCFURLPOSIXPathStyle);
}

// The implicit bundle is for commands that have no bundle of their own: the contextual menu host's,
// whose commands come from a command file outside any applet. An applet's commands come with the
// applet; a folder of the same name that anything able to write the user's Application Support
// folder can create must not replace their scripts and windows (an applet keeps its code signature
// while running someone else's script under its privacy grants). An applet that wants an external
// bundle names it with EXTERNAL_BUNDLE_PATH.
bool
OMCHostUsesDefaultExternBundles(CFBundleRef inMainBundle)
{
	if(inMainBundle == NULL)
		return true;
	CFObj<CFURLRef> ownCommandFile( CopyCommandFileURLInBundle(inMainBundle, CFSTR("Command")) );
	return (ownCommandFile == NULL);
}

};//extern "C"

CFBundleRef
CreateBundleFromURL(CFURLRef inBundleURL)
{
	if(inBundleURL == nullptr)
		return nullptr;

	CFObj<CFURLRef> absoluteBundleURL( CFURLCopyAbsoluteURL(inBundleURL) );
	if(absoluteBundleURL == nullptr)
		return nullptr;

	return ::CFBundleCreate(kCFAllocatorDefault, absoluteBundleURL);
}

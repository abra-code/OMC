//**************************************************************************************
// Filename:	CMUtilsHostName.cp
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
//
// Copyright © 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	static utilities for Contextual Menu Plugins
//
//
//**************************************************************************************

#include "CMUtils.h"
#include "DebugSettings.h"

//this function returns the name of the application currently executing the contextual menu plug-in

CFStringRef
CMUtils::CopyHostName()
{
	ProcessSerialNumber psn = { 0, kCurrentProcess };
	CFStringRef outName = NULL;
	OSStatus err = ::CopyProcessName( &psn, &outName);
	if(err == noErr)
		return outName;
	
	return NULL;
}

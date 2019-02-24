//**************************************************************************************
// Filename:	CMUtilsIsFolder.cp
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

OSErr
CMUtils::IsFolder(const FSRef *inRef, Boolean &outIsFolder)
{
	outIsFolder = false;

	if(inRef == NULL)
		return paramErr;

	FSCatalogInfo theInfo;
	OSErr err = ::FSGetCatalogInfo(inRef, kFSCatInfoNodeFlags, &theInfo, NULL, NULL, NULL);
	if ( err == noErr )
	{
		if( (theInfo.nodeFlags & kFSNodeIsDirectoryMask) != 0)
		{
			outIsFolder = true;
		}
	}
	return err;
}

//**************************************************************************************
// Filename:	CMUtilsFileName.cp
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
//
// Copyright � 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	static utilities for Contextual Menu Plugins
//
//
//**************************************************************************************

#include "CMUtils.h"
#include "CFObj.h"

#if COMPILE_FSSPEC_CODE

//copy name to output buffer. just for parity with FSRef version
OSStatus
CMUtils::GetPStringName(const FSSpec *inSpec, Str255 outName)
{
	if(inSpec == NULL)
		return paramErr;
	::BlockMoveData( inSpec->name, outName, inSpec->name[0] + 1);
	return noErr;
}

#endif //COMPILE_FSSPEC_CODE

OSStatus
CMUtils::GetPStringName(const FSRef *inRef, Str255 outName)
{
	if(inRef == NULL)
		return paramErr;

	OSStatus err = noErr;
	FSCatalogInfo theFileInfo;
	FSCatalogInfoBitmap whichInfo = kFSCatInfoTextEncoding;
	HFSUniStr255 uniFileName;
	err = ::FSGetCatalogInfo( inRef, whichInfo, &theFileInfo, &uniFileName, NULL, NULL);
	if( err == noErr )
	{
		if( theFileInfo.textEncodingHint == kTextEncodingUnknown)
			theFileInfo.textEncodingHint = ::CFStringGetSystemEncoding();
		
		CFObj<CFStringRef> theStrRef( ::CFStringCreateWithCharacters( kCFAllocatorDefault, uniFileName.unicode, uniFileName.length ) );
		if(theStrRef != NULL)
		{
			Boolean isOK = ::CFStringGetPascalString(theStrRef, outName, sizeof(Str255), theFileInfo.textEncodingHint);
			err = isOK ? noErr : -1;
		}
	}
	return err;
}

//caller is responsible for deleting the output string
CFStringRef
CMUtils::CreateCFStringNameFromFSRef(const FSRef *inRef)
{
	if(inRef == NULL)
		return NULL;

	FSCatalogInfo theFileInfo;
	FSCatalogInfoBitmap whichInfo = kFSCatInfoNone;
	HFSUniStr255 uniFileName;

	OSStatus err = ::FSGetCatalogInfo( inRef, whichInfo, &theFileInfo, &uniFileName, NULL, NULL);
	if( err == noErr )
		return ::CFStringCreateWithCharacters( kCFAllocatorDefault, uniFileName.unicode, uniFileName.length );

	return NULL;
}

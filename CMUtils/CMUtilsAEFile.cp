//**************************************************************************************
// Filename:	CMUtilsAEFile.cp
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
#include "StAEDesc.h"


OSErr
CMUtils::GetFSRef(const AEDesc &inDesc, FSRef &outRef)
{
	OSErr err = fnfErr;

	if( (inDesc.descriptorType == typeFSRef) && (inDesc.dataHandle != NULL) )
	{//no need to coerce
		TRACE_CSTR1("\tCMUtils::FSRefGetRef without coercing..." );
		err = ::AEGetDescData( &inDesc, &outRef, sizeof(FSRef) );
	}
	else if( (inDesc.descriptorType != typeNull) && (inDesc.dataHandle != NULL) )
	{
		StAEDesc coercedRef;
		err = ::AECoerceDesc( &inDesc, typeFSRef, coercedRef );
		if(err == noErr)
		{
			TRACE_CSTR1("\tCMUtils::FSRefGetRef with coercing..." );
			err = ::AEGetDescData( coercedRef, &outRef, sizeof(FSRef) );
		}
	}

	return err;
}

OSErr
CMUtils::CreateFSRefDesc( const CFURLRef inURL, AEDesc &outAEDesc )
{
	if(inURL == NULL) return fnfErr;
	FSRef fileRef;
	if( ::CFURLGetFSRef(inURL, &fileRef) )
	{
		return ::AECreateDesc( typeFSRef, &fileRef, sizeof(fileRef), &outAEDesc );
	}
	return fnfErr;
}


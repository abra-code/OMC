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

#if COMPILE_FSSPEC_CODE

OSErr
CMUtils::GetFSSpec(const AEDesc &inDesc, FSSpec &outSpec)
{
	OSErr err = fnfErr;

	if( (inDesc.descriptorType == typeFSS) && (inDesc.dataHandle != NULL) )
	{//no need to coerce
		err = ::AEGetDescData( &inDesc, &outSpec, sizeof(FSSpec) );
	}
	else if( (inDesc.descriptorType != typeNull) && (inDesc.dataHandle != NULL) )
	{
		StAEDesc coercedSpec;
		err = ::AECoerceDesc( &inDesc, typeFSS, coercedSpec );
		if(err == noErr)
		{
			err = ::AEGetDescData( coercedSpec, &outSpec, sizeof(FSSpec) );
		}
		else
		{
			DEBUG_PSTR( "\p\tUnable to coerce to FSSpec..." );
		}
	}

	return err;
}

#endif //COMPILE_FSSPEC_CODE


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

#if COMPILE_FSSPEC_CODE
		else
		{// Cannot get an FSRef. Try getting an FSSpec and make an FSRef out of it.
			FSSpec theSpec;
			err = CMUtils::GetFSSpec(inDesc, theSpec);
			if(err == noErr)
			{
				err = ::FSpMakeFSRef( &theSpec, &outRef );
			}
			else
			{
				DEBUG_PSTR( "\p\tUnable to coerce to FSRef..." );
			}
		}
#endif //COMPILE_FSSPEC_CODE
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


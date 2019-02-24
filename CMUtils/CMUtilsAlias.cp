//**************************************************************************************
// Filename:	CMUtilsAlias.cp
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
//#include "StAEDesc.h"


//ripped off MoreAEObjects.c

OSErr
CMUtils::CreateAliasDesc( const AliasHandle inAliasH, AEDesc *outAliasAEDesc )
{
	OSErr	err = noErr;
	
	char	handleState = ::HGetState( (Handle)inAliasH );
	::HLock( (Handle)inAliasH );
	
	err = ::AECreateDesc( typeAlias, *inAliasH, ::GetHandleSize( (Handle)inAliasH ), outAliasAEDesc );
	
	::HSetState( (Handle)inAliasH, handleState );

	return err;
}

OSErr
CMUtils::CreateAliasDesc( const FSRef *inFSRef, AEDesc *outAliasAEDesc )
{
	OSErr			err = noErr;
	AliasHandle		aliasHandle;

	err = ::FSNewAlias( NULL, inFSRef, &aliasHandle );

	if( (err == noErr) && (aliasHandle == NULL) )
	{
		err = paramErr;
	}

	if( err == noErr )
	{
		err = CMUtils::CreateAliasDesc( aliasHandle, outAliasAEDesc );
		::DisposeHandle( (Handle)aliasHandle );
	}

	return err;
}

OSErr
CMUtils::CreateAliasDesc( const CFURLRef inURL, AEDesc *outAliasAEDesc )
{
	if(inURL == NULL) return fnfErr;

	FSRef fileRef;
	if( ::CFURLGetFSRef(inURL, &fileRef) )
		return CreateAliasDesc( &fileRef, outAliasAEDesc );

	return fnfErr;
}


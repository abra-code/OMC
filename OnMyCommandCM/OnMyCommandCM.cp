//**************************************************************************************
// Filename:	OnMyCommandCM.cp
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright � 2002-2005 Abracode, Inc.  All rights reserved.
//
// Description:	Executes Unix commands in Terminal.app or silently
//
//**************************************************************************************


#include "OnMyCommand.h"

#pragma mark -
#pragma mark **** IMPLEMENTATION ****

CFUUIDRef kCMPluginFactoryID = ::CFUUIDGetConstantUUIDWithBytes( NULL,
								0xCD, 0xA5, 0x48, 0xCA, 0xC6, 0xE5, 0x11, 0xD6, 0x82, 0x21, 0x00, 0x30, 0x65, 0xEA, 0xE3, 0xBE );
// "CDA548CA-C6E5-11D6-8221-003065EAE3BE"

ACMPlugin *CreateNewCMPlugin()
{
//	TRACE_CSTR( "CreateNewCMPlugin for OnMyCommandCM\n" );
	return new OnMyCommandCM(NULL);
}


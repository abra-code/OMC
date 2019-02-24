//**************************************************************************************
// Filename:	CMUtilsSendAE.cp
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
#include "DebugSettings.h"


OSErr
CMUtils::SendAppleEventToRunningApplication( FourCharCode appSig, AEEventClass theAEEventClass,
											AEEventID theAEEventID, const AEDesc &directObjectDesc, Boolean waitForReply /*=false*/ )
{
	return CMUtils::SendAEWithObjToRunningApp( appSig, theAEEventClass, theAEEventID, keyDirectObject, directObjectDesc, waitForReply);
}

OSErr
CMUtils::SendAEWithObjToRunningApp( FourCharCode appSig, AEEventClass theAEEventClass, AEEventID theAEEventID,
										AEKeyword keyOne, const AEDesc &objOne, Boolean waitForReply /*=false*/  )
{
	AEDesc emptyDesc;
	
	return CMUtils::SendAEWithThreeObjToRunningApp( appSig, theAEEventClass, theAEEventID, 
													keyOne, objOne, 0, emptyDesc, 0, emptyDesc, waitForReply);
}

OSErr
CMUtils::SendAEWithTwoObjToRunningApp( FourCharCode appSig, AEEventClass theAEEventClass, AEEventID theAEEventID,
										AEKeyword keyOne, const AEDesc &objOne,
										AEKeyword keyTwo, const AEDesc &objTwo, Boolean waitForReply /*=false*/  )
{
	AEDesc emptyDesc;
	
	return CMUtils::SendAEWithThreeObjToRunningApp( appSig, theAEEventClass, theAEEventID, 
													keyOne, objOne, keyTwo, objTwo, 0, emptyDesc, waitForReply);
}

OSErr
CMUtils::SendAEWithThreeObjToRunningApp( FourCharCode appSig, AEEventClass theAEEventClass, AEEventID theAEEventID,
										AEKeyword keyOne, const AEDesc &objOne,
										AEKeyword keyTwo, const AEDesc &objTwo,
										AEKeyword keyThree, const AEDesc &objThree, Boolean waitForReply /*=false*/  )
{
	OSErr theErr = noErr;

	StAEDesc appAddress;
	theErr = ::AECreateDesc(typeApplSignature, &appSig, sizeof(FourCharCode), appAddress);
	if(theErr == noErr)
	{
		StAEDesc appleEvent;

		theErr = ::AECreateAppleEvent(theAEEventClass, theAEEventID,
									appAddress,
									kAutoGenerateReturnID,
									kAnyTransactionID,
									appleEvent);

		if(theErr == noErr)
		{
			if(keyOne != 0)//if key is zero we understand that caller does not want to put an object
			{
				theErr = ::AEPutKeyDesc( appleEvent, keyOne, &objOne);
			}
			
			if(theErr != noErr)
			{
				DEBUG_CSTR("CMUtils::SendAEWithThreeObjToRunningApp. AEPutKeyDesc (keyOne) failed\n" );
				return theErr;
			}

			if(keyTwo != 0)//if key is zero we understand that caller does not want to put an object
			{
				theErr = ::AEPutKeyDesc( appleEvent, keyTwo, &objTwo);
			}
			
			if(theErr != noErr)
			{
				DEBUG_CSTR("CMUtils::SendAEWithThreeObjToRunningApp. AEPutKeyDesc (keyTwo) failed\n" );
				return theErr;
			}

			if(keyThree != 0)//if key is zero we understand that caller does not want to put an object
			{
				theErr = ::AEPutKeyDesc( appleEvent, keyThree, &objThree);
			}
			
			if(theErr != noErr)
			{
				DEBUG_CSTR("CMUtils::SendAEWithThreeObjToRunningApp. AEPutKeyDesc (keyTwo) failed\n" );
				return theErr;
			}

			AESendMode theMode = kAENoReply;
			AEIdleUPP theUpp = NULL;
			
			if(waitForReply)
			{
				theMode = kAEWaitReply;
				//theUpp = NewAEIdleUPP(AEIdleProc);
			}
			
			StAEDesc theAEReply;
			theErr = ::AESend( appleEvent, theAEReply, theMode,
					kAENormalPriority, kAEDefaultTimeout, theUpp, NULL);
		
			if(theUpp != NULL)
			{
				::DisposeAEIdleUPP(theUpp);
			}

			if(theErr == connectionInvalid)
			{
				DEBUG_CSTR("CMUtils::SendAEWithThreeObjToRunningApp. Application is not running\n" );
			}
			else if(theErr != noErr)
			{
				DEBUG_CSTR("CMUtils::SendAEWithThreeObjToRunningApp. AESend failed\n" );
			}
		}
		else
		{
			DEBUG_CSTR("CMUtils::SendAEWithThreeObjToRunningApp. AECreateAppleEvent failed\n" );
		}
	}
	else
	{
		DEBUG_CSTR("CMUtils::SendAEWithThreeObjToRunningApp. Application address not found\n" );
	}
	
	return theErr;
}


OSErr
CMUtils::SendAppleEventToRunningApplication( const char * inAppBundleIDCStr, AEEventClass theAEEventClass,
											AEEventID theAEEventID, const AEDesc &directObjectDesc, Boolean waitForReply /*=false*/ )
{
	return CMUtils::SendAEWithObjToRunningApp( inAppBundleIDCStr, theAEEventClass, theAEEventID, keyDirectObject, directObjectDesc, waitForReply);
}

OSErr
CMUtils::SendAEWithObjToRunningApp( const char * inAppBundleIDCStr, AEEventClass theAEEventClass, AEEventID theAEEventID,
										AEKeyword keyOne, const AEDesc &objOne, Boolean waitForReply /*=false*/  )
{
	AEDesc emptyDesc;
	
	return CMUtils::SendAEWithThreeObjToRunningApp( inAppBundleIDCStr, theAEEventClass, theAEEventID, 
													keyOne, objOne, 0, emptyDesc, 0, emptyDesc, waitForReply);
}

OSErr
CMUtils::SendAEWithTwoObjToRunningApp( const char * inAppBundleIDCStr, AEEventClass theAEEventClass, AEEventID theAEEventID,
										AEKeyword keyOne, const AEDesc &objOne,
										AEKeyword keyTwo, const AEDesc &objTwo, Boolean waitForReply /*=false*/  )
{
	AEDesc emptyDesc;
	
	return CMUtils::SendAEWithThreeObjToRunningApp( inAppBundleIDCStr, theAEEventClass, theAEEventID, 
													keyOne, objOne, keyTwo, objTwo, 0, emptyDesc, waitForReply);
}

OSErr
CMUtils::SendAEWithThreeObjToRunningApp( const char * inAppBundleIDCStr, AEEventClass theAEEventClass, AEEventID theAEEventID,
										AEKeyword keyOne, const AEDesc &objOne,
										AEKeyword keyTwo, const AEDesc &objTwo,
										AEKeyword keyThree, const AEDesc &objThree, Boolean waitForReply /*=false*/  )
{
	if(inAppBundleIDCStr == NULL)
		return paramErr;

	OSErr theErr = noErr;
	StAEDesc appAddress;
	theErr = ::AECreateDesc(typeApplicationBundleID, inAppBundleIDCStr, strlen(inAppBundleIDCStr), appAddress);
	if(theErr == noErr)
	{
		StAEDesc appleEvent;

		theErr = ::AECreateAppleEvent(theAEEventClass, theAEEventID,
									appAddress,
									kAutoGenerateReturnID,
									kAnyTransactionID,
									appleEvent);

		if(theErr == noErr)
		{
			if(keyOne != 0)//if key is zero we understand that caller does not want to put an object
			{
				theErr = ::AEPutKeyDesc( appleEvent, keyOne, &objOne);
			}
			
			if(theErr != noErr)
			{
				DEBUG_CSTR("CMUtils::SendAEWithThreeObjToRunningApp. AEPutKeyDesc (keyOne) failed\n" );
				return theErr;
			}

			if(keyTwo != 0)//if key is zero we understand that caller does not want to put an object
			{
				theErr = ::AEPutKeyDesc( appleEvent, keyTwo, &objTwo);
			}
			
			if(theErr != noErr)
			{
				DEBUG_CSTR("CMUtils::SendAEWithThreeObjToRunningApp. AEPutKeyDesc (keyTwo) failed\n" );
				return theErr;
			}

			if(keyThree != 0)//if key is zero we understand that caller does not want to put an object
			{
				theErr = ::AEPutKeyDesc( appleEvent, keyThree, &objThree);
			}
			
			if(theErr != noErr)
			{
				DEBUG_CSTR("CMUtils::SendAEWithThreeObjToRunningApp. AEPutKeyDesc (keyTwo) failed\n" );
				return theErr;
			}

			AESendMode theMode = kAENoReply;
			AEIdleUPP theUpp = NULL;
			
			if(waitForReply)
			{
				theMode = kAEWaitReply;
				//theUpp = NewAEIdleUPP(AEIdleProc);
			}
			
			StAEDesc theAEReply;
			theErr = ::AESend( appleEvent, theAEReply, theMode,
					kAENormalPriority, kAEDefaultTimeout, theUpp, NULL);
		
			if(theUpp != NULL)
			{
				::DisposeAEIdleUPP(theUpp);
			}

			if(theErr == connectionInvalid)
			{
				DEBUG_CSTR("CMUtils::SendAEWithThreeObjToRunningApp. Application is not running\n" );
			}
			else if(theErr != noErr)
			{
				DEBUG_CSTR("CMUtils::SendAEWithThreeObjToRunningApp. AESend failed\n" );
			}
		}
		else
		{
			DEBUG_CSTR("CMUtils::SendAEWithThreeObjToRunningApp. AECreateAppleEvent failed\n" );
		}
	}
	else
	{
		DEBUG_CSTR("CMUtils::SendAEWithThreeObjToRunningApp. Application address not found\n" );
	}
	
	return theErr;
}

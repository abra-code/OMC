//**************************************************************************************
// Filename:	CMUtilsFinder.cp
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
#include "MoreAppleEvents.h"
//#include "AAEDesc.h"

//send simple event with direct param to Finder
//if you need something more complicated, use the following code as a starting point and stick required descriptions
//into the appleEvent

//if the function returns noErr it does not mean the Finder will process your event
//it just means that the event was sent successfully

OSErr
CMUtils::SendAppleEventToFinder( AEEventClass theAEEventClass, AEEventID theAEEventID, const AEDesc &directObjectDesc, Boolean waitForReply /*=false*/)
{
	return CMUtils::SendAppleEventToRunningApplication( 'MACS', theAEEventClass, theAEEventID, directObjectDesc, waitForReply );
}

OSErr
CMUtils::SendAEWithTwoObjToFinder( AEEventClass theAEEventClass, AEEventID theAEEventID,
									AEKeyword keyOne, const AEDesc &objOne,
									AEKeyword keyTwo, const AEDesc &objTwo, Boolean waitForReply /*=false*/)
{
	return CMUtils::SendAEWithTwoObjToRunningApp( 'MACS', theAEEventClass, theAEEventID, keyOne, objOne, keyTwo, objTwo, waitForReply );
}

OSErr
CMUtils::SendAEWithThreeObjToFinder( AEEventClass theAEEventClass, AEEventID theAEEventID,
									AEKeyword keyOne, const AEDesc &objOne,
									AEKeyword keyTwo, const AEDesc &objTwo,
									AEKeyword keyThree, const AEDesc &objThree, Boolean waitForReply /*=false*/)
{
	return CMUtils::SendAEWithThreeObjToRunningApp( 'MACS', theAEEventClass, theAEEventID, keyOne, objOne, keyTwo, objTwo, keyThree, objThree, waitForReply );
}

#pragma mark -

void
CMUtils::PutFinderObjectToTrash(const AEDesc &directObjectDesc, Boolean waitForReply)
{
	CMUtils::SendAppleEventToFinder( kAEFinderSuite, kAESync, directObjectDesc, waitForReply );
}

void
CMUtils::PutFinderObjectToTrash(const FSRef *inRef, Boolean waitForReply)
{
	if(inRef != NULL)
	{
		StAEDesc fileDesc;
		OSErr err = CMUtils::CreateAliasDesc( inRef, fileDesc );
		if(err == noErr)
		{
			CMUtils::PutFinderObjectToTrash(fileDesc, waitForReply);
		}
	}
}



#pragma mark -

void
CMUtils::UpdateFinderObject(const AEDesc &directObjectDesc, Boolean waitForReply)
{
	CMUtils::SendAppleEventToFinder( kAEFinderSuite, kAESync, directObjectDesc, waitForReply);
}

void
CMUtils::UpdateFinderObject(const FSRef *inRef, Boolean waitForReply)
{
	if(inRef != NULL)
	{
		StAEDesc fileDesc;
		OSErr err = CMUtils::CreateAliasDesc( inRef, fileDesc );
		if(err == noErr)
		{
			CMUtils::UpdateFinderObject( fileDesc, waitForReply);
		}
	}
}


#pragma mark -

void
CMUtils::MoveFinderObjectToFolder(const AEDesc &directObjectDesc, const FSRef *inFolderRef, Boolean waitForReply)
{
	if( inFolderRef != NULL )
	{
		StAEDesc folderDesc;
		OSErr err = CMUtils::CreateAliasDesc( inFolderRef, folderDesc );
		if(err == noErr)
		{
			CMUtils::SendAEWithTwoObjToFinder( kAECoreSuite, kAEMove,
													keyDirectObject, directObjectDesc,
													keyAEDestination, folderDesc, waitForReply);
		}
	}
}


void
CMUtils::MoveFinderObjectToFolder(const FSRef *inFileRef, const FSRef *inFolderRef, Boolean waitForReply)
{
	if( (inFileRef != NULL) && (inFolderRef != NULL) )
	{
		StAEDesc fileDesc;
		OSErr err = CMUtils::CreateAliasDesc( inFileRef, fileDesc );
		if(err == noErr)
		{
			CMUtils::MoveFinderObjectToFolder(fileDesc, inFolderRef, waitForReply);
		}
	}
}


OSStatus
CMUtils::GetInsertionLocationAsAliasDesc(AEDesc &outAliasDesc, AEDesc &outFinderObj)
{
	OSErr err = MoreAETellAppToGetAEDesc('MACS', pInsertionLoc, typeWildCard, &outFinderObj);
	if(err != noErr)
	{
		LOG_CSTR( "OMC->CMUtils::GetInsertionLocation. MoreAETellAppToGetAEDesc failed\n" );

#if 0 //_DEBUG_
		{
			Str255 hexString;
			ByteCount destLen = sizeof(Str255);
			CMUtils::BufToHex( (const unsigned char *)&err, (char *)hexString, sizeof(err), destLen );
			::CopyCStringToPascal( (char *)hexString, hexString);
			DEBUG_PSTR( "\p\tError code is: " );
			DEBUG_PSTR(hexString);
		}
#endif //_DEBUG_
		return err;
	}

#if _DEBUG_
	{
	Str31 debugStr;
	DEBUG_PSTR( "\pGetInsertionLocation: finderObjDesc data type is:" );
	UInt8 *descPtr = (UInt8 *)&(outFinderObj.descriptorType);
	debugStr[0] = 4;
	debugStr[1] = descPtr[0];
	debugStr[2] = descPtr[1];
	debugStr[3] = descPtr[2];
	debugStr[4] = descPtr[3];
	
	DEBUG_PSTR( debugStr );
	}
#endif
	
    err = MoreAETellAppToCoerceAEDescRequestingType('MACS', &outFinderObj, typeAlias, &outAliasDesc);

#if _DEBUG_
	{
	Str31 debugStr;
	DEBUG_PSTR( "\pGetInsertionLocation: outAliasDesc data type is:" );
	UInt8 *descPtr = (UInt8 *)&(outAliasDesc.descriptorType);
	debugStr[0] = 4;
	debugStr[1] = descPtr[0];
	debugStr[2] = descPtr[1];
	debugStr[3] = descPtr[2];
	debugStr[4] = descPtr[3];
	
	DEBUG_PSTR( debugStr );
	}
#endif
	
	return err;
}

//the following is needed for Mac OS 10.3 Finder
//call it when one item is in the list and only when running in Finder
//if you know that selected item is a folder, pass false for doCheckIfFolder to prevent redundant checking

Boolean
CMUtils::IsClickInOpenFinderWindow(const AEDesc *inContext, Boolean doCheckIfFolder)
{
	TRACE_CSTR( "Enter CMUtils::IsClickInOpenFinderWindow\n" );
	if(inContext == NULL)
		return false;
	
	if( (inContext->descriptorType == typeNull) || (inContext->dataHandle == NULL) )
		return false;

	long itemCount = 0;
	OSErr err = ::AECountItems(inContext, &itemCount);
	if( (err != noErr) || (itemCount == 0) || (itemCount > 1))
	{
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. No object or more than one selected\n" );
		return false;
	}

	StAEDesc oneObject;
	AEKeyword theKeyword;
	err = ::AEGetNthDesc(inContext, 1, typeWildCard, &theKeyword, oneObject);//get first item in list
	if (err != noErr)
	{
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. AEGetNthDesc returned error\n" );
		return false;
	}

	FSRef contextRef;
	err = CMUtils::GetFSRef(oneObject, contextRef);
	if(err != noErr)
	{
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. CMUtils::GetFSRef returned error\n" );
		return false;
	}

	if(doCheckIfFolder)
	{
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. Checking if folder selected\n" );
		/*
		//now check if it is a folder. only folders can be containers
		FSCatalogInfo theInfo;
		::BlockZero(&theInfo, sizeof(theInfo));
		err = ::FSGetCatalogInfo( &contextRef, kFSCatInfoNodeFlags, &theInfo, NULL, NULL, NULL);
		if ( err != noErr )
			return false;
		
		if( (theInfo.nodeFlags & kFSNodeIsDirectoryMask) == 0 )
			return false;
		*/

		//now check if it is a folder. only folders can be containers
		//also check for packages - we treat bundles as files
		LSItemInfoRecord itemInfo;
		memset(&itemInfo, 0, sizeof(itemInfo));
		LSRequestedInfo whichInfo = kLSRequestBasicFlagsOnly;
		err = ::LSCopyItemInfoForRef( &contextRef, whichInfo, &itemInfo);
		if( err == noErr )
		{
			if( (itemInfo.flags & kLSItemInfoIsContainer) == 0 )//not a container, we can safely assume the click is not in open folder
			{
				TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. Folder not selected\n" );
				return false;
			}
			//isPackage = ((itemInfo.flags & kLSItemInfoIsPackage) != 0);
		}
		else
		{
			TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. LSCopyItemInfoForRef returned error\n" );
			return false;
		}
	}

	//if we are here it means that the clicked object is a folder
	//now check what folder is reported by Finder as an insertion location
	StAEDesc insertionLocAlias;
	StAEDesc finderObjDesc;

	//there is a bug in Finder 10.3 that it returns non-container items (like plain file)
	//when requested for insertion location in column view
	
	err = CMUtils::GetInsertionLocationAsAliasDesc(insertionLocAlias, finderObjDesc);
	
	if(err != noErr)
	{
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. GetInsertionLocationAsAliasDesc returned error\n" );
		return false;
	}

	FSRef insertionRef;
	err = CMUtils::GetFSRef(insertionLocAlias, insertionRef);

	if(err != noErr)
	{
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. GetFSRef returned error on insertion location\n" );
		return false;
	}

	Boolean refsEqual = (::FSCompareFSRefs(&contextRef, &insertionRef) == noErr);
	
	if(refsEqual)
	{
		FourCharCode viewType = 0;
		err = GetFinderWindowViewType(finderObjDesc, viewType);
		//there is a bug in Finder 10.3 (sic! another one!) that it returns error when asked for view type of window containing application or alias object
		//in this case we interpret that returned error means that our click is indeed on some item
		if(err != noErr)
		{
			TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. GetFinderWindowViewType returned error\n" );
			return false;
		}

		if( viewType == 'clvw' )//in case of column view we always treat it as a click on object
		{
			TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. GetFinderWindowViewType indicates column view, always click on object\n" );
			return false;		//we are not able to distinguish between click on folder and click in folder
		}
		
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow returns true\n" );
	}
	else
	{
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow selection and isertion file refs different\n" );
	}

	return refsEqual;
}

//types:
//'clvw' - column view
// 'icnv' - icon view
//'lsvw' - list view

OSErr
CMUtils::GetFinderWindowViewType(AEDesc &finderObjDesc, FourCharCode &outViewType)
{
	OSErr err = noErr;
	outViewType = 0;

	StAEDesc windowObjDesc;
    err = MoreAETellAppObjectToGetAEDesc('MACS', &finderObjDesc, cContainerWindow, typeWildCard, windowObjDesc);

	if(err != noErr)										
	{
		DEBUG_PSTR( "\pGetFinderWindowViewType->MoreAETellAppObjectToGetAEDesc failed to get container window" );
		return err;
	}

	StAEDesc viewTypeDesc;
    err = MoreAETellAppObjectToGetAEDesc('MACS', windowObjDesc, pView, typeWildCard, viewTypeDesc);

	if(err != noErr)										
	{
		DEBUG_PSTR( "\pGetFinderWindowViewType->MoreAETellAppObjectToGetAEDesc failed to get view type" );
		return err;
	}

#if _DEBUG_
	{
	Str31 debugStr;
	DEBUG_PSTR( "\pGetFinderWindowViewType: viewTypeDesc data type is:" );
	UInt8 *descPtr = (UInt8 *)&(viewTypeDesc.descriptorType);
	debugStr[0] = 4;
	debugStr[1] = descPtr[0];
	debugStr[2] = descPtr[1];
	debugStr[3] = descPtr[2];
	debugStr[4] = descPtr[3];
	
	DEBUG_PSTR( debugStr );	
	}
#endif

	if( ((AEDesc*)viewTypeDesc)->descriptorType == typeEnumerated)
		::AEGetDescData(viewTypeDesc, &outViewType, sizeof(outViewType));

	return err;
}

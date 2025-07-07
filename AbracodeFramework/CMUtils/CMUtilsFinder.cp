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
#include "CFObj.h"

#pragma mark -

//TODO: check if this code still works with Finder in the latest macOS versions

static OSStatus GetInsertionLocationAsAliasDesc(AEDesc &outAliasDesc, AEDesc &outFinderObj)
{
	OSErr err = MoreAETellAppToGetAEDesc('MACS', pInsertionLoc, typeWildCard, &outFinderObj);
	if(err != noErr)
	{
		LOG_CSTR( "OMC->CMUtils::GetInsertionLocation. MoreAETellAppToGetAEDesc failed\n" );

#if 0 //_DEBUG_
		{
			DEBUG_CSTR( "\tError code is: 0x%x\n", (int)err );
		}
#endif //_DEBUG_
		return err;
	}

#if _DEBUG_
	{
	char debugStr[8];
	UInt8 *descPtr = (UInt8 *)&(outFinderObj.descriptorType);
    debugStr[0] = descPtr[0];
    debugStr[1] = descPtr[1];
    debugStr[2] = descPtr[2];
    debugStr[3] = descPtr[3];
    debugStr[4] = 0;
    DEBUG_CSTR( "GetInsertionLocation: finderObjDesc data type is: %s\n", debugStr );
	}
#endif
	
    err = MoreAETellAppToCoerceAEDescRequestingType('MACS', &outFinderObj, typeAlias, &outAliasDesc);

#if _DEBUG_
	{
	char debugStr[8];
	UInt8 *descPtr = (UInt8 *)&(outAliasDesc.descriptorType);
	debugStr[0] = descPtr[0];
	debugStr[1] = descPtr[1];
	debugStr[2] = descPtr[2];
	debugStr[3] = descPtr[3];
    debugStr[4] = 0;
    DEBUG_CSTR( "GetInsertionLocation: outAliasDesc data type is: %s\n", debugStr );
	}
#endif
	
	return err;
}

//types:
//'clvw' - column view
// 'icnv' - icon view
//'lsvw' - list view

static OSErr GetFinderWindowViewType(AEDesc &finderObjDesc, FourCharCode &outViewType)
{
    OSErr err = noErr;
    outViewType = 0;
    
    StAEDesc windowObjDesc;
    err = MoreAETellAppObjectToGetAEDesc('MACS', &finderObjDesc, cContainerWindow, typeWildCard, windowObjDesc);
    
    if(err != noErr)
    {
        DEBUG_CSTR( "GetFinderWindowViewType->MoreAETellAppObjectToGetAEDesc failed to get container window\n" );
        return err;
    }
    
    StAEDesc viewTypeDesc;
    err = MoreAETellAppObjectToGetAEDesc('MACS', windowObjDesc, pView, typeWildCard, viewTypeDesc);
    
    if(err != noErr)
    {
        DEBUG_CSTR( "GetFinderWindowViewType->MoreAETellAppObjectToGetAEDesc failed to get view type\n" );
        return err;
    }
    
#if _DEBUG_
    {
        char debugStr[8];
        UInt8 *descPtr = (UInt8 *)&(viewTypeDesc.descriptorType);
        debugStr[0] = descPtr[0];
        debugStr[1] = descPtr[1];
        debugStr[2] = descPtr[2];
        debugStr[3] = descPtr[3];
        debugStr[4] = 0;
        DEBUG_CSTR( "GetFinderWindowViewType: viewTypeDesc data type is: %s\n", debugStr );
    }
#endif
    
    if( ((AEDesc*)viewTypeDesc)->descriptorType == typeEnumerated)
        ::AEGetDescData(viewTypeDesc, &outViewType, sizeof(outViewType));
    
    return err;
}

//the following is needed for Mac OS 10.3 Finder
//call it when one item is in the list and only when running in Finder
//if you know that selected item is a folder, pass false for doCheckIfFolder to prevent redundant checking

bool
CMUtils::IsClickInOpenFinderWindow(const AEDesc *inAEContext, Boolean doCheckIfFolder) noexcept
{
	TRACE_CSTR( "Enter CMUtils::IsClickInOpenFinderWindow\n" );
	if(inAEContext == nullptr)
		return false;
	
	if( (inAEContext->descriptorType == typeNull) || (inAEContext->dataHandle == nullptr) )
		return false;

	long itemCount = 0;
	OSErr err = ::AECountItems(inAEContext, &itemCount);
	if( (err != noErr) || (itemCount == 0) || (itemCount > 1))
	{
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. No object or more than one selected\n" );
		return false;
	}

	StAEDesc oneObject;
	AEKeyword theKeyword;
	err = ::AEGetNthDesc(inAEContext, 1, typeWildCard, &theKeyword, oneObject);//get first item in list
	if (err != noErr)
	{
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. AEGetNthDesc returned error\n" );
		return false;
	}

    CFObj<CFURLRef> contextURL = CMUtils::CopyURL(oneObject);
	if(contextURL == nullptr)
	{
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. CMUtils::CopyURL returned error\n" );
		return false;
	}

	if(doCheckIfFolder)
	{
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. Checking if folder selected\n" );
        Boolean isDir = CFURLHasDirectoryPath(contextURL);
        if(!isDir)
            return false;
	}

	//if we are here it means that the clicked object is a folder
	//now check what folder is reported by Finder as an insertion location
	StAEDesc insertionLocAlias;
	StAEDesc finderObjDesc;

	//there is a bug in Finder 10.3 that it returns non-container items (like plain file)
	//when requested for insertion location in column view
	
	err = GetInsertionLocationAsAliasDesc(insertionLocAlias, finderObjDesc);
	
	if(err != noErr)
	{
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. GetInsertionLocationAsAliasDesc returned error\n" );
		return false;
	}

    CFObj<CFURLRef> insertionURL = CMUtils::CopyURL(insertionLocAlias);

	if(insertionURL == nullptr)
	{
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow. CopyURL returned error on insertion location\n" );
		return false;
	}

    CFObj<CFURLRef> absoluteContextURL = CFURLCopyAbsoluteURL(contextURL);
    CFObj<CFURLRef> absoluteInsertionURL( CFURLCopyAbsoluteURL(insertionURL) );
 
    if(CFEqual(absoluteContextURL, absoluteInsertionURL)  )
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
        return true;
	}
	else
	{
		TRACE_CSTR( "CMUtils::IsClickInOpenFinderWindow selection and isertion file refs different\n" );
	}

	return false;
}


//**************************************************************************************
// Filename:	NibDialogControl.cp
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright � 2002-2004 Abracode, Inc.  All rights reserved.
//
//
//**************************************************************************************
// Revision History:
// July 21, 2004 - Original
//**************************************************************************************

#include "NibDialogControl.h"
#include "ACFPropertyList.h"
#include "OMCDialog.h"
#include "ACFURL.h"
#include "CFObj.h"
#include "ACFType.h"

//read values and delete the plist file immediately

CFDictionaryRef
ReadControlValuesFromPlist(CFStringRef inDialogUniqueID)
{
    CFObj<CFStringRef> filePathStr( ::CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("/tmp/OMC/%@.plist"), inDialogUniqueID ) );
    if(filePathStr == NULL)
        return NULL;
    
    DEBUG_CFSTR( (CFStringRef)filePathStr );
    
    CFObj<CFURLRef> fileURL( ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, filePathStr, kCFURLPOSIXPathStyle, false) );
    if(fileURL == NULL)
        return NULL;
    
    CFObj<CFPropertyListRef> thePlist( CreatePropertyList(fileURL, kCFPropertyListImmutable) );
    CFDictionaryRef resultDict = ACFType<CFDictionaryRef>::DynamicCast(thePlist);
    if(resultDict != NULL)
        thePlist.Detach();

    (void)DeleteFile(fileURL);

    return resultDict;
}


//get the controlID from __NIB_DIALOG_CONTROL_XXX_VALUE__ or environment variable style OMC_NIB_DIALOG_CONTROL_XXX_VALUE
//TODO: if we implement more control id modifiers they should be added here and masked before being used for searching real IDs
CFStringRef
CreateControlIDFromString(CFStringRef inControlIDString, bool isEnvStyle)
{
	if(inControlIDString == NULL)
		return NULL;
	
//the first part of the string is constant:
	CFStringRef prefixString = isEnvStyle ? CFSTR("OMC_NIB_DIALOG_CONTROL_") : CFSTR("__NIB_DIALOG_CONTROL_");
	CFIndex prefixLen = ::CFStringGetLength(prefixString);
	CFStringRef suffixString = isEnvStyle ? CFSTR("_VALUE") : CFSTR("_VALUE__");
	CFIndex suffixLen  =  ::CFStringGetLength(suffixString);
	
	CFIndex actualLen = ::CFStringGetLength(inControlIDString);

//there needs to be at least one character between prefix and suffix
	if(actualLen < (prefixLen + 1 + suffixLen) )
		return NULL;

	if( ::CFStringHasPrefix(inControlIDString, prefixString) == false)
		return NULL;

	if( ::CFStringHasSuffix(inControlIDString, suffixString) == false)
		return NULL;

	CFRange idStrRange;
	idStrRange.location = prefixLen;
	idStrRange.length = actualLen - prefixLen - suffixLen;
	
	//in OMC 3 it does not have to be a number
	return ::CFStringCreateWithSubstring(kCFAllocatorDefault, inControlIDString, idStrRange);

//	CFObj<CFStringRef> numberStr( ::CFStringCreateWithSubstring(kCFAllocatorDefault, inControlIDString, numberStrRange) );
//	if(numberStr != NULL)
//	{
//		return ::CFStringGetIntValue (numberStr);
//	}
//
//	return NULL;
}

//get the params from __NIB_TABLE_XXX_COLUMN_XXX_VALUE__ or environment variable style OMC_NIB_TABLE_XXX_COLUMN_XXX_VALUE
//TODO: if we implement more control id modifiers they should be added here and masked before being used for searching real IDs
CFStringRef
CreateTableIDAndColumnFromString(CFStringRef inControlIDString, CFObj<CFStringRef> &outColumnIndexStr, bool useAllRows, bool isEnvStyle)
{
	if(inControlIDString == NULL)
		return NULL;
	
//the first part of the string is constant:
	CFStringRef prefixString = isEnvStyle ? CFSTR("OMC_NIB_TABLE_") : CFSTR("__NIB_TABLE_");
	CFIndex prefixLen = ::CFStringGetLength(prefixString);

	CFStringRef columnString = CFSTR("_COLUMN_");
	CFIndex columnLen  =  ::CFStringGetLength(columnString);
	
	CFStringRef suffixString = NULL;
	if( useAllRows )
		suffixString = isEnvStyle ? CFSTR("_ALL_ROWS") : CFSTR("_ALL_ROWS__");
	else
		suffixString = isEnvStyle ? CFSTR("_VALUE") : CFSTR("_VALUE__");

	CFIndex suffixLen  =  ::CFStringGetLength(suffixString);
	
	CFIndex actualLen = ::CFStringGetLength(inControlIDString);

//there needs to be at least one character between prefix and column and one between column and suffix
	if(actualLen < (prefixLen + 1 + columnLen + 1 + suffixLen) )
		return NULL;

	if( ::CFStringHasPrefix(inControlIDString, prefixString) == false)
		return NULL;

	if( ::CFStringHasSuffix(inControlIDString, suffixString) == false)
		return NULL;

	CFRange columnStrRange = ::CFStringFind( inControlIDString, columnString, 0 );
	if(columnStrRange.length != columnLen)
		return NULL;

	CFStringRef controlID = NULL;
	CFRange idStrRange;
	idStrRange.location = prefixLen;
	idStrRange.length = columnStrRange.location - prefixLen;
	if( idStrRange.length > 0)
	{
		controlID = ::CFStringCreateWithSubstring(kCFAllocatorDefault, inControlIDString, idStrRange);
	}

	CFRange numberStrRange;
	numberStrRange.location = columnStrRange.location + columnStrRange.length;
	numberStrRange.length = actualLen - (columnStrRange.location + columnStrRange.length) - suffixLen;
	if( numberStrRange.length > 0 )
	{
		outColumnIndexStr = CFStringCreateWithSubstring(kCFAllocatorDefault, inControlIDString, numberStrRange);
	}
	return controlID;
}

CFStringRef kControlModifierString_AllRows = CFSTR("|ALL_ROWS");

CFStringRef
CreateControlIDByStrippingModifiers(CFStringRef inControlIDWithModifiers, UInt32 &outModifiers)
{
	if(inControlIDWithModifiers == NULL)
		return NULL;

	outModifiers = 0;
	Boolean hasAllRows = CFStringHasSuffix(inControlIDWithModifiers, kControlModifierString_AllRows);
	if(hasAllRows)
	{
		outModifiers |= kControlModifier_AllRows;
	
		CFIndex totalLen = CFStringGetLength(inControlIDWithModifiers);
		CFIndex modifierLen = CFStringGetLength(kControlModifierString_AllRows);
		CFRange mainControlIDRange = CFRangeMake(0, totalLen - modifierLen);
		return CFStringCreateWithSubstring(kCFAllocatorDefault, inControlIDWithModifiers, mainControlIDRange);
	}
		
	CFRetain(inControlIDWithModifiers);
	return inControlIDWithModifiers;
}

CFStringRef
CreateControlIDByAddingModifiers(CFStringRef inControlID, UInt32 inModifiers)
{
	if(inControlID == NULL)
		return NULL;

	if(inModifiers == 0)
	{
		CFRetain(inControlID);
		return inControlID;
	}

	CFObj<CFStringRef> outControlID;
	if( (inModifiers & kControlModifier_AllRows) != 0 )
	{
		outControlID.Adopt( CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@%@"), inControlID, kControlModifierString_AllRows) );
	}
	return outControlID.Detach();
}

// Extract control ID XXX and HTML element ID YYYY from string: OMC_NIB_WEBVIEW_XXX_ELEMENT_YYY_VALUE or __NIB_WEBVIEW_XXX_ELEMENT_YYY_VALUE__

CFStringRef
CreateWebViewIDAndElementIDFromString(CFStringRef inControlIDAndElementIDString, CFObj<CFStringRef> &outElementIDString, bool isEnvStyle)
{
	if(inControlIDAndElementIDString == NULL)
		return NULL;
	
//the first part of the string is constant:
	CFStringRef prefixString = isEnvStyle ? CFSTR("OMC_NIB_WEBVIEW_") : CFSTR("__NIB_WEBVIEW_");
	CFIndex prefixLen = ::CFStringGetLength(prefixString);

	CFStringRef elementString = CFSTR("_ELEMENT_");
	CFIndex elementLen  =  ::CFStringGetLength(elementString);
	
	CFStringRef suffixString = isEnvStyle ? CFSTR("_VALUE") : CFSTR("_VALUE__");
	CFIndex suffixLen  =  ::CFStringGetLength(suffixString);
	
	CFIndex actualLen = ::CFStringGetLength(inControlIDAndElementIDString);

//there needs to be at least one character between prefix and ELEMENT and one between ELEMENT and suffix
	if(actualLen < (prefixLen + 1 + elementLen + 1 + suffixLen) )
		return NULL;

	if( ::CFStringHasPrefix(inControlIDAndElementIDString, prefixString) == false)
		return NULL;

	if( ::CFStringHasSuffix(inControlIDAndElementIDString, suffixString) == false)
		return NULL;

	CFRange elementStrRange = ::CFStringFind( inControlIDAndElementIDString, elementString, 0 );
	if(elementStrRange.length != elementLen)
		return NULL;

	CFStringRef controlID = NULL;
	CFRange idStrRange;
	idStrRange.location = prefixLen;
	idStrRange.length = elementStrRange.location - prefixLen;
	if( idStrRange.length > 0)
	{
		controlID = ::CFStringCreateWithSubstring(kCFAllocatorDefault, inControlIDAndElementIDString, idStrRange);
	}

	CFRange elementIDStrRange;
	elementIDStrRange.location = elementStrRange.location + elementStrRange.length;
	elementIDStrRange.length = actualLen - (elementStrRange.location + elementStrRange.length) - suffixLen;
	if( elementIDStrRange.length > 0 )
	{
		outElementIDString = CFStringCreateWithSubstring(kCFAllocatorDefault, inControlIDAndElementIDString, elementIDStrRange);
	}
	return controlID;
}

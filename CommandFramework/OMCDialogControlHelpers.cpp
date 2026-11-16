//**************************************************************************************
// Filename:	OMCDialogControlHelpers.cpp
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright � 2002-2004 Abracode, Inc.  All rights reserved.
//
//
//**************************************************************************************
// Revision History:
// July 21, 2004 - Original
//**************************************************************************************

#include "OMCDialogControlHelpers.h"
#include "ACFPropertyList.h"
#include "OMCDialog.h"
#include "ACFURL.h"
#include "CFObj.h"
#include "ACFType.h"
#include "OMCEngineTempDir.h"

//read values and delete the plist file immediately

CFDictionaryRef
ReadControlValuesFromPlist(CFStringRef inDialogUniqueID)
{
    if(inDialogUniqueID == NULL)
        return NULL;

    // Engine-internal IPC file in the per-user temp dir (see OMCEngineTempDir.h).
    char uuidBuf[256];
    if( !::CFStringGetCString(inDialogUniqueID, uuidBuf, sizeof(uuidBuf), kCFStringEncodingUTF8) )
        return NULL;

    char leafName[512];
    snprintf(leafName, sizeof(leafName), "%s.plist", uuidBuf);

    char filePath[PATH_MAX];
    if( !OMCGetEngineTempFilePath(leafName, false /*reader: do not create dir*/, filePath, sizeof(filePath)) )
        return NULL;

    CFObj<CFStringRef> filePathStr( ::CFStringCreateWithCString(kCFAllocatorDefault, filePath, kCFStringEncodingUTF8) );
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


// A macro, not a global: on Linux CFSTR cannot initialize anything outside a function
#define kControlModifierString_AllRows CFSTR("|ALL_ROWS")

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

// Extract view ID N from string: OMC_ACTIONUI_VIEW_N_VALUE or __ACTIONUI_VIEW_N_VALUE__
CFStringRef
CreateActionUIViewIDFromString(CFStringRef inActionUIViewIDString, bool isEnvStyle)
{
	if(inActionUIViewIDString == NULL)
		return NULL;

	CFStringRef prefixString = isEnvStyle ? CFSTR("OMC_ACTIONUI_VIEW_") : CFSTR("__ACTIONUI_VIEW_");
	CFIndex prefixLen = ::CFStringGetLength(prefixString);
	CFStringRef suffixString = isEnvStyle ? CFSTR("_VALUE") : CFSTR("_VALUE__");
	CFIndex suffixLen = ::CFStringGetLength(suffixString);

	CFIndex actualLen = ::CFStringGetLength(inActionUIViewIDString);

	if(actualLen < (prefixLen + 1 + suffixLen))
		return NULL;

	if(::CFStringHasPrefix(inActionUIViewIDString, prefixString) == false)
		return NULL;

	if(::CFStringHasSuffix(inActionUIViewIDString, suffixString) == false)
		return NULL;

	CFRange idStrRange;
	idStrRange.location = prefixLen;
	idStrRange.length = actualLen - prefixLen - suffixLen;

	return ::CFStringCreateWithSubstring(kCFAllocatorDefault, inActionUIViewIDString, idStrRange);
}

// Extract view ID N and column index M from: OMC_ACTIONUI_TABLE_N_COLUMN_M_VALUE or __ACTIONUI_TABLE_N_COLUMN_M_VALUE__
CFStringRef
CreateActionUITableIDAndColumnFromString(CFStringRef inControlIDString, CFObj<CFStringRef> &outColumnIndexStr, bool useAllRows, bool isEnvStyle)
{
	if(inControlIDString == NULL)
		return NULL;

	CFStringRef prefixString = isEnvStyle ? CFSTR("OMC_ACTIONUI_TABLE_") : CFSTR("__ACTIONUI_TABLE_");
	CFIndex prefixLen = ::CFStringGetLength(prefixString);

	CFStringRef columnString = CFSTR("_COLUMN_");
	CFIndex columnLen = ::CFStringGetLength(columnString);

	CFStringRef suffixString = NULL;
	if(useAllRows)
		suffixString = isEnvStyle ? CFSTR("_ALL_ROWS") : CFSTR("_ALL_ROWS__");
	else
		suffixString = isEnvStyle ? CFSTR("_VALUE") : CFSTR("_VALUE__");

	CFIndex suffixLen = ::CFStringGetLength(suffixString);

	CFIndex actualLen = ::CFStringGetLength(inControlIDString);

	// need at least one character for view ID and one for column index
	if(actualLen < (prefixLen + 1 + columnLen + 1 + suffixLen))
		return NULL;

	if(::CFStringHasPrefix(inControlIDString, prefixString) == false)
		return NULL;

	if(::CFStringHasSuffix(inControlIDString, suffixString) == false)
		return NULL;

	CFRange columnStrRange = ::CFStringFind(inControlIDString, columnString, 0);
	if(columnStrRange.length != columnLen)
		return NULL;

	CFObj<CFStringRef> controlID;
	CFRange idStrRange;
	idStrRange.location = prefixLen;
	idStrRange.length = columnStrRange.location - prefixLen;
	if(idStrRange.length > 0)
	{
		controlID.Adopt( ::CFStringCreateWithSubstring(kCFAllocatorDefault, inControlIDString, idStrRange) );
	}

	CFRange numberStrRange;
	numberStrRange.location = columnStrRange.location + columnStrRange.length;
	numberStrRange.length = actualLen - (columnStrRange.location + columnStrRange.length) - suffixLen;
	if(numberStrRange.length > 0)
	{
		outColumnIndexStr = CFStringCreateWithSubstring(kCFAllocatorDefault, inControlIDString, numberStrRange);
	}
	return controlID.Detach();
}


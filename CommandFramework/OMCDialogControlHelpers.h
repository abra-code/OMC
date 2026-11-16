//**************************************************************************************
// Filename:	OMCDialogControlHelpers.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright � 2002-2004 Abracode, Inc.  All rights reserved.
//
//
//**************************************************************************************
// Revision History:
// July 21, 2004 - Original
//**************************************************************************************

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include "CFObj.h"

CFDictionaryRef ReadControlValuesFromPlist(CFStringRef inDialogUniqueID);

CFStringRef CreateActionUITableIDAndColumnFromString(CFStringRef inTableIDAndColumnString, CFObj<CFStringRef> &outColumnIndexStr, bool useAllRows, bool isEnvStyle);

CFStringRef CreateControlIDByAddingModifiers(CFStringRef inControlID, UInt32 inModifiers);

CFStringRef CreateActionUIViewIDFromString(CFStringRef inActionUIViewIDString, bool isEnvStyle);

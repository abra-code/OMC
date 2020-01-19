//**************************************************************************************
// Filename:	NibDialogControl.h
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

CFStringRef CreateControlIDFromString(CFStringRef inControlIDString, bool isEnvStyle);
CFStringRef CreateTableIDAndColumnFromString(CFStringRef inTableIDAndColumnString, CFObj<CFStringRef> &outColumnIndexStr, bool useAllRows, bool isEnvStyle);

CFStringRef CreateControlIDByStrippingModifiers(CFStringRef inControlIDWithModifiers, UInt32 &outModifiers);
CFStringRef CreateControlIDByAddingModifiers(CFStringRef inControlID, UInt32 inModifiers);

CFStringRef CreateWebViewIDAndElementIDFromString(CFStringRef inControlIDAndElementIDString, CFObj<CFStringRef> &outElementIDString, bool isEnvStyle);

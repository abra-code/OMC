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

#ifndef __LP64__

#include <Carbon/Carbon.h>
//#include <QuickTime/QuickTime.h>

#include "CFObj.h"

class SelectionIterator;

class NibDialogControl
{
public:

	typedef struct KeyFocusCandidate
	{
		SInt32 lowestID;
		ControlRef control;
	} KeyFocusCandidate;


//							NibDialogControl(CFStringRef inControlIDString, CFArrayRef inCommandName);
							NibDialogControl(const ControlID &inControlID, CFArrayRef inCommandName);
	virtual					~NibDialogControl();

	CFTypeRef				CopyControlValue(WindowRef theWindow, SInt32 inControlPart, SelectionIterator *inSelIterator, CFDictionaryRef *outCustomProperties);
	CFDictionaryRef			CopyCustomProperties(ControlRef inControl);
	static SelectionIterator *FindSelectionIteratorForCommand(WindowRef inWindow, ControlRef inControl, FourCharCode inCommandID);
	static SelectionIterator *CreateSelectionIterator(ControlRef inControl, FourCharCode inCommandID);

	CFStringRef				CopyEditFieldString(ControlRef inControl, Boolean canBePassword);
	CFStringRef				CopyPopupButtonString(ControlRef inControl);
	CFStringRef				CopyUnmappedControlString(ControlRef inControl);
	CFStringRef				CopyClockString(ControlRef inControl);
	CFStringRef				CopyCheckboxString(ControlRef inControl);
	CFStringRef				CopyRadioGroupString(ControlRef inControl);
	CFStringRef				CopyTXNString(ControlRef inControl);

	OSStatus				SetControlValue(WindowRef inWindow, CFStringRef inValue, CFBundleRef inExternBundle, CFBundleRef inMainBundle, Boolean doRefresh);
	void					SetEditFieldString(ControlRef inControl, CFStringRef inString, Boolean canBePassword);
	void					SetTXNString(ControlRef inControl, CFStringRef inString);
	static void				SetTXNStyle(TXNObject inTxnObj, CFStringRef inFontName, short inFontSize);
	void					SetClockString(ControlRef inControl, CFStringRef inString);

	OSStatus				EnableDisable(WindowRef inWindow, Boolean inEnable);
	OSStatus				ShowHide(WindowRef inWindow, Boolean inShow);
	OSStatus				RemoveListItems(WindowRef inWindow, Boolean doRefresh);
	OSStatus				AppendListItems(WindowRef inWindow, CFArrayRef inItems, Boolean doRefresh);

	OSStatus				RemoveTableRows(WindowRef inWindow, Boolean doRefresh);
	OSStatus				AddTableRows(WindowRef inWindow, CFArrayRef inItems, Boolean doRefresh);
	OSStatus				SetTableColumns(WindowRef inWindow, CFArrayRef inItems, Boolean doRefresh);
	OSStatus				SetTableWidths(WindowRef inWindow, CFArrayRef inItems, Boolean doRefresh);

	OSStatus				SetCommandID(WindowRef inWindow, UInt32 inCommandID);

	OSType					InitializeOMCControl(WindowRef inWindow, ControlRef myControl, CFBundleRef inExternBundle, CFBundleRef inMainBundle, bool &outHasSelectionIterator);
	static void				InitializeAllSubControls(WindowRef inWindow, ControlRef inParentControl, CFArrayRef inCommandName,
															CFBundleRef inExternBundle, CFBundleRef inMainBundle, KeyFocusCandidate &ioFocusCandidate, bool &outHasSelectionIterator);

	CGImageRef				CreateImageFromFile(CFURLRef inURL);
	IconRef					CreateIconRefFromFile(CFURLRef inURL);

//	static Movie			CreateMovieFromFile(CFURLRef inURL);


	static SInt32			MapControlPropertyToIntegerValue(ControlRef inControl, CFStringRef inProperty);
	static SInt32			MapMenuItemNameToIndex(ControlRef inControl, CFStringRef inName);
	static SInt32			MapRadioButtonNameToIndex(ControlRef inControl, CFStringRef inName);


	static FourCharCode		NumberToFourCharCode(UInt32 inNum);
	static CFStringRef		CreateControlPropertyString(ControlRef inControl, OSType propertyCreator, OSType propertyTag);
	static CFStringRef		MapValueToPropertyString(ControlRef inControl, UInt32 inValue);

	static void				SetControlValues(CFDictionaryRef inValues, WindowRef inWindow,
											CFArrayRef inCommandName, CFBundleRef inExternBundle, CFBundleRef inMainBundle, Boolean updateEverything);
	static OSStatus			SetControlPropertyString(ControlRef inControl, OSType propertyCreator, OSType propertyTag, CFStringRef inString);

	static CFURLRef			CreateResourceFileURL(CFBundleRef inBundle, CFStringRef inFileName);


protected:
	ControlID				mID;
	CFObj<CFArrayRef>		mCommandName;

private:
							NibDialogControl(const NibDialogControl&);
		NibDialogControl&			operator=(const NibDialogControl&);
};

#endif //__LP64__

CFStringRef CreateControlIDFromString(CFStringRef inControlIDString, bool isEnvStyle);
CFStringRef CreateTableIDAndColumnFromString(CFStringRef inTableIDAndColumnString, CFIndex &outColumnIndex, bool useAllRows, bool isEnvStyle);

CFStringRef CreateControlIDByStrippingModifiers(CFStringRef inControlIDWithModifiers, UInt32 &outModifiers);
CFStringRef CreateControlIDByAddingModifiers(CFStringRef inControlID, UInt32 inModifiers);


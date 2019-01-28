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
#include "OMCDialog.h"
#include "CFObj.h"

#ifndef __LP64__

#include "AMacHandle.h"
#include "AStdMalloc.h"
#include "DebugSettings.h"
#include "CMUtils.h"
#include "NibTabHandler.h"
#include "DefaultExternBundle.h"
#include "ACFArr.h"
#include "ACFDict.h"
#include "OMCDataBrowser.h"

//#include <QuickTime/ImageCompression.h>

//inDlogControlIDString is in the form of __NIB_DIALOG_CONTROL_XXX_VALUE__
//we need to extract ID number from this string

/*
NibDialogControl::NibDialogControl(CFStringRef inControlIDString, CFArrayRef inCommandName)
	: mCommandName(inCommandName, kCFObjRetain)
{
	mID.signature = 'OMC!';
	mID.id = GetControlIDFromString(inControlIDString);
}
*/

NibDialogControl::NibDialogControl(const ControlID &inControlID, CFArrayRef inCommandName)
	: mID(inControlID), mCommandName(inCommandName, kCFObjRetain)
{
}



NibDialogControl::~NibDialogControl()
{
}

#pragma mark -

//controlPart currently used for column index in table
//may return a string or array of strings. caller must check for type
//caller responsible for releasing non-null custom properties dictionary
CFTypeRef
NibDialogControl::CopyControlValue(WindowRef inWindow, SInt32 inControlPart, SelectionIterator *inSelIterator, CFDictionaryRef *outCustomProperties)
{
	if(inWindow == NULL)
		return NULL;

	ControlRef myControl = NULL;
	OSStatus err = ::GetControlByID(inWindow, &mID, &myControl);

	if( (err != noErr) || (myControl == NULL) )
		return NULL;
	
	ControlKind controlKind = {0,0};
	err = ::GetControlKind(myControl, &controlKind);
	
	if( (err != noErr) || (controlKind.signature != kControlKindSignatureApple) )
		return NULL;

	if(outCustomProperties != NULL)
		*outCustomProperties = CopyCustomProperties(myControl);
	
	switch(controlKind.kind)
	{		
		case kControlKindClock:
			return CopyClockString(myControl);
		break;

		case kControlKindStaticText:
		{
			Size actualSize = 0;
			CFStringRef newStr = NULL;
			err = ::GetControlData( myControl, kControlEntireControl, kControlStaticTextCFStringTag,
									sizeof(CFStringRef), &newStr, &actualSize);//"creates" string
			return newStr;
		}
		break;

		case kControlKindEditText:
		case kControlKindEditUnicodeText:
			return CopyEditFieldString(myControl, true);
		break;

		case kControlKindHISearchField:
		case kControlKindHIComboBox:
			return CopyEditFieldString(myControl, false);
		break;

		case kControlKindHITextView:
			return CopyTXNString(myControl);
		break;
		
		case kControlKindCheckBox:
			return CopyCheckboxString(myControl);
		break;
		
		case kControlKindRadioGroup:
			return CopyRadioGroupString(myControl);
		break;
		
		case kControlKindPopupButton:
			return CopyPopupButtonString(myControl);
		break;
		
		case 'imag'://HIImageView, control kind not defined by Apple in headers
		case kControlKindImageWell:
		case kControlKindIcon:
		case kControlKindBevelButton:
		case kControlKindRoundButton:
			//path to displayed image/icon is stored in 'val!' tag
			return NibDialogControl::CreateControlPropertyString(myControl, 'OMC!', kControlCustomValueKey);
		break;

		case kControlKindSlider:
		case kControlKindProgressBar:
		case kControlKindRelevanceBar:
			return CopyUnmappedControlString(myControl);
		break;

		case kControlKindPushButton:
		{
			CFStringRef newStr = NULL;
			err = ::CopyControlTitleAsCFString(myControl, &newStr);
			return newStr;
		}
		break;
		
		case kControlKindDataBrowser:
		{
			OMCDataBrowser *dbController = OMCDataBrowser::GetController(myControl);
			if(dbController == NULL)
				return NULL;
			return dbController->CopySelectionValue(inControlPart, inSelIterator);
		}
		break;
		
		default:
			LOG_CSTR("OMC->NibDialogControl::CopyControlValue. Unknown control kind: %x\n", (unsigned int)controlKind.kind);
		break;
		
	}
	
	return NULL;
}

CFDictionaryRef
NibDialogControl::CopyCustomProperties(ControlRef inControl)
{
//custom escaping mode	
	CFObj<CFStringRef> escapingMode( NibDialogControl::CreateControlPropertyString(inControl, 'OMC!', kCustomEscapeMethodKey) );	
	CFObj<CFStringRef> customPrefix( NibDialogControl::CreateControlPropertyString(inControl, 'OMC!', kCustomPrefixKey) );
	CFObj<CFStringRef> customSuffix( NibDialogControl::CreateControlPropertyString(inControl, 'OMC!', kCustomSuffixKey) );
	CFObj<CFStringRef> customSeparator( NibDialogControl::CreateControlPropertyString(inControl, 'OMC!', kCustomSeparatorKey) );

	if( (escapingMode == NULL) && (customPrefix == NULL) && (customSuffix == NULL) && (customSeparator == NULL) )
		return NULL;

	CFMutableDictionaryRef outDict = ::CFDictionaryCreateMutable(
											kCFAllocatorDefault,
											0,
											NULL,//keyCallBacks,
											&kCFTypeDictionaryValueCallBacks );	
	if(outDict == NULL)
		return NULL;

	if(escapingMode != NULL)
		::CFDictionarySetValue(
						outDict,
						(const void *)kCustomEscapeMethodKey,
						(const void *)(CFStringRef)escapingMode);

	if(customPrefix != NULL)
		::CFDictionarySetValue(
						outDict,
						(const void *)kCustomPrefixKey,
						(const void *)(CFStringRef)customPrefix);

	if(customSuffix != NULL)
		::CFDictionarySetValue(
						outDict,
						(const void *)kCustomSuffixKey,
						(const void *)(CFStringRef)customSuffix);

	if(customSeparator != NULL)
		::CFDictionarySetValue(
						outDict,
						(const void *)kCustomSeparatorKey,
						(const void *)(CFStringRef)customSeparator);

	return outDict;
}

//only one table with iterator is allowed per dialog, so we find the first one and return
//caller responsible for releasing the non-null object
SelectionIterator *
NibDialogControl::FindSelectionIteratorForCommand(WindowRef inWindow, ControlRef inControl, FourCharCode inCommandID)
{		
	OSStatus err = noErr;
	ControlID controlID;
	//multilevel embedding
	
	if(inControl == NULL)//need to obtain root control
	{
		err = ::GetRootControl(inWindow, &inControl);
		if( (err != noErr) || (inControl == NULL) ) 
			return NULL;
	}

//find children and init them one by one
	UInt16 controlCount = 0;
	err = CountSubControls(inControl, &controlCount);
	if( (err != noErr) || (controlCount == 0) )
		return NULL;

	CFStringRef oneValue = NULL;
	ControlRef oneControl = NULL;
	ControlKind controlKind = {0,0};

	SelectionIterator *outIterator = NULL;
	for(UInt16 i = 1; i <= controlCount; i++ )
	{
		err = GetIndexedSubControl(inControl, i, &oneControl);
		if( (err == noErr) && (oneControl != NULL) )
		{
			controlID.signature = 0;
			controlID.id = 0;
			err = ::GetControlID(oneControl, &controlID);
			if( (err == noErr) && (controlID.signature == 'OMC!') )
			{
				err = ::GetControlKind(oneControl, &controlKind);
				if( (controlKind.kind == kControlKindDataBrowser) && (err == noErr) && (controlKind.signature == kControlKindSignatureApple) )
				{
					outIterator = CreateSelectionIterator(oneControl, inCommandID);
					if(outIterator != NULL)
						break;
				}
			}
			
			//recursive miltilevel digger
			//try to find OMC subcontrols even if the container does not have 'OMC!' signature.
			outIterator = FindSelectionIteratorForCommand(inWindow, oneControl, inCommandID);
			if(outIterator != NULL)
				break;
		}
	}

	return outIterator;
}

SelectionIterator *
NibDialogControl::CreateSelectionIterator(ControlRef inControl, FourCharCode inCommandID)
{
	OMCDataBrowser *dbController = OMCDataBrowser::GetController(inControl);
	if(dbController == NULL)
		return NULL;

	//the string represents command list in format of {4 chars, 1 separator char, 4 chars, 1 speparator, etc. }
	//the separator is not fixed, it can be anything and it is ignored 
	CFObj<CFStringRef> commandListString( NibDialogControl::CreateControlPropertyString(inControl, 'OMC!', kSelectionIteratingCommands) );//'ite!' property

	if(commandListString != NULL)
	{
		CFIndex stringLength = ::CFStringGetLength(commandListString);
		bool commandFound = false;
		//4 chars + 1 sep + 4 chars...
		for(CFIndex idStartIndex = 0; (idStartIndex + 4) <= stringLength; idStartIndex += 5 )
		{
			CFObj<CFStringRef> oneID( ::CFStringCreateWithSubstring( kCFAllocatorDefault, commandListString, CFRangeMake(idStartIndex,4)) );
			if( ::UTGetOSTypeFromString(oneID) == inCommandID )
			{
				return dbController->CreateSelectionIterator(false /*useReverseIterator*/);
			}
		}
	}

	commandListString.Adopt( NibDialogControl::CreateControlPropertyString(inControl, 'OMC!', kReverseIterationCommands) );//'rev!' property

	if(commandListString != NULL)
	{
		CFIndex stringLength = ::CFStringGetLength(commandListString);
		//4 chars + 1 sep + 4 chars...
		for(CFIndex idStartIndex = 0; (idStartIndex + 4) <= stringLength; idStartIndex += 5 )
		{
			CFObj<CFStringRef> oneID( ::CFStringCreateWithSubstring( kCFAllocatorDefault, commandListString, CFRangeMake(idStartIndex,4)) );
			if( ::UTGetOSTypeFromString(oneID) == inCommandID )
			{
				return dbController->CreateSelectionIterator(true /*useReverseIterator*/);
			}
		}
	}

	return NULL;
}


CFStringRef
NibDialogControl::CopyEditFieldString(ControlRef inControl, Boolean canBePassword)
{
	Size actualSize;
	CFStringRef outText = NULL;
	OSStatus err = errDataNotSupported;
	
//	ControlVariant theVariant = ::GetControlVariant(inControl);

//kControlEditTextProc
//kControlEditTextPasswordProc

//	kControlEditUnicodeTextProc
//	kControlEditUnicodeTextPasswordProc

	//there is no way to tell if it is password or not
	//need to try password first, then regular text
	if(canBePassword)
		err = ::GetControlData( inControl, kControlEntireControl, kControlEditTextPasswordCFStringTag,
												sizeof(CFStringRef), &outText, &actualSize);


	if(err == errDataNotSupported)
		err = ::GetControlData( inControl, kControlEntireControl, kControlEditTextCFStringTag,
												sizeof(CFStringRef), &outText, &actualSize);

	return outText;
}


CFStringRef
NibDialogControl::CopyPopupButtonString(ControlRef inControl)
{
	SInt16 popupChoice = ::GetControlValue(inControl);
	CFStringRef outResult = NibDialogControl::MapValueToPropertyString(inControl, popupChoice);
	if(outResult == NULL)
	{//no mapping, try to obtain the menu item name
		MenuRef theMenu = ::GetControlPopupMenuHandle(inControl);
		if(theMenu != NULL)
		{
			UInt16 menuItemCount = ::CountMenuItems(theMenu);
			if( (popupChoice >= 1) && (popupChoice <= menuItemCount) )
			{
				CFStringRef theName = NULL;
				OSStatus err = ::CopyMenuItemTextAsCFString(theMenu, popupChoice, &theName);   
 				 if((err == noErr) && (theName != NULL))
					return theName;
			}
		}
		//last resort is the selected menu item index
		outResult  = ::CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d"), (int)popupChoice);
	}
	return outResult;
}

CFStringRef
NibDialogControl::CopyUnmappedControlString(ControlRef inControl)
{
	SInt16 theValue = ::GetControlValue(inControl);
	//no mapping of the output number allowed
	return ::CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d"), (int)theValue);
}

CFStringRef
NibDialogControl::CopyClockString(ControlRef inControl)
{
	Size actualSize = 0;
	CFStringRef outText = NULL;
	OSStatus err;

//Date/time format as specified by ICU at: http://oss.software.ibm.com/icu/userguide/formatDateTime.html

	CFObj<CFStringRef> dateFormatStr( NibDialogControl::CreateControlPropertyString(inControl, 'OMC!', 'frmt') );

	LongDateRec longDate;
	memset(&longDate, 0, sizeof(longDate));
	err = ::GetControlData(inControl, kControlEntireControl, kControlClockLongDateTag, sizeof(longDate), &longDate, &actualSize);
	if(err != noErr)
		return NULL;

	LongDateTime longSecs = 0;
	LongDateToSeconds(&longDate, &longSecs);
	CFAbsoluteTime absTime = 0.0;

	err = ::UCConvertLongDateTimeToCFAbsoluteTime(longSecs, &absTime);
	if(err != noErr)
		return NULL;

	CFObj<CFDateFormatterRef> dateFormatter( ::CFDateFormatterCreate(kCFAllocatorDefault, NULL, kCFDateFormatterShortStyle, kCFDateFormatterShortStyle) );
	if(dateFormatter == NULL)
		return NULL;

	if(dateFormatStr != NULL)
		::CFDateFormatterSetFormat(dateFormatter, dateFormatStr);

	return ::CFDateFormatterCreateStringWithAbsoluteTime(kCFAllocatorDefault, dateFormatter, absTime);
}


CFStringRef
NibDialogControl::CopyCheckboxString(ControlRef inControl)
{
	SInt16 theValue = ::GetControlValue(inControl);

	CFStringRef outResult = NibDialogControl::MapValueToPropertyString(inControl, theValue);
	if(outResult == NULL)
	{//no property mapping. just use "0" and "1"
		outResult = ::CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d"), (int)theValue);
	}
	return outResult;
}

CFStringRef
NibDialogControl::CopyRadioGroupString(ControlRef inControl)
{
	SInt16 theValue = ::GetControlValue(inControl);
	if(theValue < 1)
		return NULL;//something is really wrong
	CFStringRef outResult = NibDialogControl::MapValueToPropertyString(inControl, theValue);
	
	if(outResult == NULL)
	{//no mapping: try to obtain the name of the selected radio button instead
		UInt16 controlCount = 0;
		OSStatus err = CountSubControls(inControl, &controlCount);
		if( (err == noErr) && (theValue <= controlCount) )
		{
			ControlRef oneControl = NULL;
			err = GetIndexedSubControl(inControl, theValue, &oneControl);
			if((err == noErr) && (oneControl != NULL))
			{
				CFStringRef theName = NULL;
				err = ::CopyControlTitleAsCFString(oneControl, &theName);
				if((err == noErr) && (theName != NULL))
					return theName;
			}
		}
		//last resort is the selected button index
		outResult  = ::CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d"), (int)theValue);
	}
	return outResult;
}


CFStringRef
NibDialogControl::CopyTXNString(ControlRef inControl)
{
	TXNObject txnObj = ::HITextViewGetTXNObject(inControl);
	if(txnObj != NULL)
	{
		Handle dataHandle = NULL;
		OSStatus err = ::TXNGetDataEncoded(
							txnObj,
							kTXNStartOffset, kTXNEndOffset,
							&dataHandle,
							kTXNUnicodeTextData);

		if( (err == noErr) && (dataHandle != NULL) )
		{
			AMacHandle<UniChar> uniTextH((UniChar **)dataHandle);
			uniTextH.Lock();
			return ::CFStringCreateWithCharacters(
											kCFAllocatorDefault,
											(UniChar *)*(uniTextH.Get()),
											uniTextH.GetSize());//the size is actually a UniChar count
		}
	}
	return NULL;
}

//creates CFString. caller responsible for releasing it
CFStringRef
NibDialogControl::MapValueToPropertyString(ControlRef inControl, UInt32 inValue)
{
	OSType propertyTag = NibDialogControl::NumberToFourCharCode(inValue);
	return CreateControlPropertyString(inControl, 'OMC!', propertyTag);
}

//creates CFString. caller responsible for releasing it
CFStringRef
NibDialogControl::CreateControlPropertyString(ControlRef inControl, OSType propertyCreator, OSType propertyTag)
{
	UInt32 attribs = 0;
	OSStatus err = ::GetControlPropertyAttributes(
						inControl,
						propertyCreator,
						propertyTag,
						&attribs);

	if(err != noErr)
	{
		DEBUG_CSTR("NibDialogControl::CreateControlPropertyString: GetControlPropertyAttributes returned error\n");
		return NULL;
	}

	UInt32 dataSize = 0;
	err = ::GetControlPropertySize(
						inControl,
						propertyCreator,
						propertyTag,
						&dataSize );

	if(err != noErr)
	{
		DEBUG_CSTR("NibDialogControl::CreateControlPropertyString: GetControlPropertySize returned error\n");
		return NULL;
	}

	if(dataSize != 0)
	{
		AMalloc theBuffer(dataSize);
		UInt32 actualSize = 0;

		err = ::GetControlProperty(
					inControl,
					propertyCreator,
					propertyTag,
					dataSize,
					&actualSize,
	  				theBuffer.Get() );

		if(err != noErr)
		{
			DEBUG_CSTR("NibDialogControl::CreateControlPropertyString: GetControlProperty returned error\n");
			return NULL;
		}

		//unicode string must have at least one char, 2 bytes
		if(actualSize > 1)
			return ::CFStringCreateWithCharacters(
									kCFAllocatorDefault,
									(UniChar *)theBuffer.Get(),
									actualSize/sizeof(UniChar));
	}	

	//return empty string if data size is 0 but no error is returned so it exists as empty text
	CFStringRef outStr = CFSTR("");
	::CFRetain(outStr);
	return outStr;
}

//null inString removes the property

OSStatus
NibDialogControl::SetControlPropertyString(ControlRef inControl, OSType propertyCreator, OSType propertyTag, CFStringRef inString)
{
	OSStatus err = -1;
	UniCharCount uniCharCount = 0;
	if(inString == NULL)
	{
		::RemoveControlProperty(inControl, propertyCreator, propertyTag);
		return noErr;
	}
	
	UniChar *newData = CMUtils::CreateUTF16DataFromCFString(inString, &uniCharCount);
	if(newData != NULL)
	{
		AStdMalloc<UniChar> dataDel(newData);
		err = ::SetControlProperty(inControl, propertyCreator, propertyTag,
									uniCharCount*sizeof(UniChar), newData);
	}
	return err;
}

#pragma mark -


OSStatus
NibDialogControl::SetControlValue(WindowRef inWindow, CFStringRef inValue, CFBundleRef inExternBundle, CFBundleRef inMainBundle, Boolean doRefresh)
{
	if(inWindow == NULL)
		return paramErr;

	ControlRef myControl = NULL;
	OSStatus err = ::GetControlByID(inWindow, &mID, &myControl);

	if(err != noErr)
		return err;

	if( myControl == NULL )
		return errUnknownControl;
	
	ControlKind controlKind = {0,0};
	err = ::GetControlKind(myControl, &controlKind);
	if(err != noErr)
		return err;

	if( controlKind.signature != kControlKindSignatureApple )
		return errUnknownControl;
		
	switch(controlKind.kind)
	{
		case kControlKindClock:
			SetClockString(myControl, inValue);
		break;

		case kControlKindStaticText:
			err = ::SetControlData( myControl, kControlEntireControl, kControlStaticTextCFStringTag,
									sizeof(CFStringRef), &inValue);
		break;

		case kControlKindEditText:
		case kControlKindEditUnicodeText:
			SetEditFieldString(myControl, inValue, true);
		break;

		case kControlKindHISearchField:
			::HISearchFieldSetDescriptiveText(myControl, NULL);
		//fall through to setting actual string
		case kControlKindHIComboBox:
			SetEditFieldString(myControl, inValue, false);
			::HIViewSetNeedsDisplay(myControl, true);
		break;

		case kControlKindHITextView:
			SetTXNString(myControl, inValue);
			::HIViewSetNeedsDisplay(myControl, true);
		break;

		case kControlKindCheckBox:
		{
			SInt32 intValue = NibDialogControl::MapControlPropertyToIntegerValue(myControl, inValue);
			if(intValue < 0)
				intValue = ::CFStringGetIntValue(inValue);
			if((intValue == 0) || (intValue == 1))
				::SetControl32BitValue(myControl, intValue);
		}
		break;

		case kControlKindRadioGroup:
		{
			SInt32 intValue = NibDialogControl::MapControlPropertyToIntegerValue(myControl, inValue);
			if(intValue < 0)
				intValue = NibDialogControl::MapRadioButtonNameToIndex(myControl, inValue);
			if(intValue < 0)
				intValue = ::CFStringGetIntValue(inValue);
			if(intValue > 0)
				::SetControl32BitValue(myControl, intValue);
		}
		break;
	
		case kControlKindPopupButton:
		{
			SInt32 intValue = NibDialogControl::MapControlPropertyToIntegerValue(myControl, inValue);
			if(intValue < 0)
				intValue = NibDialogControl::MapMenuItemNameToIndex(myControl, inValue);
			if(intValue < 0)
				intValue = ::CFStringGetIntValue(inValue);
			if(intValue > 0)
				::SetControl32BitValue(myControl, intValue);
		}
		break;

		case kControlKindIcon:
		case kControlKindBevelButton:
		case kControlKindRoundButton:
		{
			CFObj<CFURLRef> imageURL;
			if(inExternBundle != NULL)
				imageURL.Adopt( CreateResourceFileURL(inExternBundle, inValue) );

			if(imageURL == NULL)
				imageURL.Adopt( CreateResourceFileURL(inMainBundle, inValue) );

			Boolean icnsFound = false;
			if(imageURL != NULL)
			{
				CFObj<CFStringRef> theExt( ::CFURLCopyPathExtension(imageURL) );
				if(theExt != NULL)
				{
					if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("icns"), theExt, kCFCompareCaseInsensitive) )
					{
						icnsFound = true;
					}
				}
			}
			
			if(icnsFound)
			{
				ControlButtonContentInfo contentInfo;
				contentInfo.contentType = kControlContentIconRef;
				contentInfo.u.iconRef = CreateIconRefFromFile(imageURL);
				err = SetControlData(myControl, kControlNoPart, kControlImageWellContentTag, sizeof(contentInfo), &contentInfo);
				//iconRef is retained by control, we can release our reference
				if(contentInfo.u.iconRef != 0)
					ReleaseIconRef(contentInfo.u.iconRef);
				if(imageURL != NULL)
				{
					CFObj<CFStringRef> filePath( ::CFURLCopyFileSystemPath(imageURL, kCFURLPOSIXPathStyle) );
					err = NibDialogControl::SetControlPropertyString(myControl, 'OMC!', 'val!', filePath);
				}
			}
		}
		break;

		case 'imag'://HIImageView, control kind not defined by Apple in headers
		{
			CFObj<CFURLRef> imageURL;
			if(inExternBundle != NULL)
				imageURL.Adopt( CreateResourceFileURL(inExternBundle, inValue) );

			if(imageURL == NULL)
				imageURL.Adopt( CreateResourceFileURL(inMainBundle, inValue) );
			
			CGImageRef cgImage = CreateImageFromFile(imageURL);
			err = ::HIImageViewSetImage(myControl, cgImage);//NULL image is OK
			if(cgImage != NULL)
				::CGImageRelease(cgImage);
			if(imageURL != NULL)
			{
				CFObj<CFStringRef> filePath( ::CFURLCopyFileSystemPath(imageURL, kCFURLPOSIXPathStyle) );
				err = NibDialogControl::SetControlPropertyString(myControl, 'OMC!', 'val!', filePath);
			}
			::HIViewSetNeedsDisplay(myControl, true);
		}
		break;

//imageRef stuff does not work as of Mac OS 10.3	
		case kControlKindImageWell:
		{
			CFObj<CFURLRef> imageURL;
			if(inExternBundle != NULL)
				imageURL.Adopt( CreateResourceFileURL(inExternBundle, inValue) );

			if(imageURL == NULL)
				imageURL.Adopt( CreateResourceFileURL(inMainBundle, inValue) );

			Boolean icnsFound = false;
			if(imageURL != NULL)
			{
				CFObj<CFStringRef> theExt( ::CFURLCopyPathExtension(imageURL) );
				if(theExt != NULL)
				{
					if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("icns"), theExt, kCFCompareCaseInsensitive) )
					{
						icnsFound = true;
					}
				}
			}
			
			if(icnsFound)
			{
				ControlButtonContentInfo contentInfo;
				contentInfo.contentType = kControlContentIconRef;
				contentInfo.u.iconRef = CreateIconRefFromFile(imageURL);
				err = SetControlData(myControl, kControlNoPart, kControlImageWellContentTag, sizeof(contentInfo), &contentInfo);
				//iconRef is retained by control, we can release our reference
				if(contentInfo.u.iconRef != 0)
					ReleaseIconRef(contentInfo.u.iconRef);
			}
			else
			{
				ControlButtonContentInfo contentInfo;
				contentInfo.contentType = kControlContentCGImageRef;
				contentInfo.u.imageRef = CreateImageFromFile(imageURL);
				//err = SetImageWellContentInfo(dropTarget, &cbci);
				err = SetControlData(myControl, kControlNoPart, kControlImageWellContentTag, sizeof(contentInfo), &contentInfo);
				if(contentInfo.u.imageRef != NULL)
					::CGImageRelease(contentInfo.u.imageRef);
			}
			
			if(imageURL != NULL)
			{
				CFObj<CFStringRef> filePath( ::CFURLCopyFileSystemPath(imageURL, kCFURLPOSIXPathStyle) );
				err = NibDialogControl::SetControlPropertyString(myControl, 'OMC!', 'val!', filePath);
			}
		}
		break;

		case kControlKindSlider:
		case kControlKindRelevanceBar:
			::SetControl32BitValue(myControl, ::CFStringGetIntValue(inValue));//no mapping here
		break;
		
		case kControlKindProgressBar:
		{
			SInt32 theNum = ::CFStringGetIntValue(inValue);
			Boolean isIndeterminate = false;
			if(theNum < 0)
				isIndeterminate = true;

			::SetControlData(myControl, kControlNoPart, kControlProgressBarIndeterminateTag,
		 						sizeof(Boolean), &isIndeterminate);

			::SetControl32BitValue(myControl, ::CFStringGetIntValue(inValue));//no mapping here
		}
		break;
		
		case kControlKindPushButton:
		{
			::SetControlTitleWithCFString( myControl, inValue );
		}
		break;

		default:
		{
#if OLD_QUICKTIME_MOVIE
            //CFStringRef whatIsTheClassID = ::HIObjectCopyClassID( (HIObjectRef)myControl );
			//if( ::HIObjectIsOfClass( (HIObjectRef)myControl, kHIMovieViewClassID) )
			if( true )
			{
			    // set inital movie view attributes and show the window
				OptionBits setAttributes = kHIMovieViewAutoIdlingAttribute | kHIMovieViewControllerVisibleAttribute;
				OptionBits clearAttributes = kHIMovieViewEditableAttribute | kHIMovieViewHandleEditingHIAttribute | kHIMovieViewAcceptsFocusAttribute;
				
				err = HIMovieViewChangeAttributes((HIViewRef)myControl, setAttributes, clearAttributes);

				CFObj<CFURLRef> movieURL;
				if(inExternBundle != NULL)
					movieURL.Adopt( CreateResourceFileURL(inExternBundle, inValue) );

				if(movieURL == NULL)
					movieURL.Adopt( CreateResourceFileURL(inMainBundle, inValue) );
			
				Movie qtMovie = NibDialogControl::CreateMovieFromFile( movieURL );
				if(qtMovie != NULL)
				{
					err = ::HIMovieViewSetMovie( (HIViewRef)myControl, qtMovie );
					::DisposeMovie( qtMovie );
				}
			}
			else
#endif //OLD_QUICKTIME_MOVIE
            {
				LOG_CSTR("OMC->NibDialogControl::CopyControlValue. Unknown control kind: %x\n", (unsigned int)controlKind.kind);
			}
		}
		break;

	}
	
	if(doRefresh)
		Draw1Control(myControl);

	return noErr;
}

void
NibDialogControl::SetEditFieldString(ControlRef inControl, CFStringRef inString, Boolean canBePassword)
{
	OSStatus err = errDataNotSupported;

	::SetControlTitleWithCFString(inControl, CFSTR(""));

	//there is no way to tell if it is password or not
	//need to try password first, then regular text
	if(canBePassword)
	{
		err = ::SetControlData(inControl, kControlEntireControl, kControlEditTextPasswordCFStringTag,
		 						sizeof(CFStringRef), &inString);
	}
	

	if(err != noErr)
		err = ::SetControlData( inControl, kControlEntireControl, kControlEditTextCFStringTag,
												sizeof(CFStringRef), &inString);

//	DrawOneControl(inControl);
}

//inValue may be a mapped value or real value - we try to find mapping first
//must query all posible values for given control because there is no API to search for property by its value
//returns -1 when preporty not matched (-1 is invalid value)

SInt32
NibDialogControl::MapControlPropertyToIntegerValue(ControlRef inControl, CFStringRef inProperty)
{
	SInt32 minVal = ::GetControl32BitMinimum(inControl);
	SInt32 maxVal = ::GetControl32BitMaximum(inControl);

	for(SInt32 i = minVal; i <= maxVal; i++)
	{
		CFObj<CFStringRef> mapStr( NibDialogControl::MapValueToPropertyString(inControl, i) );
		if(mapStr != NULL)
		{// some valid mapping was found - now check if it is equal to our property string
			if( kCFCompareEqualTo == ::CFStringCompare(mapStr, inProperty, 0) )
			{//a match found
				return i;
			}
		}
	}

	return -1;
}

//returns -1 for invalid index when match was not found

SInt32
NibDialogControl::MapMenuItemNameToIndex(ControlRef inControl, CFStringRef inName)
{
	MenuRef theMenu = ::GetControlPopupMenuHandle(inControl);
	if(theMenu != NULL)
	{
		UInt16 menuItemCount = ::CountMenuItems(theMenu);
		for(SInt32 i = 1; i <= menuItemCount; i++)
		{
			CFObj<CFStringRef> itemName;
			OSStatus err = ::CopyMenuItemTextAsCFString(theMenu, i, &itemName);   
			if( (err == noErr) && (itemName != NULL) )
			{// some valid mapping was found - now check if it is equal to our property string
				if( kCFCompareEqualTo == ::CFStringCompare(itemName, inName, 0) )
				{//a match found
					return i;
				}
			}
		}
	}
	return -1;
}


SInt32
NibDialogControl::MapRadioButtonNameToIndex(ControlRef inControl, CFStringRef inName)
{
	UInt16 controlCount = 0;
	OSStatus err = CountSubControls(inControl, &controlCount);
	if( err == noErr )
	{
		for(SInt32 i = 1; i <= controlCount; i++)
		{
			ControlRef oneControl = NULL;
			err = ::GetIndexedSubControl(inControl, i, &oneControl);
			if((err == noErr) && (oneControl != NULL))
			{
				CFObj<CFStringRef> itemName;
				err = ::CopyControlTitleAsCFString(oneControl, &itemName);
				if((err == noErr) && (itemName != NULL))
				{
					if( kCFCompareEqualTo == ::CFStringCompare(itemName, inName, 0) )
					{//a match found
						return i;
					}
				}
			}
		}
	}
	return -1;
}


void
NibDialogControl::SetTXNString(ControlRef inControl, CFStringRef inString)
{
	TXNObject txnObj = ::HITextViewGetTXNObject(inControl);
	if(txnObj == NULL)
		return;

	OSStatus err = noErr;
	CFIndex uniCount = ::CFStringGetLength(inString);
	const UniChar *uniString = ::CFStringGetCharactersPtr(inString);

	if( uniString != NULL )
	{
		err = ::TXNSetData(
						txnObj,
						kTXNUnicodeTextData,
						(UniChar *)uniString,
						uniCount * sizeof(UniChar),
						kTXNStartOffset,
						kTXNEndOffset );	
	}
	else
	{
		AStdMalloc<UniChar> newString(uniCount);
		CFRange theRange;
		theRange.location = 0;
		theRange.length = uniCount;
		::CFStringGetCharacters( inString, theRange, newString.Get());
		
		err = ::TXNSetData(
						txnObj,
						kTXNUnicodeTextData,
						(UniChar *)newString,
						uniCount * sizeof(UniChar),
						kTXNStartOffset,
						kTXNEndOffset );	
		
	}
	
	CFObj<CFStringRef> customFontName( NibDialogControl::CreateControlPropertyString(inControl, 'OMC!', kCustomFontName) );
	CFObj<CFStringRef> customFontSize( NibDialogControl::CreateControlPropertyString(inControl, 'OMC!', kCustomFontSize) );
	if( (customFontName != NULL) || (customFontSize != NULL) )
	{
		SInt32 fontSize = 0;
		if(customFontSize != NULL)
			fontSize = ::CFStringGetIntValue( customFontSize );
		SetTXNStyle(txnObj, customFontName, fontSize);
	}
	
	::TXNSetSelection(txnObj, 0, 0);
	::TXNShowSelection(txnObj, false /*show end*/);
}

//the old declarations not available in 10.7 SDK
extern "C" FMFontFamily
FMGetFontFamilyFromName(ConstStr255Param iName);

extern "C" OSStatus 
FMGetFontFromFontFamilyInstance(
  FMFontFamily   iFontFamily,
  FMFontStyle    iStyle,
  FMFont *       oFont,
  FMFontStyle *  oIntrinsicStyle);


extern "C"
OSStatus
ATSUFindFontFromName (
   const void *iName, 
   ByteCount iNameLength, 
   FontNameCode iFontNameCode, 
   FontPlatformCode iFontNamePlatform, 
   FontScriptCode iFontNameScript, 
   FontLanguageCode iFontNameLanguage, 
   ATSUFontID *oFontID
);

void
NibDialogControl::SetTXNStyle(TXNObject inTxnObj, CFStringRef inFontName, short inFontSize)
{
	OSStatus err = noErr;
	TXNTypeAttributes attributes[4];
	int i = 0;
	if(inFontName != NULL)
	{
		Str255 fName = "\pMonaco";
		::CFStringGetPascalString(inFontName, fName, sizeof(fName), kCFStringEncodingMacRoman);
		ATSUFontID iFontID = 0;
		err = ::ATSUFindFontFromName(
									(Ptr)fName+1,
									(long)fName[0],
									kFontFullName,
									kFontNoPlatformCode, //kFontMacintoshPlatform,
									kFontNoScriptCode, //kFontRomanScript,
									kFontNoLanguage,
									&iFontID );
		if(err != noErr)
		{
/*
			//this does not work correctly. Finds bolds, italics before regular fonts.
			err = ::ATSUFindFontFromName(
										(Ptr)fName+1,
										(long)fName[0],
										kFontFamilyName,
										kFontNoPlatformCode, //kFontMacintoshPlatform,
										kFontNoScriptCode, //kFontRomanScript,
										kFontNoLanguage,
										&iFontID );
*/

			FMFontStyle intrinsicStyle;
			FMFontFamily familyID = ::FMGetFontFamilyFromName(fName);
			err = ::FMGetFontFromFontFamilyInstance(familyID, normal, &iFontID, &intrinsicStyle);

/*
			CFStringRef fontFamilyName = CFSTR("Monaco");
			ATSFontFamilyRef fontFamilyRef = ::ATSFontFamilyFindFromName(fontFamilyName, kATSOptionFlagsDefault );
			FMFontFamily fmFontFamily = ::FMGetFontFamilyFromATSFontFamilyRef( fontFamilyRef );
			FMFont fmFontRef = 0;
			FMFontStyle fmFontStyle = 0;
			FMFontStyle intrFontStyle = 0;
			err = ::FMGetFontFromFontFamilyInstance( fmFontFamily, fmFontStyle, &fmFontRef, &intrFontStyle );
			iFontID = (ATSUFontID)fmFontRef; //FMFont and ATSUFontID are equvalent
*/
		}
				
		if(err == noErr)
		{
			attributes[i].tag = kATSUFontTag;
			attributes[i].size = sizeof(ATSUFontID);	
			attributes[i].data.dataValue = iFontID;
			i++;
		}
	}


	if(inFontSize < 0)
		inFontSize = 0;
	if(inFontSize > 10000)
		inFontSize = 10000;

	if(inFontSize > 0)
	{
		attributes[i].tag = kATSUSizeTag;
		attributes[i].size = sizeof(Fixed);	
		attributes[i].data.dataValue = Long2Fix(inFontSize);
		i++;
	}


	if( i > 0)
	{
		err = ::TXNSetTypeAttributes(
									inTxnObj,
									i,
									attributes,
									kTXNStartOffset,
									kTXNEndOffset );
	}

}


void
NibDialogControl::SetClockString(ControlRef inControl, CFStringRef inString)
{
	Size actualSize = 0;
	CFStringRef outText = NULL;
	OSStatus err = -1;

//Date/time format as specified by ICU at: http://icu.sourceforge.net/userguide/formatDateTime.html

	CFObj<CFStringRef> dateFormatStr( NibDialogControl::CreateControlPropertyString(inControl, 'OMC!', 'frmt') );

	CFObj<CFDateFormatterRef> dateFormatter( ::CFDateFormatterCreate(kCFAllocatorDefault, NULL, kCFDateFormatterShortStyle, kCFDateFormatterShortStyle) );
	if(dateFormatter == NULL)
		return;

	if(dateFormatStr != NULL)
		::CFDateFormatterSetFormat(dateFormatter, dateFormatStr);

	CFAbsoluteTime absTime = 0.0;

	Boolean parsedOK = ::CFDateFormatterGetAbsoluteTimeFromString(
										dateFormatter,
										inString,
										NULL,
  										&absTime);
	if(parsedOK && (absTime != 0.0))
	{
		LongDateTime longSecs = 0;
		err = ::UCConvertCFAbsoluteTimeToLongDateTime(absTime, &longSecs);

		LongDateRec longDate;
		memset(&longDate, 0, sizeof(longDate));

		::LongSecondsToDate(&longSecs, &longDate);

		err = ::SetControlData(inControl, kControlEntireControl, kControlClockLongDateTag, sizeof(longDate), &longDate);
	}
}


OSStatus
NibDialogControl::EnableDisable(WindowRef inWindow, Boolean inEnable)
{
	if(inWindow == NULL)
		return paramErr;

	ControlRef myControl = NULL;
	OSStatus err = ::GetControlByID(inWindow, &mID, &myControl);

	if(err != noErr)
		return err;

	if( myControl == NULL )
		return errUnknownControl;
	
	if(inEnable)
		err = EnableControl(myControl);
	else
		err = DisableControl(myControl);

	return err;
}

OSStatus
NibDialogControl::ShowHide(WindowRef inWindow, Boolean inShow)
{
	if(inWindow == NULL)
		return paramErr;

	ControlRef myControl = NULL;
	OSStatus err = ::GetControlByID(inWindow, &mID, &myControl);

	if(err != noErr)
		return err;

	if( myControl == NULL )
		return errUnknownControl;
		
	if(inShow)
		ShowControl(myControl);
	else
		HideControl(myControl);

	return noErr;
}

OSStatus
NibDialogControl::RemoveListItems(WindowRef inWindow, Boolean doRefresh)
{
	if(inWindow == NULL)
		return paramErr;

	ControlRef myControl = NULL;
	OSStatus err = ::GetControlByID(inWindow, &mID, &myControl);

	if(err != noErr)
		return err;

	if( myControl == NULL )
		return errUnknownControl;
	
	ControlKind controlKind = {0,0};
	err = ::GetControlKind(myControl, &controlKind);
	if(err != noErr)
		return err;

	if( controlKind.signature != kControlKindSignatureApple )
		return errUnknownControl;
		
	switch(controlKind.kind)
	{
		case kControlKindPopupButton:
		{
			MenuRef theMenu = ::GetControlPopupMenuHandle(myControl);
			if(theMenu != NULL)
			{
				UInt16 menuItemCount = ::CountMenuItems(theMenu);
				::DeleteMenuItems(theMenu, 1, menuItemCount);
				
				::SetControlMinimum(myControl, 0);
				::SetControlMaximum(myControl, 0);
				::SetControlValue(myControl, 0);
			}
		}
		break;
		
		case kControlKindHIComboBox:
		{
			ItemCount menuItemCount = ::HIComboBoxGetItemCount(myControl);
			//indexes are 0-based apparently although Apple did not care to document it
			for(CFIndex i = menuItemCount-1; i >= 0; i--)
			{
				::HIComboBoxRemoveItemAtIndex(myControl, i);
			}
			::SetControlMinimum(myControl, 0);
			::SetControlMaximum(myControl, 0);
		}
		break;
	}

	if(doRefresh)
		Draw1Control(myControl);

	return noErr;
}

OSStatus
NibDialogControl::AppendListItems(WindowRef inWindow, CFArrayRef inItems, Boolean doRefresh)
{
	if(inWindow == NULL)
		return paramErr;

	if(inItems == NULL)
		return noErr;

	ControlRef myControl = NULL;
	OSStatus err = ::GetControlByID(inWindow, &mID, &myControl);

	if(err != noErr)
		return err;

	if( myControl == NULL )
		return errUnknownControl;
	
	ControlKind controlKind = {0,0};
	err = ::GetControlKind(myControl, &controlKind);
	if(err != noErr)
		return err;

	if( controlKind.signature != kControlKindSignatureApple )
		return errUnknownControl;
	
	ACFArr items(inItems);
	CFIndex itemCount = items.GetCount();
	CFStringRef kSeparatorString = CFSTR("-");
	MenuItemAttributes menuAttributes;

	switch(controlKind.kind)
	{
		case kControlKindPopupButton:
		{
			MenuRef theMenu = ::GetControlPopupMenuHandle(myControl);
			if(theMenu != NULL)
			{
				CFStringRef theStr;
				for(CFIndex i = 0; i < itemCount; i++)//indexes in CFArray are zero-based
				{
					menuAttributes = kMenuItemAttrIgnoreMeta;
					if( items.GetValueAtIndex(i, theStr) )
					{
						if( kCFCompareEqualTo == ::CFStringCompare(theStr, kSeparatorString, 0) )
							menuAttributes |= kMenuItemAttrSeparator;
						
						err = ::AppendMenuItemTextWithCFString( theMenu, theStr, menuAttributes, 0, NULL );
					}
				}
				
				UInt16 menuItemCount = ::CountMenuItems(theMenu);
				if(menuItemCount > 0)
				{
					::SetControlMinimum(myControl, 1);
					::SetControlMaximum(myControl, menuItemCount);
					SInt16 oldValue = ::GetControlValue(myControl);
					if( (oldValue <= 0) || (oldValue > menuItemCount) )
						::SetControlValue(myControl, 1);
				}
			}
		}
		break;
		
		case kControlKindHIComboBox:
		{
			CFStringRef theStr;
			for(CFIndex i = 0; i < itemCount; i++)//indexes in CFArray are zero-based
			{
				if( items.GetValueAtIndex(i, theStr) )
					err = ::HIComboBoxAppendTextItem( myControl, theStr, NULL);
			}
			ItemCount menuItemCount = ::HIComboBoxGetItemCount(myControl);
			if(menuItemCount > 0)
			{
				::SetControlMinimum(myControl, 1);
				::SetControlMaximum(myControl, menuItemCount);
			}
		}
		break;
		
	}

	if(doRefresh)
		Draw1Control(myControl);

	return noErr;
}

OSStatus
NibDialogControl::RemoveTableRows(WindowRef inWindow, Boolean doRefresh)
{
	OMCDataBrowser *dbController = OMCDataBrowser::GetController(inWindow, mID);
	if(dbController == NULL)
		return errUnknownControl;

	return dbController->RemoveRows();
}

//array of non-parsed rows passed here: needs separator info
OSStatus
NibDialogControl::AddTableRows(WindowRef inWindow, CFArrayRef inItems, Boolean doRefresh)
{
	if(inItems == NULL)
		return noErr;

	OMCDataBrowser *dbController = OMCDataBrowser::GetController(inWindow, mID);
	if(dbController == NULL)
		return errUnknownControl;

	return dbController->AddRows(inItems);
}

//column names passed here
OSStatus
NibDialogControl::SetTableColumns(WindowRef inWindow, CFArrayRef inItems, Boolean doRefresh)
{
	if(inItems == NULL)
		return noErr;

	OMCDataBrowser *dbController = OMCDataBrowser::GetController(inWindow, mID);
	if(dbController == NULL)
		return errUnknownControl;

	dbController->RemoveColumns();
	return dbController->AddColumns(inItems);
}

//column widths as strings 
OSStatus
NibDialogControl::SetTableWidths(WindowRef inWindow, CFArrayRef inItems, Boolean doRefresh)
{
	if(inItems == NULL)
		return noErr;

	OMCDataBrowser *dbController = OMCDataBrowser::GetController(inWindow, mID);
	if(dbController == NULL)
		return errUnknownControl;

	dbController->SetColumnWidths(inItems);
	return noErr;
}



OSStatus
NibDialogControl::SetCommandID(WindowRef inWindow, UInt32 inCommandID)
{
	if(inWindow == NULL)
		return paramErr;

	ControlRef myControl = NULL;
	OSStatus err = ::GetControlByID(inWindow, &mID, &myControl);

	if(err != noErr)
		return err;

	if( myControl == NULL )
		return errUnknownControl;
	
	err = ::SetControlCommandID( myControl, inCommandID );

	return noErr;
}

//static
void
NibDialogControl::SetControlValues(CFDictionaryRef inControlDict, WindowRef inWindow,
									CFArrayRef inCommandName, CFBundleRef inExternBundle, CFBundleRef inMainBundle, Boolean updateEverything)
{
	if((inWindow == NULL) || (inControlDict == NULL))
		return;
	
	CFIndex itemCount = ::CFDictionaryGetCount(inControlDict);
	if(itemCount == 0)
		return;

	ACFDict controlValues(inControlDict);
	
	CFDictionaryRef removeListItemsDict;
	if( controlValues.GetValue(CFSTR("REMOVE_LIST_ITEMS"), removeListItemsDict) )
	{
		itemCount = ::CFDictionaryGetCount(removeListItemsDict);
		if(itemCount > 0)
		{
			AStdMalloc<CFTypeRef> keyList(itemCount);
			AStdMalloc<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(removeListItemsDict, (const void **)keyList.Get(), (const void **)valueList.Get());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if(theKey != NULL)
				{
					ControlID oneID = { 'OMC!', 0 };
					oneID.id = ::CFStringGetIntValue(theKey);
					NibDialogControl oneControl(oneID, inCommandName);
					oneControl.RemoveListItems(inWindow, !updateEverything);
				}
			}
		}
	}

	CFDictionaryRef appendListItemsDict;
	if( controlValues.GetValue(CFSTR("APPEND_LIST_ITEMS"), appendListItemsDict) )
	{
		itemCount = ::CFDictionaryGetCount(appendListItemsDict);
		if(itemCount > 0)
		{
			AStdMalloc<CFTypeRef> keyList(itemCount);
			AStdMalloc<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(appendListItemsDict, (const void **)keyList.Get(), (const void **)valueList.Get());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (theKey != NULL) && (theArr != NULL) )
				{
					ControlID oneID = { 'OMC!', 0 };
					oneID.id = ::CFStringGetIntValue(theKey);
					NibDialogControl oneControl(oneID, inCommandName);
					oneControl.AppendListItems(inWindow, theArr, !updateEverything);
				}
			}
		}
	}

	CFDictionaryRef removeTableRowsDict;
	if( controlValues.GetValue(CFSTR("REMOVE_TABLE_ROWS"), removeTableRowsDict) )
	{
		itemCount = ::CFDictionaryGetCount(removeTableRowsDict);
		if(itemCount > 0)
		{
			AStdMalloc<CFTypeRef> keyList(itemCount);
			AStdMalloc<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(removeTableRowsDict, (const void **)keyList.Get(), (const void **)valueList.Get());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if(theKey != NULL)
				{
					ControlID oneID = { 'OMC!', 0 };
					oneID.id = ::CFStringGetIntValue(theKey);
					NibDialogControl oneControl(oneID, inCommandName);
					oneControl.RemoveTableRows(inWindow, !updateEverything);
				}
			}
		}
	}

	CFDictionaryRef addTableRowsDict;
	if( controlValues.GetValue(CFSTR("ADD_TABLE_ROWS"), addTableRowsDict) )
	{
		itemCount = ::CFDictionaryGetCount(addTableRowsDict);
		if(itemCount > 0)
		{
			AStdMalloc<CFTypeRef> keyList(itemCount);
			AStdMalloc<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(addTableRowsDict, (const void **)keyList.Get(), (const void **)valueList.Get());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (theKey != NULL) && (theArr != NULL) )
				{
					ControlID oneID = { 'OMC!', 0 };
					oneID.id = ::CFStringGetIntValue(theKey);
					NibDialogControl oneControl(oneID, inCommandName);
					oneControl.AddTableRows(inWindow, theArr, !updateEverything);
				}
			}
		}
	}

	CFDictionaryRef addTableColumnsDict;
	if( controlValues.GetValue(CFSTR("SET_TABLE_COLUMNS"), addTableColumnsDict) )
	{
		itemCount = ::CFDictionaryGetCount(addTableColumnsDict);
		if(itemCount > 0)
		{
			AStdMalloc<CFTypeRef> keyList(itemCount);
			AStdMalloc<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(addTableColumnsDict, (const void **)keyList.Get(), (const void **)valueList.Get());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (theKey != NULL) && (theArr != NULL) )
				{
					ControlID oneID = { 'OMC!', 0 };
					oneID.id = ::CFStringGetIntValue(theKey);
					NibDialogControl oneControl(oneID, inCommandName);
					oneControl.SetTableColumns(inWindow, theArr, !updateEverything);
				}
			}
		}
	}

	CFDictionaryRef setTableWidthsDict;
	if( controlValues.GetValue(CFSTR("SET_TABLE_WIDTHS"), setTableWidthsDict) )
	{
		itemCount = ::CFDictionaryGetCount(setTableWidthsDict);
		if(itemCount > 0)
		{
			AStdMalloc<CFTypeRef> keyList(itemCount);
			AStdMalloc<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(setTableWidthsDict, (const void **)keyList.Get(), (const void **)valueList.Get());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (theKey != NULL) && (theArr != NULL) )
				{
					ControlID oneID = { 'OMC!', 0 };
					oneID.id = ::CFStringGetIntValue(theKey);
					NibDialogControl oneControl(oneID, inCommandName);
					oneControl.SetTableWidths(inWindow, theArr, !updateEverything);
				}
			}
		}
	}

	CFDictionaryRef valuesDict;
	
	if( controlValues.GetValue(CFSTR("VALUES"), valuesDict) )
	{
		itemCount = ::CFDictionaryGetCount(valuesDict);
		if(itemCount > 0)
		{
			AStdMalloc<CFTypeRef> keyList(itemCount);
			AStdMalloc<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(valuesDict, (const void **)keyList.Get(), (const void **)valueList.Get());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if(theKey != NULL)
				{
					ControlID oneID = { 'OMC!', 0 };
					oneID.id = ::CFStringGetIntValue(theKey);
					NibDialogControl oneControl(oneID, inCommandName);
					oneControl.SetControlValue(inWindow, ACFType<CFStringRef>::DynamicCast( valueList[i] ), inExternBundle, inMainBundle, !updateEverything);
				}
			}
		}
	}
	
	CFDictionaryRef enableDisableDict;
	if( controlValues.GetValue(CFSTR("ENABLE_DISABLE"), enableDisableDict) )
	{
		itemCount = ::CFDictionaryGetCount(enableDisableDict);
		if(itemCount > 0)
		{
			AStdMalloc<CFTypeRef> keyList(itemCount);
			AStdMalloc<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(enableDisableDict, (const void **)keyList.Get(), (const void **)valueList.Get());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFBooleanRef theVal = ACFType<CFBooleanRef>::DynamicCast( valueList[i] );
				if( (theKey != NULL) && (theVal != NULL) )
				{
					ControlID oneID = { 'OMC!', 0 };
					oneID.id = ::CFStringGetIntValue(theKey);
					NibDialogControl oneControl(oneID, inCommandName);
					oneControl.EnableDisable(inWindow, ::CFBooleanGetValue(theVal));
				}
			}
		}
	}

	CFDictionaryRef showHideDict;
	if( controlValues.GetValue(CFSTR("SHOW_HIDE"), showHideDict) )
	{
		itemCount = ::CFDictionaryGetCount(showHideDict);
		if(itemCount > 0)
		{
			AStdMalloc<CFTypeRef> keyList(itemCount);
			AStdMalloc<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(showHideDict, (const void **)keyList.Get(), (const void **)valueList.Get());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFBooleanRef theVal = ACFType<CFBooleanRef>::DynamicCast( valueList[i] );
				if( (theKey != NULL) && (theVal != NULL) )
				{
					ControlID oneID = { 'OMC!', 0 };
					oneID.id = ::CFStringGetIntValue(theKey);
					NibDialogControl oneControl(oneID, inCommandName);
					oneControl.ShowHide(inWindow, ::CFBooleanGetValue(theVal));
				}
			}
		}
	}

	CFDictionaryRef commandIdsDict;
	if( controlValues.GetValue(CFSTR("COMMAND_IDS"), commandIdsDict) )
	{
		itemCount = ::CFDictionaryGetCount(commandIdsDict);
		if(itemCount > 0)
		{
			AStdMalloc<CFTypeRef> keyList(itemCount);
			AStdMalloc<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(commandIdsDict, (const void **)keyList.Get(), (const void **)valueList.Get());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFStringRef theVal = ACFType<CFStringRef>::DynamicCast( valueList[i] );
				if( (theKey != NULL) && (theVal != NULL) )
				{
					ControlID oneID = { 'OMC!', 0 };
					oneID.id = ::CFStringGetIntValue(theKey);
					UInt32 commandID = ::UTGetOSTypeFromString( theVal );
					NibDialogControl oneControl(oneID, inCommandName);
					oneControl.SetCommandID(inWindow, commandID);
				}
			}
		}
	}

	if(updateEverything)
		DrawControls(inWindow);
//	UpdateControls(inWindow, NULL);
}


#pragma mark -

//	if(controlRef != NULL)
//		::SetKeyboardFocus( dialogWindow, controlRef, kControlFocusNextPart);


void
NibDialogControl::InitializeAllSubControls(WindowRef inWindow, ControlRef inParentControl, CFArrayRef inCommandName,
											CFBundleRef inExternBundle, CFBundleRef inMainBundle,
											KeyFocusCandidate &ioFocusCandidate, bool &outHasSelectionIterator )
{
	OSStatus err = noErr;
	ControlID controlID;
	//multilevel embedding
	
	if(inParentControl == NULL)//need to obtain root control
	{
		err = ::GetRootControl(inWindow, &inParentControl);
		if( (err != noErr) || (inParentControl == NULL) ) 
			return;// handlerChain;
	}

//find children and init them one by one
	UInt16 controlCount = 0;
	err = CountSubControls(inParentControl, &controlCount);
	if( (err != noErr) || (controlCount == 0) )
		return; //handlerChain;

	CFStringRef oneValue = NULL;
	ControlRef oneControl = NULL;

	for(UInt16 i = 1; i <= controlCount; i++ )
	{
		err = GetIndexedSubControl(inParentControl, i, &oneControl);
		if((err == noErr) && (oneControl != NULL))
		{
			controlID.signature = 0;
			controlID.id = 0;
			err = ::GetControlID(oneControl, &controlID);
			if( (err == noErr) && (controlID.signature == 'OMC!') )
			{
				NibDialogControl omcControl(controlID, inCommandName);
				OSType controlKind = omcControl.InitializeOMCControl(inWindow, oneControl, inExternBundle, inMainBundle, outHasSelectionIterator);
				
				//try to find the edit field-like control with lowest id to focus keyboard
				if( (controlID.id < ioFocusCandidate.lowestID) &&
					((controlKind == kControlKindEditText) ||
					(controlKind == kControlKindEditUnicodeText) ||
					(controlKind == kControlKindHISearchField) ||
					(controlKind == kControlKindHIComboBox) ||
					(controlKind == kControlKindHITextView)) )
				{
					ioFocusCandidate.lowestID = controlID.id;
					ioFocusCandidate.control = oneControl;
				}
			}
			
			//recursive miltilevel digger
			//try to find OMC subcontrols even if the container does not have 'OMC!' signature.
			InitializeAllSubControls(inWindow, oneControl, /*handlerChain,*/ inCommandName, inExternBundle, inMainBundle, ioFocusCandidate, outHasSelectionIterator);
		}
	}
	
	return; //handlerChain;
}

//returns control kind
OSType
NibDialogControl::InitializeOMCControl(WindowRef inWindow, ControlRef myControl, CFBundleRef inExternBundle, CFBundleRef inMainBundle, bool &outHasSelectionIterator)
{
	if((inWindow == NULL) || (myControl == NULL))
		return 0;

	ControlKind controlKind = {0,0};
	OSStatus err = ::GetControlKind(myControl, &controlKind);
	if(err != noErr)
		return 0;

	if( controlKind.signature != kControlKindSignatureApple )
		return controlKind.kind;

	switch(controlKind.kind)
	{
/* most controls do not need additional static initializers
		case kControlKindSlider:
		break;

		case kControlKindStaticText:
		break;

		case kControlKindEditText:
		case kControlKindEditUnicodeText:
		break;

		case kControlKindHISearchField:
		case kControlKindHIComboBox:
		break;

		case kControlKindCheckBox:
		break;

		case kControlKindRadioGroup:
		break;
	
		case kControlKindPopupButton:
		break;
*/

		case kControlKindHITextView:
		{

			TXNObject txnObj = ::HITextViewGetTXNObject(myControl);
			if( txnObj != NULL )
			{
				TXNControlTag controlTags[2];
				TXNControlData controlData[2];
				::memset( controlData, 0, sizeof(controlData) );
				controlTags[0] = kTXNIOPrivilegesTag;
				controlTags[1] = kTXNNoUserIOTag;
				
				//controlData[0].uValue = kTXNReadOnly;

				OSStatus err = ::TXNGetTXNObjectControls(
									txnObj,
									2,
									controlTags,
									controlData );

				if( controlData[0].uValue != (UInt32)kTXNReadWrite )
				{//a read-only flag is set, we have to clear it. we only want "user" read-only 
					controlData[0].uValue = kTXNReadWrite;
					controlData[1].uValue = kTXNReadOnly;//user read-only needs to be set in this case
					err = ::TXNSetTXNObjectControls( txnObj, false, 2, controlTags, controlData );
				}
				
				//setting up margins confuses scroller about the size of text. MLTE is hopeless.
				controlTags[0] = kTXNMarginsTag;
				TXNMargins txnMargins = { 1, 4, 0, 0 };  //t,l,b,r
				controlData[0].marginsPtr  = &txnMargins; 
				err = ::TXNSetTXNObjectControls( txnObj, false, 1, controlTags, controlData );
				
				CFObj<CFStringRef> customFontName( NibDialogControl::CreateControlPropertyString(myControl, 'OMC!', kCustomFontName) );
				CFObj<CFStringRef> customFontSize( NibDialogControl::CreateControlPropertyString(myControl, 'OMC!', kCustomFontSize) );
				if( (customFontName != NULL) || (customFontSize != NULL) )
				{
					SInt32 fontSize = 0;
					if(customFontSize != NULL)
						fontSize = ::CFStringGetIntValue( customFontSize );
					SetTXNStyle(txnObj, customFontName, fontSize);
				}
			}
		}

		case kControlKindBevelButton:
		{
			Boolean doScale = true;
			SetControlData(myControl, kControlNoPart, kControlBevelButtonScaleIconTag, sizeof(Boolean), &doScale);
		}
		case kControlKindIcon:
		case kControlKindRoundButton:
		{
			
			CFObj<CFStringRef> inValue( NibDialogControl::CreateControlPropertyString(myControl, 'OMC!', kControlCustomValueKey) );
			if(inValue != NULL)
			{
				CFObj<CFURLRef> imageURL;
				if(inExternBundle != NULL)
					imageURL.Adopt( CreateResourceFileURL(inExternBundle, inValue) );

				if(imageURL == NULL)
					imageURL.Adopt( CreateResourceFileURL(inMainBundle, inValue) );

				Boolean icnsFound = false;
				if(imageURL != NULL)
				{
					CFObj<CFStringRef> theExt( ::CFURLCopyPathExtension(imageURL) );
					if(theExt != NULL)
					{
						if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("icns"), theExt, kCFCompareCaseInsensitive) )
						{
							icnsFound = true;
						}
					}
				}
				
				if(icnsFound)
				{
					ControlButtonContentInfo contentInfo;
					contentInfo.contentType = kControlContentIconRef;
					contentInfo.u.iconRef = CreateIconRefFromFile(imageURL);
					err = SetControlData(myControl, kControlNoPart, kControlImageWellContentTag, sizeof(contentInfo), &contentInfo);
					//iconRef is retained by control, we can release our reference
					if(contentInfo.u.iconRef != 0)
						ReleaseIconRef(contentInfo.u.iconRef);
				}
			}		
		}
		break;

		case kControlKindClock:
		{
			CFObj<CFStringRef> inValue( NibDialogControl::CreateControlPropertyString(myControl, 'OMC!', kControlCustomValueKey) );
			if(inValue != NULL)
			{
				SetClockString(myControl, inValue);
			}
		}
		break;

		case 'imag'://HIImageView, control kind not defined by Apple in headers
		{
			CFObj<CFStringRef> inValue( NibDialogControl::CreateControlPropertyString(myControl, 'OMC!', kControlCustomValueKey) );
			if(inValue != NULL)
			{
				CFObj<CFURLRef> imageURL;
				if(inExternBundle != NULL)
					imageURL.Adopt( CreateResourceFileURL(inExternBundle, inValue) );

				if(imageURL == NULL)
					imageURL.Adopt( CreateResourceFileURL(inMainBundle, inValue) );

				CGImageRef cgImage = CreateImageFromFile(imageURL);
				err = ::HIImageViewSetImage(myControl, cgImage);//NULL image is OK
				if(cgImage != NULL)
					::CGImageRelease(cgImage);
				::HIViewSetNeedsDisplay(myControl, true);
			}
		}
		break;

//CG image stuff does not work as of Mac OS 10.3
		case kControlKindImageWell:
		{
			CFObj<CFStringRef> inValue( NibDialogControl::CreateControlPropertyString(myControl, 'OMC!', kControlCustomValueKey) );
			if(inValue != NULL)
			{
				CFObj<CFURLRef> imageURL;
				if(inExternBundle != NULL)
					imageURL.Adopt( CreateResourceFileURL(inExternBundle, inValue) );

				if(imageURL == NULL)
					imageURL.Adopt( CreateResourceFileURL(inMainBundle, inValue) );

				Boolean icnsFound = false;
				if(imageURL != NULL)
				{
					CFObj<CFStringRef> theExt( ::CFURLCopyPathExtension(imageURL) );
					if(theExt != NULL)
					{
						if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("icns"), theExt, kCFCompareCaseInsensitive) )
						{
							icnsFound = true;
						}
					}
				}
				
				if(icnsFound)
				{
					ControlButtonContentInfo contentInfo;
					contentInfo.contentType = kControlContentIconRef;
					contentInfo.u.iconRef = CreateIconRefFromFile(imageURL);
					err = SetControlData(myControl, kControlNoPart, kControlImageWellContentTag, sizeof(contentInfo), &contentInfo);
					//iconRef is retained by control, we can release our reference
					if(contentInfo.u.iconRef != 0)
						ReleaseIconRef(contentInfo.u.iconRef);
				}
				else
				{
					ControlButtonContentInfo contentInfo;
					contentInfo.contentType = kControlContentCGImageRef;
					contentInfo.u.imageRef = CreateImageFromFile(imageURL);
					//err = SetImageWellContentInfo(dropTarget, &cbci);
					err = SetControlData(myControl, kControlNoPart, kControlImageWellContentTag, sizeof(contentInfo), &contentInfo);
					if(contentInfo.u.imageRef != NULL)
						::CGImageRelease(contentInfo.u.imageRef);
				}
			}
		}
		break;
		
		case kControlKindTabs:
		{
			new NibTabHandler(myControl, true, true);//self-deleting on control destruction
//			controlHandler = (AStdNewLink *)new NibTabHandler(myControl, true, true);
		}
		break;
		
		case kControlKindDataBrowser:
		{
			err = OMCDataBrowser::InitializeControl(myControl);
			//we need to know in advance if we are dealing with selection iterator in table control
			CFObj<CFStringRef> commandListString( NibDialogControl::CreateControlPropertyString(myControl, 'OMC!', kSelectionIteratingCommands) );//'ite!' property
			if( (commandListString != NULL) && (::CFStringGetLength(commandListString) >= 4) )
				outHasSelectionIterator = true;
		}
		break;
	}
	
	return controlKind.kind;
}

#pragma mark -

#if 1
//static
//non-four char chars are padded with spaces
//the min number is 0 which needs to be translated into '0   ' = 0x30202020
//the max number is 9999 which needs to be translated in '9999' = 0x39393939

FourCharCode
NibDialogControl::NumberToFourCharCode(UInt32 inNum)
{
	FourCharCode outCode = '    ';//we start with 4 spaces
	UInt32 rest = inNum%10;
	if(inNum > 999)
	{//4 digits
		outCode &= 0xFFFFFF00;//clear the space
		outCode |= ('0' + rest);
		inNum /= 10;
		rest = inNum%10;
	}
	
	if(inNum > 99)
	{//3 digits
		outCode &= 0xFFFF00FF;//clear the space
		outCode |= ('0' + rest) << 8;
		inNum /= 10;
		rest = inNum%10;
	}
	
	if(inNum > 9)
	{//2 digits
		outCode &= 0xFF00FFFF;//clear the space
		outCode |= ('0' + rest) << 16;
		inNum /= 10;
		rest = inNum%10;
	}
	
	//1 digit
	outCode &= 0x00FFFFFF;//clear the space
	outCode |= (('0' + rest) << 24);

#if _DEBUG_
//do not swap here, it is all OK at this point on any machine
	FourCharCode swapped = ::CFSwapInt32BigToHost(outCode);
	printf("NibDialogControl::NumberToFourCharCode: origNum= %u Unswapped FourCharCode = 0X%.8X, swapped=0X%.8X\n", (unsigned int)inNum, (unsigned int)outCode, (unsigned int)swapped);
#endif //_DEBUG
	
	return outCode;
}

#else

FourCharCode
NibDialogControl::NumberToFourCharCode(UInt32 inNum)
{
	return '123 ';

	CFObj<CFStringRef> numStr( ::CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%u"), inNum) );
	FourCharCode outCode = ::UTGetOSTypeFromString( numStr );//creates four char code padded with zeros for less than 4 chacaters
#if _DEBUG_
	printf("NibDialogControl::NumberToFourCharCode: origNum= %u FourCharCode = 0X%.8X\n", inNum, outCode);
#endif //_DEBUG
	return outCode;
}
#endif

#pragma mark -

CFURLRef
NibDialogControl::CreateResourceFileURL(CFBundleRef inBundle, CFStringRef inFileName)
{
	CFIndex strLen = ::CFStringGetLength(inFileName);
	if(strLen == 0)
		return NULL;

	UniChar firstChar = ::CFStringGetCharacterAtIndex(inFileName, 0);
	CFURLRef url = NULL;
	
	if(firstChar == (UniChar)'/')
	{//absolute path
		url = ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, inFileName, kCFURLPOSIXPathStyle, false);
	}
	else
	{//image in resources
		if(inBundle == NULL)
			inBundle = ::CFBundleGetMainBundle();
		url = ::CFBundleCopyResourceURL( inBundle, inFileName, NULL, NULL );
	}
	return url;
}


//caller responsible for releasing non-null CGImageRef with CGImageRelease()
CGImageRef
NibDialogControl::CreateImageFromFile(CFURLRef inURL)
{
	CGImageRef outImage = NULL;

	if( inURL == NULL )
		return NULL;

	CFObj<CGImageSourceRef> imgSource( CGImageSourceCreateWithURL(inURL, NULL) );
	if(imgSource != NULL)
		outImage = CGImageSourceCreateImageAtIndex( imgSource, 0, NULL );

	return outImage;
}

//available in OS 10.3 or higher because of GetIconRefFromIconFamilyPtr
//caller responsibe for releasing non-zero IconRef with ReleaseIconRef() 
IconRef
NibDialogControl::CreateIconRefFromFile(CFURLRef inURL)
{
	if( inURL == NULL )
		return 0;

	FSRef fileRef;
	memset(&fileRef, 0, sizeof(fileRef));
	Boolean isFileRefValid = ::CFURLGetFSRef(inURL, &fileRef);

    IconFamilyHandle iconFamily = NULL;	
	OSStatus err = ReadIconFromFSRef(&fileRef, &iconFamily);
    if(iconFamily == NULL)
    	return 0;

    HLock((Handle)iconFamily);
	Size dataSize = GetHandleSize((Handle)iconFamily);
	IconRef iconRef = 0;
    GetIconRefFromIconFamilyPtr(*iconFamily, dataSize, &iconRef);
    HUnlock((Handle)iconFamily);
    DisposeHandle((Handle)iconFamily);
    
    return iconRef;
}

#if OLD_QUICKTIME_MOVIE

Movie
NibDialogControl::CreateMovieFromFile(CFURLRef inURL)
{
	if( inURL == NULL )
		return NULL;

	Handle movieReference = NULL;
	OSType referenceType = 0;

	OSErr err = ::QTNewDataReferenceFromCFURL(
						inURL,
						0, //UInt32      flags, //unused
						&movieReference,
						&referenceType );
	
	if( movieReference == NULL )
		return NULL;

	Movie newMovie = NULL;
	err = ::NewMovieFromDataRef (
						&newMovie,
						0, //short     flags,
						NULL, //short     *id,
						movieReference,
						referenceType );

	::DisposeHandle( movieReference );
    
    return newMovie;
}
#endif //OLD_QUICKTIME_MOVIE
#endif //__LP64__

#pragma mark -

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
CreateTableIDAndColumnFromString(CFStringRef inControlIDString, CFIndex &outColumnIndex, bool useAllRows, bool isEnvStyle)
{
	outColumnIndex = 0;

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
		//if(numberStr != NULL)
		//	controlID = ::CFStringGetIntValue (numberStr);
	}

	CFRange numberStrRange;
	numberStrRange.location = columnStrRange.location + columnStrRange.length;
	numberStrRange.length = actualLen - (columnStrRange.location + columnStrRange.length) - suffixLen;
	if( numberStrRange.length > 0 )
	{
		CFObj<CFStringRef> numberStr( ::CFStringCreateWithSubstring(kCFAllocatorDefault, inControlIDString, numberStrRange) );
		if(numberStr != NULL)
			outColumnIndex = (CFIndex)::CFStringGetIntValue (numberStr);
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


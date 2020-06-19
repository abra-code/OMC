/*
 *  OMCDialog.cpp
 *  Abracode
 *
 *  Created by Tomasz Kukielka on 3/2/08.
 *  Copyright 2008 Abracode. All rights reserved.
 *
 */

#include "OMCDialog.h"
#include "AppGroupIdentifier.h"
#include "OnMyCommand.h"
#include "NibDialogControl.h"
#include "ACFType.h"

OMCDialog * OMCDialog::sChainHead = NULL;

OMCDialog::OMCDialog()
	: next(NULL),
	mTaskObserver( new AObserver<OMCDialog>(this) ),
	mSelectionIterator(NULL)
{
	//add ourselves to linked list
	if(sChainHead == NULL)
	{
		sChainHead = this;
	}
	else
	{
		OMCDialog *oneLink = sChainHead;
		//find the tail
		while(oneLink->next != NULL)
			oneLink = oneLink->next;
		oneLink->next = this;
	}

}

OMCDialog::~OMCDialog()
{
	if(mTaskObserver != NULL)
		mTaskObserver->SetOwner(NULL);//observer may outlive us so it is very important to tell that we died

	//remove ourselves from linked list
	OMCDialog *prevLink = NULL;
	OMCDialog *oneLink = sChainHead;
	while(oneLink != NULL)
	{
		if(oneLink == this)
		{
			if(prevLink != NULL) //connect it to previous
				prevLink->next = this->next;
			else //or make it a head (prevLink is NULL only on first iteration)
				sChainHead = this->next;
			this->next = NULL;
			break;
		}
		prevLink = oneLink;
		oneLink = oneLink->next;
	}
}

//caller should NOT release the result string

CFStringRef
OMCDialog::GetDialogUniqueID()
{
	if(mDialogUniqueID != NULL)
		return mDialogUniqueID;

	CFObj<CFUUIDRef>  myUUID( ::CFUUIDCreate(kCFAllocatorDefault) );
	if(myUUID != NULL)
		mDialogUniqueID.Adopt( ::CFUUIDCreateString(kCFAllocatorDefault, myUUID) );

	return mDialogUniqueID;
}

void
OMCDialog::StartListening()
{
	CFObj<CFStringRef> portName( ::CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%s.OMCDialogControlPort-%@"), GetAppGroupIdentifier(), GetDialogUniqueID()) );
	mListener.StartListening(this, portName);
}


/*static*/
ARefCountedObj<OMCDialog>
OMCDialog::FindDialogByGUID(CFStringRef inGUID)
{
	ARefCountedObj<OMCDialog> outDialog;
	if(inGUID == nullptr)
		return outDialog;

	OMCDialog *oneLink = sChainHead;
	while(oneLink != nullptr)
	{
		CFStringRef oneGUID = oneLink->mDialogUniqueID;//do not generate if never requested before, cannot be equal in such case
		if( (oneGUID != nullptr) && (CFStringCompare(oneGUID, inGUID, 0) == kCFCompareEqualTo) )
		{
			outDialog.Adopt(oneLink, kARefCountRetain);
			break;
		}

		oneLink = oneLink->next;
	}

	return outDialog;
}

//static
CFStringRef
OMCDialog::CreateControlValueString(CFTypeRef controlValue, CFDictionaryRef customProperties, UInt16 escSpecialCharsMode, bool isEnvStyle) noexcept
{
	CFStringRef newStrRef = nullptr;
	if(controlValue == nullptr)
		return nullptr;
	
	CFStringRef oneProperty = nullptr;
	if( !isEnvStyle && (customProperties != nullptr) ) //in environment variables we don't put escapings
	{
		oneProperty = ACFType<CFStringRef>::DynamicCast( CFDictionaryGetValue(customProperties, (const void *)kCustomEscapeMethodKey) );
		if(oneProperty != nullptr)
			escSpecialCharsMode = GetEscapingMode(oneProperty);
	}

	//it can be string or array of strings
	CFTypeID valType = ::CFGetTypeID( (CFTypeRef)controlValue );
	if( valType == ACFType<CFStringRef>::sTypeID )//regular string
	{
		newStrRef = CreateEscapedStringCopy( (CFStringRef)(CFTypeRef)controlValue, escSpecialCharsMode);
	}
	else if( valType == ACFType<CFArrayRef>::sTypeID )
	{
		CFStringRef prefix = nullptr;
		CFStringRef suffix = nullptr;
		CFStringRef separator =  CFSTR("\t"); //separate with tab byy default

		if(customProperties != nullptr)
		{
			oneProperty = ACFType<CFStringRef>::DynamicCast( CFDictionaryGetValue(customProperties, (const void *)kCustomPrefixKey) );
			if(oneProperty != nullptr)
				prefix = oneProperty;

			oneProperty = ACFType<CFStringRef>::DynamicCast( CFDictionaryGetValue(customProperties, (const void *)kCustomSuffixKey) );
			if(oneProperty != nullptr)
				suffix = oneProperty;

			oneProperty = ACFType<CFStringRef>::DynamicCast( CFDictionaryGetValue(customProperties, (const void *)kCustomSeparatorKey) );
			if(oneProperty != nullptr)
				separator = oneProperty;

		}
		newStrRef = CreateCombinedString( (CFArrayRef)(CFTypeRef)controlValue, separator, prefix, suffix, escSpecialCharsMode );
	}

	return newStrRef;
}

//string or array of strings
CFStringRef
OMCDialog::CreateNibControlValue(SInt32 inSpecialWordID, CFStringRef inNibControlString, UInt16 escSpecialCharsMode, bool isEnvStyle) noexcept
{
	CFObj<CFTypeRef> oneValue;
	CFObj<CFStringRef> partIDStr(CFSTR("0"), kCFObjRetain);
	CFObj<CFStringRef> controlID;

	TRACE_CFSTR(CFSTR("OnMyCommandCM::CreateNibControlValue"));

	if((mNibControlValues == nullptr) || (CFDictionaryGetCount(mNibControlValues) == 0))
		return nullptr;

	if( inSpecialWordID == NIB_DLG_CONTROL_VALUE ) //regular control query
	{
		controlID.Adopt( CreateControlIDFromString(inNibControlString, isEnvStyle), kCFObjDontRetain );
	}
	else if( (inSpecialWordID == NIB_TABLE_VALUE) || (inSpecialWordID == NIB_TABLE_ALL_ROWS) ) //table control query
	{
		controlID.Adopt( CreateTableIDAndColumnFromString(inNibControlString, partIDStr, inSpecialWordID == NIB_TABLE_ALL_ROWS, isEnvStyle), kCFObjDontRetain );

		if( inSpecialWordID == NIB_TABLE_ALL_ROWS )
		{ //saved as unique value in the dictionary
			CFObj<CFStringRef> newControlID( CreateControlIDByAddingModifiers(controlID, kControlModifier_AllRows) );
			controlID.Swap(newControlID);
		}
	}
	else if( inSpecialWordID == NIB_WEB_VIEW_VALUE ) //OMCWebView control query
	{
		partIDStr.Adopt(CFSTR(""), kCFObjRetain);
		controlID.Adopt( CreateWebViewIDAndElementIDFromString(inNibControlString, partIDStr, isEnvStyle), kCFObjDontRetain );
	}

	DEBUG_CFSTR((CFStringRef)controlID);

	CFDictionaryRef customProperties = nullptr;

	//we should have all the values already read from the dialog controls

	const void *theItem = ::CFDictionaryGetValue(mNibControlValues, (CFStringRef)controlID);
	CFDictionaryRef columnIds = ACFType<CFDictionaryRef>::DynamicCast(theItem);
	if((columnIds != nullptr) && (partIDStr != nullptr))
	{
		theItem = ::CFDictionaryGetValue(columnIds, (const void *)(CFStringRef)partIDStr);
		oneValue.Adopt((CFTypeRef)theItem, kCFObjRetain);
		if((oneValue != nullptr) && (mNibControlCustomProperties != nullptr))
			customProperties = ACFType<CFDictionaryRef>::DynamicCast(CFDictionaryGetValue(mNibControlCustomProperties, (CFStringRef)controlID));
	}

	CFStringRef controlValue = CreateControlValueString(oneValue, customProperties, escSpecialCharsMode, isEnvStyle);

	TRACE_CSTR("\texiting CreateNibControlValue\n");

	return controlValue;
}

void
OMCDialog::AddEnvironmentVariablesForAllControls(CFMutableDictionaryRef ioEnvironList) noexcept
{
	if(mNibControlValues == nullptr)
		return;

	CFIndex controlCount = CFDictionaryGetCount(mNibControlValues);
	if(controlCount == 0)
		return;

	std::vector<CFTypeRef> keyList(controlCount);
	std::vector<CFTypeRef> valueList(controlCount);

	CFDictionaryGetKeysAndValues(mNibControlValues, (const void **)keyList.data(), (const void **)valueList.data());
	for(CFIndex i = 0; i < controlCount; i++)
	{
		CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
		CFDictionaryRef partsDict = ACFType<CFDictionaryRef>::DynamicCast( valueList[i] );
		if((controlID != nullptr) && (partsDict != nullptr))
		{
			CFDictionaryRef controlProperties = (CFDictionaryRef)CFDictionaryGetValue(mNibControlCustomProperties, controlID);
			CFIndex partsCount = CFDictionaryGetCount(partsDict);
			if(partsCount == 1)
			{
				//parts dictionary keys are CFStringRefs
				CFTypeRef controlValue = CFDictionaryGetValue(partsDict, (void *)CFSTR("0"));
				if(controlValue != nullptr)
				{
					CFObj<CFStringRef> controlValueString = CreateControlValueString(controlValue, controlProperties, kEscapeNone, true);
					if(controlValueString != nullptr)
					{
						CFObj<CFStringRef> controlEnvName(CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("OMC_NIB_DIALOG_CONTROL_%@_VALUE"), controlID));
						CFDictionarySetValue(ioEnvironList, controlEnvName, controlValueString);
					}
				}
			}
			// previously only table views had multiple parts, now WebKit view has multiple elements
			else if(partsCount > 1)
			{
				std::vector<CFTypeRef> partIDs(partsCount);
				std::vector<CFTypeRef> partValues(partsCount);
				CFDictionaryGetKeysAndValues(partsDict, (const void **)partIDs.data(), (const void **)partValues.data());
				
				Boolean isWebView = CFDictionaryContainsKey(partsDict, CFSTR("@")); //this otherwise invalid key indicates it is a WebView
				
				CFStringRef envVariableFormat = CFSTR("OMC_NIB_TABLE_%@_COLUMN_%@_VALUE");
				if(isWebView)
					envVariableFormat = CFSTR("OMC_NIB_WEBVIEW_%@_ELEMENT_%@_VALUE");
				
				for(CFIndex k = 0; k < partsCount; k++)
				{
					CFTypeRef partID = partIDs[k];
					CFTypeRef partValue = partValues[k];
					if( (partValue != nullptr) && (CFStringCompare((CFStringRef)partID, CFSTR("@"), 0) != kCFCompareEqualTo) )
					{
						CFObj<CFStringRef> partValueString = CreateControlValueString(partValue, controlProperties, kEscapeNone, true);
						if(partValueString != nullptr)
						{
							CFObj<CFStringRef> controlAndPartEnvName(CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, envVariableFormat, controlID, partID));
							CFDictionarySetValue(ioEnvironList, controlAndPartEnvName, partValueString);
						}
					}
				}
			}
			else
			{
				continue;
			}
		}
	}
}

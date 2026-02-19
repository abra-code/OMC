//
//  OMCActionUIDialog.mm
//  Abracode
//
//  Created by Tomasz Kukielka on 2/17/26.
//  Copyright 2026 Abracode. All rights reserved.
//

#import "OMCActionUIDialog.h"
#import "OMCActionUIWindowController.h"
#import "OMCControlAccessor.h"
#include "OnMyCommand.h"
#include "CommandRuntimeData.h"
#include "NibDialogControl.h"
#include "ACFType.h"
#include "OMCStrings.h"

ARefCountedObj<OMCDialog> RunActionUIDialog(OnMyCommandCM *inPlugin, CommandRuntimeData *commandRuntimeData)
{
	ARefCountedObj<OMCDialog> outDialog;
	if(inPlugin == nullptr)
		return outDialog;

	assert(commandRuntimeData != nullptr);

	@autoreleasepool
	{
		@try
		{
			OMCActionUIWindowController *windowController = [[OMCActionUIWindowController alloc] initWithOmc:inPlugin
																		  commandRuntimeData:commandRuntimeData];
			if(windowController != nullptr)
			{
				outDialog.Adopt( [windowController getOMCDialog], kARefCountRetain );

				[windowController run];
				if( [windowController isModal] )
				{
					if( [windowController isOkeyed] )
					{
						if(outDialog != nullptr)
						{
							outDialog->CopyAllControlValues(nullptr, nullptr);
						}
					}
					else
					{
						outDialog.Adopt(nullptr);
					}
				}
			}
		}
		@catch (NSException *localException)
		{
			NSLog(@"RunActionUIDialog received exception: %@", localException);
			outDialog.Adopt(nullptr);
		}
	}

	return outDialog;
}

#pragma mark -

CFStringRef
OMCActionUIDialog::CreateControlValue(SInt32 inSpecialWordID, CFStringRef inControlString, UInt16 escSpecialCharsMode, bool isEnvStyle) noexcept
{
	if(inSpecialWordID != ACTIONUI_VIEW_VALUE)
		return nullptr;

	if((mControlValues == nullptr) || (CFDictionaryGetCount(mControlValues) == 0))
		return nullptr;

	CFObj<CFStringRef> controlID( CreateActionUIViewIDFromString(inControlString, isEnvStyle), kCFObjDontRetain );
	if(controlID == nullptr)
		return nullptr;

	const void *theItem = ::CFDictionaryGetValue(mControlValues, (CFStringRef)controlID);
	CFDictionaryRef columnIds = ACFType<CFDictionaryRef>::DynamicCast(theItem);
	if(columnIds == nullptr)
		return nullptr;

	theItem = ::CFDictionaryGetValue(columnIds, (const void *)CFSTR("0"));
	if(theItem == nullptr)
		return nullptr;

	CFObj<CFTypeRef> oneValue((CFTypeRef)theItem, kCFObjRetain);
	CFDictionaryRef customProperties = nullptr;
	if(mControlCustomProperties != nullptr)
		customProperties = ACFType<CFDictionaryRef>::DynamicCast(CFDictionaryGetValue(mControlCustomProperties, (CFStringRef)controlID));

	return CreateControlValueString(oneValue, customProperties, escSpecialCharsMode, isEnvStyle);
}

void
OMCActionUIDialog::AddEnvironmentVariablesForAllControls(CFMutableDictionaryRef ioEnvironList) noexcept
{
	if(mControlValues == nullptr)
		return;

	CFIndex controlCount = CFDictionaryGetCount(mControlValues);
	if(controlCount == 0)
		return;

	std::vector<CFTypeRef> keyList(controlCount);
	std::vector<CFTypeRef> valueList(controlCount);

	CFDictionaryGetKeysAndValues(mControlValues, (const void **)keyList.data(), (const void **)valueList.data());
	for(CFIndex i = 0; i < controlCount; i++)
	{
		CFStringRef controlID = ACFType<CFStringRef>::DynamicCast(keyList[i]);
		CFDictionaryRef partsDict = ACFType<CFDictionaryRef>::DynamicCast(valueList[i]);
		if((controlID != nullptr) && (partsDict != nullptr))
		{
			CFTypeRef controlValue = CFDictionaryGetValue(partsDict, (void *)CFSTR("0"));
			if(controlValue != nullptr)
			{
				CFObj<CFStringRef> controlValueString = CreateControlValueString(controlValue, nullptr, kEscapeNone, true);
				if(controlValueString != nullptr)
				{
					CFObj<CFStringRef> controlEnvName(CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("OMC_ACTIONUI_VIEW_%@_VALUE"), controlID));
					CFDictionarySetValue(ioEnvironList, controlEnvName, controlValueString);
				}
			}
		}
	}
}

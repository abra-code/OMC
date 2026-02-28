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
#include "OMCDialogControlHelpers.h"
#include "ACFType.h"
#include "OMCStrings.h"

// enable only in OMC version 5.0 or later
#if CURRENT_OMC_VERSION >= 50000
@import ActionUIObjCAdapter;
#endif

ARefCountedObj<OMCDialog> RunActionUIDialog(OnMyCommandCM *inPlugin, CommandRuntimeData *commandRuntimeData)
{
	ARefCountedObj<OMCDialog> outDialog;

#if CURRENT_OMC_VERSION >= 50000
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
#endif // CURRENT_OMC_VERSION >= 50000

	return outDialog;
}

#pragma mark -

#if CURRENT_OMC_VERSION >= 50000

void
OMCActionUIDialog::CopyAllControlValues(CFSetRef requestedNibControls, SelectionIterator *inSelIterator) noexcept
{
    // Let the base class collect standard control values via allControlValues:andProperties:withIterator:
    OMCDialog::CopyAllControlValues(requestedNibControls, inSelIterator);

    if(requestedNibControls == nullptr)
        return;

    CFIndex specialWordCount = ::CFSetGetCount(requestedNibControls);
    if(specialWordCount <= 0)
        return;

    // Get the window UUID for ActionUI API calls
    NSString *windowUUID = (__bridge NSString *)GetDialogUUID();
    if(windowUUID.length == 0)
        return;

    std::vector<CFStringRef> specialWordList(specialWordCount);
    CFSetGetValues(requestedNibControls, (const void **)specialWordList.data());

    for(CFIndex i = 0; i < specialWordCount; i++)
    {
        CFStringRef specialWord = specialWordList[i];
        bool isEnvironVariable = false;
        SpecialWordID specialWordID = GetSpecialWordID(specialWord);
        if(specialWordID == NO_SPECIAL_WORD)
        {
            specialWordID = GetSpecialEnvironWordID(specialWord);
            isEnvironVariable = true;
        }

        if(specialWordID != ACTIONUI_TABLE_ALL_ROWS)
            continue;

        // Parse "OMC_ACTIONUI_TABLE_N_COLUMN_M_ALL_ROWS" → controlID="N", columnIndexStr="M"
        CFObj<CFStringRef> columnIndexStr(CFSTR("0"), kCFObjRetain);
        CFObj<CFStringRef> controlID( CreateActionUITableIDAndColumnFromString(specialWord, columnIndexStr, true, isEnvironVariable), kCFObjDontRetain );
        if(controlID == nullptr)
            continue;

        NSString *viewIDStr = (__bridge NSString *)(CFStringRef)controlID;
        NSInteger viewID = [viewIDStr integerValue];

        // Fetch all content rows from ActionUI
        NSArray<NSArray<NSString*>*> *allRows = [ActionUIObjC getElementRowsWithWindowUUID:windowUUID viewID:viewID];
        if (allRows == nil)
            allRows = @[];

        NSInteger colIdx = [((__bridge NSString *)(CFStringRef)columnIndexStr) integerValue]; // 0 = whole row, 1..N = column

        NSMutableArray<NSString*> *columnValues = [NSMutableArray arrayWithCapacity:allRows.count];
        for(NSArray<NSString*> *row in allRows)
        {
            if(colIdx == 0)
            {
                // Whole row: join columns with tab
                [columnValues addObject:[row componentsJoinedByString:@"\t"]];
            }
            else
            {
                // Specific column (1-based) → 0-based array index
                NSInteger arrayIdx = colIdx - 1;
                [columnValues addObject:(arrayIdx < (NSInteger)row.count) ? row[arrayIdx] : @""];
            }
        }

        // Join all-row values with newline and store under allRows modifier key
        NSString *allRowsString = [columnValues componentsJoinedByString:@"\n"];
        CFObj<CFStringRef> allRowsCFStr((__bridge CFStringRef)allRowsString, kCFObjRetain);
        CFObj<CFStringRef> allRowsControlID( CreateControlIDByAddingModifiers(controlID, kControlModifier_AllRows) );

        StoreControlValue(allRowsControlID, allRowsCFStr, columnIndexStr);
    }
}

CFStringRef
OMCActionUIDialog::CreateControlValue(SInt32 inSpecialWordID, CFStringRef inControlString, UInt16 escSpecialCharsMode, bool isEnvStyle) noexcept
{
	if((mControlValues == nullptr) || (CFDictionaryGetCount(mControlValues) == 0))
		return nullptr;

	CFObj<CFStringRef> controlID;
	CFObj<CFStringRef> partIDStr(CFSTR("0"), kCFObjRetain);

	if(inSpecialWordID == ACTIONUI_VIEW_VALUE)
	{
		controlID.Adopt( CreateActionUIViewIDFromString(inControlString, isEnvStyle), kCFObjDontRetain );
	}
	else if( (inSpecialWordID == ACTIONUI_TABLE_VALUE) || (inSpecialWordID == ACTIONUI_TABLE_ALL_ROWS) )
	{
		controlID.Adopt( CreateActionUITableIDAndColumnFromString(inControlString, partIDStr, inSpecialWordID == ACTIONUI_TABLE_ALL_ROWS, isEnvStyle), kCFObjDontRetain );

		if(inSpecialWordID == ACTIONUI_TABLE_ALL_ROWS)
		{
			CFObj<CFStringRef> newControlID( CreateControlIDByAddingModifiers(controlID, kControlModifier_AllRows) );
			controlID.Swap(newControlID);
		}
	}
	else
	{
		return nullptr;
	}

	if(controlID == nullptr)
		return nullptr;

	const void *theItem = ::CFDictionaryGetValue(mControlValues, (CFStringRef)controlID);
	CFDictionaryRef columnIds = ACFType<CFDictionaryRef>::DynamicCast(theItem);
	if(columnIds == nullptr)
		return nullptr;

	theItem = ::CFDictionaryGetValue(columnIds, (const void *)(CFStringRef)partIDStr);
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
		if((controlID == nullptr) || (partsDict == nullptr))
			continue;

		CFIndex partsCount = CFDictionaryGetCount(partsDict);
		if(partsCount == 1)
		{
			// Single-value control: export as OMC_ACTIONUI_VIEW_N_VALUE
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
		else if(partsCount > 1)
		{
			// Multi-column table control: export each column as OMC_ACTIONUI_TABLE_N_COLUMN_M_VALUE
			std::vector<CFTypeRef> partIDs(partsCount);
			std::vector<CFTypeRef> partValues(partsCount);
			CFDictionaryGetKeysAndValues(partsDict, (const void **)partIDs.data(), (const void **)partValues.data());

			for(CFIndex k = 0; k < partsCount; k++)
			{
				CFTypeRef partID = partIDs[k];
				CFTypeRef partValue = partValues[k];
				if(partValue != nullptr)
				{
					CFObj<CFStringRef> partValueString = CreateControlValueString(partValue, nullptr, kEscapeNone, true);
					if(partValueString != nullptr)
					{
						CFObj<CFStringRef> controlAndPartEnvName(CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("OMC_ACTIONUI_TABLE_%@_COLUMN_%@_VALUE"), controlID, (CFStringRef)partID));
						CFDictionarySetValue(ioEnvironList, controlAndPartEnvName, partValueString);
					}
				}
			}
		}
	}
}

#endif // CURRENT_OMC_VERSION >= 50000

//
//  OMCNibDialog.mm
//  Abracode
//
//  Created by Tomasz Kukielka on 3/1/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import "OMCNibDialog.h"
#import "OMCNibWindowController.h"
#include "OnMyCommand.h"
#include "CommandRuntimeData.h"
#include "CMUtils.h"
#include "ACFType.h"
#include "OmcTaskNotification.h"
#include "NibDialogControl.h"

ARefCountedObj<OMCDialog> RunNibDialog(OnMyCommandCM *inPlugin, CommandRuntimeData *commandRuntimeData)
{
	ARefCountedObj<OMCDialog > outDialog;
	if(inPlugin == nullptr)
		return outDialog;

    assert(commandRuntimeData != nullptr);
	CommandDescription &currCommand = inPlugin->GetCurrentCommand();

	@autoreleasepool
	{
		@try
		{
			OMCNibWindowController *myController = [[OMCNibWindowController alloc] initWithOmc:inPlugin
                                                                      commandRuntimeData:commandRuntimeData];
			if(myController != nullptr)
			{
				outDialog.Adopt( [myController getOMCDialog], kARefCountRetain );

				[myController run];
				if( [myController isModal] )
				{
					if( [myController isOkeyed] )
					{
						if(outDialog != nullptr)
						{
							outDialog->CopyAllControlValues(currCommand.specialRequestedNibControls, nullptr);
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
			NSLog(@"RunNibDialog received exception: %@", localException);
			outDialog.Adopt(nullptr);
		}
	} //@autoreleasepool

	return outDialog;
}

#pragma mark -

//proxy C++ class to comply with OMCDialog protocol in OMC


CFTypeRef
OMCNibDialog::CopyControlValue(CFStringRef inControlID, CFStringRef inControlPart, SelectionIterator *inSelIterator, CFDictionaryRef *outCustomProperties) noexcept
{
	if(outCustomProperties != NULL)
		*outCustomProperties = NULL;

	id outValue = NULL;

    @try
    {
        if(mController != NULL)
        {
            OMCNibWindowController *__weak controller = (__bridge OMCNibWindowController*)mController;
            outValue = [controller controlValueForID:(__bridge NSString *)inControlID
                                             forPart:(__bridge NSString *)inControlPart
                                        withIterator:inSelIterator
                                       outProperties:outCustomProperties];
        }
    }
    @catch (NSException *localException)
    {
        NSLog(@"OMCNibDialog::CopyControlValue received exception: %@", localException);
    }

    return (CFTypeRef)CFBridgingRetain(outValue);
}

// private helper
void
OMCNibDialog::StoreControlValue(CFStringRef controlID, CFTypeRef inValue, CFStringRef controlPart) noexcept
{
	CFObj<CFMutableDictionaryRef> columnIdAndValueDict;
	CFTypeRef columnValues = CFDictionaryGetValue(mControlValues, controlID);
	if(columnValues == NULL)
	{
		columnIdAndValueDict.Adopt( ::CFDictionaryCreateMutable(
					kCFAllocatorDefault,
					0,
					&kCFTypeDictionaryKeyCallBacks,
					&kCFTypeDictionaryValueCallBacks), kCFObjDontRetain );

		CFDictionarySetValue(mControlValues, controlID, (CFMutableDictionaryRef)columnIdAndValueDict);
	}
	else
	{
		columnIdAndValueDict.Adopt((CFMutableDictionaryRef)columnValues, kCFObjRetain);
	}

	CFDictionarySetValue(columnIdAndValueDict, (const void *)controlPart, (const void *)inValue);
}

void
OMCNibDialog::CopyAllControlValues(CFSetRef requestedNibControls, SelectionIterator *inSelIterator) noexcept
{
    //get values for all controls in the dialog
    //the code is generic to handle tables
    //regular controls do not have columns and the use 0 for column number to store their values
    //column index 0 is a meta value for table and means: get array of all column values
    //this way a regular method of querying controls works with table too: produces a selected row strings
    if(mControlValues == nullptr)
        mControlValues.Adopt(CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                            0,
                                                            &kCFTypeDictionaryKeyCallBacks,
                                                            &kCFTypeDictionaryValueCallBacks),
                                                            kCFObjDontRetain);

    if(mControlCustomProperties == nullptr)
        mControlCustomProperties.Adopt(CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                                        0,
                                                                        &kCFTypeDictionaryKeyCallBacks,
                                                                        &kCFTypeDictionaryValueCallBacks),
                                                                    kCFObjDontRetain);//values will be CFStringRefs

    @try
    {
        if(mController != NULL)
        {
            [(__bridge OMCNibWindowController*)mController
                         allControlValues:(__bridge NSMutableDictionary *)mControlValues.Get()
                            andProperties:(__bridge NSMutableDictionary *)mControlCustomProperties.Get()
                             withIterator:inSelIterator];
        }
    }
    @catch (NSException *localException)
    {
        NSLog(@"OMCNibDialog::CopyAllControlValues received exception: %@", localException);
    }

    // after getting all standard values from controls, also check if there is a request
    // for special expensive values not covered by CopyAllControlValues
    if(requestedNibControls == nullptr)
        return;

    CFIndex specialWordCount = ::CFSetGetCount(requestedNibControls);
    if(specialWordCount <= 0)
        return;

    std::vector<CFStringRef> specialWordList(specialWordCount);
    CFSetGetValues(requestedNibControls, (const void **)specialWordList.data());
    for(CFIndex i = 0; i < specialWordCount; i++)
    {
        CFStringRef specialWord = (CFStringRef)specialWordList[i];
        bool isEnvironVariable = false;
        SpecialWordID specialWordID = GetSpecialWordID(specialWord);
        if(specialWordID == NO_SPECIAL_WORD)
        {
            specialWordID = GetSpecialEnvironWordID(specialWord);
            isEnvironVariable = true;
        }

        if(specialWordID == NIB_TABLE_ALL_ROWS) //the only special request currently supported
        {
            CFObj<CFStringRef> columnIndexStr(CFSTR("0"), kCFObjRetain);
            CFObj<CFStringRef> controlID( CreateTableIDAndColumnFromString(specialWord, columnIndexStr, true, isEnvironVariable), kCFObjDontRetain );
            
            SelectionIterator *selIterator = AllRowsIterator_Create();
            CFObj<CFDictionaryRef> customProperties;
            CFObj<CFTypeRef> oneValue( CopyControlValue(controlID, columnIndexStr, selIterator, &customProperties) );
            SelectionIterator_Release(selIterator);

            if(oneValue != nullptr)
            {
                CFObj<CFStringRef> allRowsControlID(CreateControlIDByAddingModifiers(controlID, kControlModifier_AllRows));
                StoreControlValue(allRowsControlID, oneValue, columnIndexStr);
            
                //custom escaping, prefix, suffix or separator
                if(customProperties != nullptr)
                {
                    ::CFDictionarySetValue( mControlCustomProperties,
                                            (const void *)allRowsControlID,
                                            (const void *)(CFDictionaryRef)customProperties); //CFTypeRef is retained
                }
            }
        }
    }
}


//port communication support for dialog
//when this port is set-up the command line tool "omc_dialog_control" sends messages to this port
//instead of saving to file and wait for command to finish

//inData is a plist XML data in exactly the same format as read from temp plist file for disk-based communication
CFDataRef
OMCNibDialog::ReceivePortMessage( SInt32 msgid, CFDataRef inData ) noexcept
{
	if( mController == NULL )
		return NULL;

	CFObj<CFPropertyListRef> thePlist( CFPropertyListCreateWithData( kCFAllocatorDefault, inData,
                                                                       kCFPropertyListImmutable, nullptr, nullptr) );
	CFDictionaryRef plistDict = ACFType<CFDictionaryRef>::DynamicCast( (CFPropertyListRef)thePlist );

    @try
    {
        if(plistDict != NULL)
        {
            [(__bridge OMCNibWindowController*)mController setControlValues:plistDict];
            
        }
    }
    @catch (NSException *localException)
    {
        NSLog(@"OMCNibDialog::ReceivePortMessage received exception: %@", localException);
    }

	return NULL;
}


void
OMCNibDialog::ReceiveNotification(void *ioData) noexcept // local message
{
	if( (ioData == NULL) || (mController == NULL) )
		return;

	OmcTaskData *taskData = (OmcTaskData *)ioData;

	switch(taskData->messageID)
	{
		case kOmcTaskFinished:
		{
			if( taskData->dataType == kOmcDataTypeBoolean )
			{
				//bool wasSynchronous = taskData->data.test;
			}

			CFObj<CFDictionaryRef> controlValues( ReadControlValuesFromPlist(GetDialogUUID()) );

            @try
            {
                if(controlValues != NULL)
                {
                    [(__bridge OMCNibWindowController*)mController setControlValues:(CFDictionaryRef)controlValues];
                }
            }
            @catch (NSException *localException)
            {
                NSLog(@"OMCNibDialog::ReceiveNotification received exception: %@", localException);
            }
		}
		break;

		case kOmcTaskProgress:
			;//we don't care about the subcommand progress messages here
		break;
		
		default:
		break;
	}
}

CFStringRef
OMCNibDialog::CreateControlValue(SInt32 inSpecialWordID, CFStringRef inControlString, UInt16 escSpecialCharsMode, bool isEnvStyle) noexcept
{
	CFObj<CFTypeRef> oneValue;
	CFObj<CFStringRef> partIDStr(CFSTR("0"), kCFObjRetain);
	CFObj<CFStringRef> controlID;

	TRACE_CFSTR(CFSTR("OMCNibDialog::CreateControlValue"));

	if((mControlValues == nullptr) || (CFDictionaryGetCount(mControlValues) == 0))
		return nullptr;

	if( inSpecialWordID == NIB_DLG_CONTROL_VALUE )
	{
		controlID.Adopt( CreateControlIDFromString(inControlString, isEnvStyle), kCFObjDontRetain );
	}
	else if( (inSpecialWordID == NIB_TABLE_VALUE) || (inSpecialWordID == NIB_TABLE_ALL_ROWS) )
	{
		controlID.Adopt( CreateTableIDAndColumnFromString(inControlString, partIDStr, inSpecialWordID == NIB_TABLE_ALL_ROWS, isEnvStyle), kCFObjDontRetain );

		if( inSpecialWordID == NIB_TABLE_ALL_ROWS )
		{
			CFObj<CFStringRef> newControlID( CreateControlIDByAddingModifiers(controlID, kControlModifier_AllRows) );
			controlID.Swap(newControlID);
		}
	}
	else if( inSpecialWordID == NIB_WEB_VIEW_VALUE )
	{
		partIDStr.Adopt(CFSTR(""), kCFObjRetain);
		controlID.Adopt( CreateWebViewIDAndElementIDFromString(inControlString, partIDStr, isEnvStyle), kCFObjDontRetain );
	}

	DEBUG_CFSTR((CFStringRef)controlID);

	CFDictionaryRef customProperties = nullptr;

	const void *theItem = ::CFDictionaryGetValue(mControlValues, (CFStringRef)controlID);
	CFDictionaryRef columnIds = ACFType<CFDictionaryRef>::DynamicCast(theItem);
	if((columnIds != nullptr) && (partIDStr != nullptr))
	{
		theItem = ::CFDictionaryGetValue(columnIds, (const void *)(CFStringRef)partIDStr);
		oneValue.Adopt((CFTypeRef)theItem, kCFObjRetain);
		if((oneValue != nullptr) && (mControlCustomProperties != nullptr))
        {
            customProperties = ACFType<CFDictionaryRef>::DynamicCast(CFDictionaryGetValue(mControlCustomProperties, (CFStringRef)controlID));
        }
	}

	CFStringRef controlValue = CreateControlValueString(oneValue, customProperties, escSpecialCharsMode, isEnvStyle);

	TRACE_CSTR("\texiting CreateControlValue\n");

	return controlValue;
}

void
OMCNibDialog::AddEnvironmentVariablesForAllControls(CFMutableDictionaryRef ioEnvironList) noexcept
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
		CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
		CFDictionaryRef partsDict = ACFType<CFDictionaryRef>::DynamicCast( valueList[i] );
		if((controlID != nullptr) && (partsDict != nullptr))
		{
			CFDictionaryRef controlProperties = (CFDictionaryRef)CFDictionaryGetValue(mControlCustomProperties, controlID);
			CFIndex partsCount = CFDictionaryGetCount(partsDict);
			if(partsCount == 1)
			{
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
			else if(partsCount > 1)
			{
				std::vector<CFTypeRef> partIDs(partsCount);
				std::vector<CFTypeRef> partValues(partsCount);
				CFDictionaryGetKeysAndValues(partsDict, (const void **)partIDs.data(), (const void **)partValues.data());
				
				Boolean isWebView = CFDictionaryContainsKey(partsDict, CFSTR("@"));
				
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

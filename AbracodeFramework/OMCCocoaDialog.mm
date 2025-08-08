//
//  OMCCocoaDialog.mm
//  Abracode
//
//  Created by Tomasz Kukielka on 3/1/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import "OMCCocoaDialog.h"
#import "OMCDialogController.h"
#include "OnMyCommand.h"
#include "CommandRuntimeData.h"
#include "CMUtils.h"
#include "ACFType.h"
#include "OmcTaskNotification.h"
#include "NibDialogControl.h"

ARefCountedObj<OMCDialog> RunCocoaDialog(OnMyCommandCM *inPlugin, CommandRuntimeData *commandRuntimeData)
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
			OMCDialogController *myController = [[OMCDialogController alloc] initWithOmc:inPlugin
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
			NSLog(@"RunCocoaDialog received exception: %@", localException);
			outDialog.Adopt(nullptr);
		}
	} //@autoreleasepool

	return outDialog;
}

#pragma mark -

//proxy C++ class to comply with OMCDialog protocol in OMC


CFTypeRef
OMCCocoaDialog::CopyControlValue(CFStringRef inControlID, CFStringRef inControlPart, SelectionIterator *inSelIterator, CFDictionaryRef *outCustomProperties) noexcept
{
	if(outCustomProperties != NULL)
		*outCustomProperties = NULL;

	id outValue = NULL;

    @try
    {
        if(mController != NULL)
        {
            OMCDialogController *__weak controller = (__bridge OMCDialogController*)mController;
            outValue = [controller controlValueForID:(__bridge NSString *)inControlID
                                             forPart:(__bridge NSString *)inControlPart
                                        withIterator:inSelIterator
                                       outProperties:outCustomProperties];
        }
    }
    @catch (NSException *localException)
    {
        NSLog(@"OMCCocoaDialog::CopyControlValue received exception: %@", localException);
    }

    return (CFTypeRef)CFBridgingRetain(outValue);
}

// private helper
void
OMCCocoaDialog::StoreControlValue(CFStringRef controlID, CFTypeRef inValue, CFStringRef controlPart) noexcept
{
	CFObj<CFMutableDictionaryRef> columnIdAndValueDict;
	CFTypeRef columnValues = CFDictionaryGetValue(mNibControlValues, controlID);
	if(columnValues == NULL)
	{
		columnIdAndValueDict.Adopt( ::CFDictionaryCreateMutable(
					kCFAllocatorDefault,
					0,
					&kCFTypeDictionaryKeyCallBacks,
					&kCFTypeDictionaryValueCallBacks), kCFObjDontRetain );

		CFDictionarySetValue(mNibControlValues, controlID, (CFMutableDictionaryRef)columnIdAndValueDict);
	}
	else
	{
		columnIdAndValueDict.Adopt((CFMutableDictionaryRef)columnValues, kCFObjRetain);
	}

	CFDictionarySetValue(columnIdAndValueDict, (const void *)controlPart, (const void *)inValue);
}

void
OMCCocoaDialog::CopyAllControlValues(CFSetRef requestedNibControls, SelectionIterator *inSelIterator) noexcept
{
    //get values for all controls in the dialog
    //the code is generic to handle tables
    //regular controls do not have columns and the use 0 for column number to store their values
    //column index 0 is a meta value for table and means: get array of all column values
    //this way a regular method of querying controls works with table too: produces a selected row strings
    if(mNibControlValues == nullptr)
        mNibControlValues.Adopt(CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                            0,
                                                            &kCFTypeDictionaryKeyCallBacks,
                                                            &kCFTypeDictionaryValueCallBacks),
                                                            kCFObjDontRetain);

    if(mNibControlCustomProperties == nullptr)
        mNibControlCustomProperties.Adopt(CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                                        0,
                                                                        &kCFTypeDictionaryKeyCallBacks,
                                                                        &kCFTypeDictionaryValueCallBacks),
                                                                    kCFObjDontRetain);//values will be CFStringRefs

    @try
    {
        if(mController != NULL)
        {
            [(__bridge OMCDialogController*)mController
                         allControlValues:(__bridge NSMutableDictionary *)mNibControlValues.Get()
                            andProperties:(__bridge NSMutableDictionary *)mNibControlCustomProperties.Get()
                             withIterator:inSelIterator];
        }
    }
    @catch (NSException *localException)
    {
        NSLog(@"OMCCocoaDialog::CopyAllControlValues received exception: %@", localException);
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
                StoreControlValue(controlID, oneValue, columnIndexStr);
            
                //custom escaping, prefix, suffix or separator
                if(customProperties != nullptr)
                {
                    ::CFDictionarySetValue( mNibControlCustomProperties,
                                            (const void *)controlID,
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
OMCCocoaDialog::ReceivePortMessage( SInt32 msgid, CFDataRef inData )
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
            [(__bridge OMCDialogController*)mController setControlValues:plistDict];
            
        }
    }
    @catch (NSException *localException)
    {
        NSLog(@"OMCCocoaDialog::ReceivePortMessage received exception: %@", localException);
    }

	return NULL;
}


void
OMCCocoaDialog::ReceiveNotification(void *ioData)//local message
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
                    [(__bridge OMCDialogController*)mController setControlValues:(CFDictionaryRef)controlValues];
                }
            }
            @catch (NSException *localException)
            {
                NSLog(@"OMCCocoaDialog::ReceiveNotification received exception: %@", localException);
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

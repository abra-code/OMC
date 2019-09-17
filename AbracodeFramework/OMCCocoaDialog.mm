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
#include "CMUtils.h"
#include "ACFType.h"
#include "OmcTaskNotification.h"

Boolean RunCocoaDialog(OnMyCommandCM *inPlugin);

Boolean RunCocoaDialog(OnMyCommandCM *inPlugin)
{
	if(inPlugin == NULL)
		return false;

	CommandDescription &currCommand = inPlugin->GetCurrentCommand();

	Boolean outResult = false;
	@autoreleasepool
	{
		@try
		{
			OMCDialogController *myController = [[OMCDialogController alloc] initWithOmc: inPlugin];
			if(myController != NULL)
			{
				[myController autorelease];
				outResult = true;

				assert(currCommand.currState != NULL);
				OMCCocoaDialog * omcDialog = [myController getOMCDialog];
				currCommand.currState->dialogGUID.Adopt(omcDialog->GetDialogUniqueID(), kCFObjRetain);

				[myController run];
				if( [myController isModal] )
				{
					if( [myController isOkeyed] )
					{
						if(omcDialog != NULL)
						{
							inPlugin->GetDialogControlValues( currCommand, *omcDialog, NULL /*sel iterator*/ );
							outResult = true;
						}
					}
					else
					{
						outResult = false;
					}
				}
			}
		}
		@catch (NSException *localException)
		{
			NSLog(@"RunCocoaDialog received exception: %@", localException);
			outResult = false;
		}
	} //@autoreleasepool

	return outResult;
}

#pragma mark -

//proxy C++ class to comply with OMCDialog protocol in OMC


CFTypeRef
OMCCocoaDialog::CopyControlValue(CFStringRef inControlID, SInt32 inControlPart, SelectionIterator *inSelIterator, CFDictionaryRef *outCustomProperties) noexcept
{
	if(outCustomProperties != NULL)
		*outCustomProperties = NULL;

	id outValue = NULL;
    @autoreleasepool
	{
		@try
		{
			if(mController != NULL)
			{
				outValue = [mController controlValueForID:(NSString *)inControlID forPart:(NSInteger)inControlPart withIterator:inSelIterator outProperties:outCustomProperties];
				[outValue retain];
			}
		}
		@catch (NSException *localException)
		{
			NSLog(@"OMCCocoaDialog::CopyControlValue received exception: %@", localException);
		}
	} //@autoreleasepool

	return (CFTypeRef)outValue;
}

void
OMCCocoaDialog::CopyAllControlValues(CFMutableDictionaryRef ioControlValues, CFMutableDictionaryRef ioCustomProperties, SelectionIterator *inSelIterator) noexcept
{
    @autoreleasepool
	{
		@try
		{
			if(mController != NULL)
			{
				[mController allControlValues:(NSMutableDictionary *)ioControlValues andProperties:(NSMutableDictionary *)ioCustomProperties withIterator:inSelIterator];
			}
		}
		@catch (NSException *localException)
		{
			NSLog(@"OMCCocoaDialog::CopyAllControlValues received exception: %@", localException);
		}
	} //@autoreleasepool
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

    @autoreleasepool
	{
		@try
		{
			if(plistDict != NULL)
				[mController setControlValues:plistDict];
		}
		@catch (NSException *localException)
		{
			NSLog(@"OMCCocoaDialog::ReceivePortMessage received exception: %@", localException);
		}
	} //@autoreleasepool

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

			CFObj<CFDictionaryRef> controlValues( ReadControlValuesFromPlist(GetDialogUniqueID()) );

			@autoreleasepool
			{
				@try
				{
					if(controlValues != NULL)
						[mController setControlValues:(CFDictionaryRef)controlValues];
				
				}
				@catch (NSException *localException)
				{
					NSLog(@"OMCCocoaDialog::ReceiveNotification received exception: %@", localException);
				}
			} //@autoreleasepool
		}
		break;

		case kOmcTaskProgress:
			;//we don't care about the subcommand progress messages here
		break;
		
		default:
		break;
	}
}

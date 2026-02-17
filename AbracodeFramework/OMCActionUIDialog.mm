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

CFTypeRef
OMCActionUIDialog::CopyControlValue(CFStringRef inControlID, CFStringRef inControlPart, SelectionIterator *inSelIterator, CFDictionaryRef *outCustomProperties) noexcept
{
	return nullptr;
}

void
OMCActionUIDialog::CopyAllControlValues(CFSetRef requestedNibControls, SelectionIterator *inSelIterator) noexcept
{
}

CFStringRef
OMCActionUIDialog::CreateControlValue(SInt32 inSpecialWordID, CFStringRef inControlString, UInt16 escSpecialCharsMode, bool isEnvStyle) noexcept
{
	return nullptr;
}

void
OMCActionUIDialog::AddEnvironmentVariablesForAllControls(CFMutableDictionaryRef ioEnvironList) noexcept
{
}

//
//  OMCInputDialog.m
//  Abracode
//
//  Created by Tomasz Kukielka on 8/25/09.
//  Copyright 2009-2010 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "OMCInputDialog.h"
#include "OnMyCommand.h"
#include "OMCInputDialogController.h"

//returns true if OKeyed and outStringRef is retained so caller responsible for releasing it
Boolean RunCocoaInputDialog(OnMyCommandCM *inPlugin, CFStringRef &outStringRef)
{
	outStringRef = NULL;
	if(inPlugin == NULL)
		return false;

	CommandDescription &currCommand = inPlugin->GetCurrentCommand();
	UInt16 dialogType = currCommand.inputDialogType;

	CFBundleRef localizationBundle = NULL;
	if(currCommand.localizationTableName != NULL)//client wants to be localized
	{
		localizationBundle = inPlugin->GetCurrentCommandExternBundle();
		if(localizationBundle == NULL)
			localizationBundle = CFBundleGetMainBundle();
	}

	Boolean isOkeyed = false;

	@autoreleasepool
	{
		@try
		{
			NSString * dialogNibName = NULL;
			switch(dialogType)
			{
				case kInputClearText:
				default:
					dialogNibName = @"input_clear";
				break;

				case kInputPasswordText:
					dialogNibName = @"input_password";
				break;
				
				case kInputPopupMenu:
					dialogNibName = @"input_popup";
				break;

				case kInputComboBox:
					dialogNibName = @"input_combo";
				break;
			}
			
			OMCInputDialogController *theController = [[OMCInputDialogController alloc] initWithWindowNibName:dialogNibName];

			if(currCommand.name != NULL)
			{
				CFObj<CFStringRef> dynamicCommandName( inPlugin->CreateDynamicCommandName(currCommand, currCommand.localizationTableName, localizationBundle) );
				[theController setWindowTitle:(NSString *)(CFStringRef)dynamicCommandName];
			}

			NSString *inputDialogOK = (NSString *)currCommand.inputDialogOK;
			if(inputDialogOK != NULL)
			{
				if(currCommand.localizationTableName != NULL)
				{
					inputDialogOK = (NSString *)::CFCopyLocalizedStringFromTableInBundle( currCommand.inputDialogOK, currCommand.localizationTableName, localizationBundle, "");
					[inputDialogOK autorelease];
				}
				[theController setOKButtonTitle:inputDialogOK];
			}

			NSString *inputDialogCancel = (NSString *)currCommand.inputDialogCancel;
			if(inputDialogCancel != NULL)
			{
				if(currCommand.localizationTableName != NULL)
				{
					inputDialogCancel = (NSString *)::CFCopyLocalizedStringFromTableInBundle( currCommand.inputDialogCancel, currCommand.localizationTableName, localizationBundle, "");
					[inputDialogCancel autorelease];
				}
				[theController setCancelButtonTitle:inputDialogCancel];
			}

			NSString* inputDialogMessage = (NSString*)currCommand.inputDialogMessage;
			if(inputDialogMessage!= NULL)
			{
				if(currCommand.localizationTableName != NULL)
				{
					inputDialogMessage = (NSString*)::CFCopyLocalizedStringFromTableInBundle( currCommand.inputDialogMessage, currCommand.localizationTableName, localizationBundle, "");
					[inputDialogMessage autorelease];
				}
				[theController setMessageText:inputDialogMessage];
			}

			NSArray *inputDialogMenuItems = (NSArray*)currCommand.inputDialogMenuItems;
			if( (dialogType == kInputPopupMenu) || (dialogType == kInputComboBox) )
			{
				if( (inputDialogMenuItems != NULL) && (currCommand.localizationTableName != NULL) )
				{
					NSUInteger itemCount = [inputDialogMenuItems count];
					NSMutableArray *localizedArray = [NSMutableArray arrayWithCapacity:itemCount];
					Class stringClass = [NSString class];
					for(NSUInteger i = 0; i < itemCount; i++)
					{
						id oneItem = [inputDialogMenuItems objectAtIndex:i];
						if( [oneItem isKindOfClass:stringClass] )
						{
							NSString *oneString = (NSString *)::CFCopyLocalizedStringFromTableInBundle( (CFStringRef)oneItem, currCommand.localizationTableName, localizationBundle, "");
							[localizedArray addObject:oneString];
							[oneString release];
						}
					}
					inputDialogMenuItems = localizedArray;
				}
				[theController setMenuItems:inputDialogMenuItems];
			}

			CFObj<CFStringRef> inputDialogDefault( inPlugin->CreateCombinedStringWithObjects(currCommand.inputDialogDefault, currCommand.localizationTableName, localizationBundle) );
			if(inputDialogDefault != NULL)
				[theController setDefaultChoiceString:(NSString *)(CFStringRef)inputDialogDefault];

			isOkeyed = (Boolean) [theController runModalDialog];
			if(isOkeyed)
			{
				NSString *choiceString = [theController getChoiceString];
				if(choiceString != NULL)
				{
					[choiceString retain];
					outStringRef = (CFStringRef)choiceString;
				}
			}

			[theController close];
			[theController release];

		}
		@catch (NSException *localException)
		{
			NSLog(@"RunCocoaInputDialog received exception: %@", localException);
			isOkeyed = false;
		}
	} //@autoreleasepool

	return isOkeyed;
}

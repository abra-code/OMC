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

// For legacy reasons we start with CFBundleRef so we use all CoreFoundations input objects and return NSString *
static inline
NSString *
LocalizedString(CFStringRef inStr, CFBundleRef localizationBundle, CFStringRef localizationTableName)
{
    NSString *__strong nsLocalizedStr = nil;
    if(inStr != NULL)
    {
        CFRetain(inStr);
        nsLocalizedStr = CFBridgingRelease(inStr);
        if(localizationTableName != NULL)
        {
            nsLocalizedStr = (NSString *)CFBridgingRelease(::CFCopyLocalizedStringFromTableInBundle(inStr, localizationTableName, localizationBundle, ""));
        }
    }
    return nsLocalizedStr;
}

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
            [theController setWindowTitle:(__bridge NSString *)(CFStringRef)dynamicCommandName];
        }

        NSString *inputDialogOK = LocalizedString(currCommand.inputDialogOK, localizationBundle, currCommand.localizationTableName);
        [theController setOKButtonTitle:inputDialogOK];
        
        NSString *inputDialogCancel = LocalizedString(currCommand.inputDialogCancel, localizationBundle, currCommand.localizationTableName);
        [theController setCancelButtonTitle:inputDialogCancel];

        NSString* inputDialogMessage = LocalizedString(currCommand.inputDialogMessage, localizationBundle, currCommand.localizationTableName);
        [theController setMessageText:inputDialogMessage];
        
        CFRetain(currCommand.inputDialogMenuItems);
        NSArray *__strong inputDialogMenuItems = CFBridgingRelease(currCommand.inputDialogMenuItems);
        
        if( (dialogType == kInputPopupMenu) || (dialogType == kInputComboBox) )
        {
            if( (inputDialogMenuItems != NULL) && (currCommand.localizationTableName != NULL) )
            {
                NSMutableArray *localizedArray = [NSMutableArray arrayWithCapacity:inputDialogMenuItems.count];
                Class stringClass = [NSString class];
                for(id oneItem in inputDialogMenuItems)
                {
                    if( [oneItem isKindOfClass:stringClass] )
                    {
                        NSString* localizedString = LocalizedString((__bridge CFStringRef)oneItem, localizationBundle, currCommand.localizationTableName);
                        // non-null oneItem guarantees non-null result oneString
                        [localizedArray addObject:localizedString];
                    }
                }
                
                inputDialogMenuItems = localizedArray;
            }
            [theController setMenuItems:inputDialogMenuItems];
        }

        CFObj<CFStringRef> inputDialogDefault( inPlugin->CreateCombinedStringWithObjects(currCommand.inputDialogDefault, currCommand.localizationTableName, localizationBundle) );
        if(inputDialogDefault != NULL)
            [theController setDefaultChoiceString:(__bridge NSString *)(CFStringRef)inputDialogDefault];

        isOkeyed = (Boolean) [theController runModalDialog];
        if(isOkeyed)
        {
            NSString *choiceString = [theController getChoiceString];
            outStringRef = (CFStringRef)CFBridgingRetain(choiceString);
        }

        [theController close];
    }
    @catch (NSException *localException)
    {
        NSLog(@"RunCocoaInputDialog received exception: %@", localException);
        isOkeyed = false;
    }

	return isOkeyed;
}

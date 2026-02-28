//
//  OMCFilePanels.mm
//  Abracode
//
//  Created by Tomasz Kukielka on 5/25/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "OMCFilePanels.h"
#include "CFObj.h"
#include "ACFType.h"

CFURLRef
CreateCFURLFromSaveAsDialog( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, UInt32 inAdditonalFlags )
{
	NSURL *outURL = nil;

	@try
	{
		NSSavePanel *savePanel	= [NSSavePanel savePanel];
		if(savePanel == nil)
			return nullptr;

		if(inClientName == nullptr)
			inClientName = CFSTR("OMC");

		if(inMessage == nullptr)
			inMessage = CFSTR("");

        savePanel.title = (__bridge NSString *)inClientName;
        savePanel.message = (__bridge NSString *)inMessage;
        if(inIdentifier != nullptr)
            savePanel.identifier = (__bridge NSString *)inIdentifier;
        if(inPrompt != nullptr)
            savePanel.prompt = (__bridge NSString *)inPrompt;
        
        savePanel.showsHiddenFiles = ((inAdditonalFlags & kOMCFilePanelAllowInvisibleItems) != 0);
        savePanel.treatsFilePackagesAsDirectories = YES;
        savePanel.canCreateDirectories = YES;

        if(inDefaultDirPath != nullptr)
        {
            savePanel.directoryURL = [NSURL fileURLWithPath:(__bridge NSString *)inDefaultDirPath];
        }
        
        if(inDefaultName != nullptr)
        {
            savePanel.nameFieldStringValue = (__bridge NSString *)inDefaultName;
        }
        
        NSModalResponse response = [savePanel runModal];
        if(response == NSModalResponseOK)
		{
			outURL = [savePanel URL];
		}
	}
	@catch (NSException *localException)
	{
		NSLog(@"CreateCFURLFromSaveAsDialog received exception: %@", localException);
	}
	
    return (CFURLRef)CFBridgingRetain(outURL);
}

CFArrayRef
CreateCFURLsFromOpenDialog( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, UInt32 inAdditonalFlags)
{
#pragma unused(inDefaultName) //NSOpenPanel API no longer supports default name
	NSArray *outURLs = nil;
	
	@try
	{
		NSOpenPanel *openPanel	= [NSOpenPanel openPanel];
		if(openPanel == NULL)
			return NULL;
				
		if(inClientName == NULL)
			inClientName = CFSTR("OMC");

		if(inMessage == NULL)
			inMessage = CFSTR("");

        openPanel.title = (__bridge NSString *)inClientName;
        openPanel.message = (__bridge NSString *)inMessage;
        if(inIdentifier != nullptr)
            openPanel.identifier = (__bridge NSString *)inIdentifier;
        if(inPrompt != nullptr)
            openPanel.prompt = (__bridge NSString *)inPrompt;
		
		openPanel.canChooseFiles = ((inAdditonalFlags & kOMCFilePanelCanChooseFiles) != 0);
		openPanel.canChooseDirectories = ((inAdditonalFlags & kOMCFilePanelCanChooseDirectories) != 0);
        openPanel.allowsMultipleSelection = ((inAdditonalFlags & kOMCFilePanelAllowMultipleItems) != 0);
        openPanel.showsHiddenFiles = ((inAdditonalFlags & kOMCFilePanelAllowInvisibleItems) != 0);
        openPanel.treatsFilePackagesAsDirectories = YES;
        openPanel.canCreateDirectories = YES;

        if(inDefaultDirPath != nullptr)
        {
            openPanel.directoryURL = [NSURL fileURLWithPath:(__bridge NSString *)inDefaultDirPath];
        }

        NSModalResponse response = [openPanel runModal];
        if(response == NSModalResponseOK)
		{
			outURLs = [openPanel URLs];
		}
		
	}
	@catch (NSException *localException)
	{
		NSLog(@"CreateCFURLsFromOpenDialog received exception: %@", localException);
	}
	
    return (CFArrayRef)CFBridgingRetain(outURLs);
}

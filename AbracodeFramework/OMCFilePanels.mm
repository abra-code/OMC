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
CreateCFURLFromSaveAsDialog( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, UInt32 inAdditonalFlags )
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

		[savePanel setTreatsFilePackagesAsDirectories:YES];
        [savePanel setTitle:(__bridge NSString *)inClientName];
        [savePanel setMessage:(__bridge NSString *)inMessage];

		//setShowsHiddenFiles: is undocumented so we need to check if it exists
		if( ((inAdditonalFlags & kOMCFilePanelAllowInvisibleItems) != 0) &&
		   [savePanel respondsToSelector:@selector(setShowsHiddenFiles:)] )
		{
			[savePanel setShowsHiddenFiles:YES];
		}
		
        if(inDefaultDirPath != nullptr)
        {
            savePanel.directoryURL = [NSURL fileURLWithPath:(__bridge NSString *)inDefaultDirPath];
        }
        
        if(inDefaultName != nullptr)
        {
            CFRetain(inDefaultName);
            savePanel.nameFieldStringValue = (NSString *)CFBridgingRelease(inDefaultName);
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

CFURLRef
CreateCFURLFromOpenDialog( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, UInt32 inAdditonalFlags )
{
	CFURLRef outURL = NULL;
	CFObj<CFArrayRef> arrayRef( CreateCFURLsFromOpenDialog( inClientName, inMessage, inDefaultName, inDefaultDirPath, inAdditonalFlags) );
	if(arrayRef != NULL)
	{
		CFIndex fileCount = ::CFArrayGetCount(arrayRef);
		if(fileCount > 0)
		{
			CFTypeRef oneItem = ::CFArrayGetValueAtIndex(arrayRef, 0);
			outURL = ACFType<CFURLRef>::DynamicCast(oneItem);
			if(outURL != NULL)
				::CFRetain(outURL);
		}
	}
	return outURL;
}

CFArrayRef
CreateCFURLsFromOpenDialog( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, UInt32 inAdditonalFlags)
{
#pragma unused(inDefaultName) //NSOpenPanel API no longer supports default name
	NSArray *outURLs = nil;
	
	@try
	{
		NSOpenPanel *openPanel	= [NSOpenPanel openPanel];
		if(openPanel == NULL)
			return NULL;
		
		[openPanel setTreatsFilePackagesAsDirectories:YES];
		
		if(inClientName == NULL)
			inClientName = CFSTR("OMC");

		if(inMessage == NULL)
			inMessage = CFSTR("");

        [openPanel setTitle:(__bridge NSString *)inClientName];	
        [openPanel setMessage:(__bridge NSString *)inMessage];
		
		[openPanel setCanChooseFiles:((inAdditonalFlags & kOMCFilePanelCanChooseFiles) != 0)];
		[openPanel setCanChooseDirectories:((inAdditonalFlags & kOMCFilePanelCanChooseDirectories) != 0)];
		[openPanel setAllowsMultipleSelection:((inAdditonalFlags & kOMCFilePanelAllowMultipleItems) != 0)];
		
		//setShowsHiddenFiles: is undocumented so we need to check if it exists
		if( ((inAdditonalFlags & kOMCFilePanelAllowInvisibleItems) != 0) &&
			[openPanel respondsToSelector:@selector(setShowsHiddenFiles:)] )
		{
			[openPanel setShowsHiddenFiles:YES];
		}

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

//
//  OMCActionUIWindowController.mm
//  Abracode
//
//  Created by Tomasz Kukielka on 2/17/26.
//  Copyright 2026 Abracode. All rights reserved.
//

#import "OMCActionUIWindowController.h"
#import "OMCActionUIDialog.h"
#import "OMCControlAccessor.h"
#include "OnMyCommand.h"
#include "CommandRuntimeData.h"
#include "ACFDict.h"
#include "OMCStrings.h"

@import ActionUIObjCAdapter;

@implementation OMCActionUIWindowController

- (id)initWithOmc:(OnMyCommandCM *)inOmc commandRuntimeData:(CommandRuntimeData *)inCommandRuntimeData
{
   self = [super initWithOmc:inOmc commandRuntimeData:inCommandRuntimeData];
	if(self == nil)
		return nil;
    
    mOMCDialogProxy.Adopt( new OMCActionUIDialog() );
    mOMCDialogProxy->SetControlAccessor((__bridge void *)self);
    self->mCommandRuntimeData->SetAssociatedDialogUUID(mOMCDialogProxy->GetDialogUUID());

	CommandDescription &currCommand = self->mPlugin->GetCurrentCommand();

	ACFDict params( currCommand.actionUIWindow );
    CFObj<CFStringRef> jsonName;
	params.CopyValue( CFSTR("JSON_NAME"), jsonName );

	if(jsonName == nullptr)
		return self;//no json name, no dialog
    
    NSString *__strong dialogJsonName = (NSString *)CFBridgingRelease(jsonName.Detach());

    CFObj<CFStringRef> initSubcommandID;
	params.CopyValue( CFSTR("INIT_SUBCOMMAND_ID"), initSubcommandID );
    self.dialogInitSubcommandID = (NSString *)CFBridgingRelease(initSubcommandID.Detach());
    
    CFObj<CFStringRef> endOKSubcommandID;
	params.CopyValue( CFSTR("END_OK_SUBCOMMAND_ID"), endOKSubcommandID );
    self.endOKSubcommandID = (NSString *)CFBridgingRelease(endOKSubcommandID.Detach());

    CFObj<CFStringRef> endCancelSubcommandID;
	params.CopyValue( CFSTR("END_CANCEL_SUBCOMMAND_ID"), endCancelSubcommandID );
    self.endCancelSubcommandID = (NSString *)CFBridgingRelease(endCancelSubcommandID.Detach());

	Boolean isBlocking = true;//default is modal
	params.GetValue( CFSTR("IS_BLOCKING"), isBlocking );
	mIsModal = isBlocking;

	//now we need to find out where our json is

	NSURL *jsonURL = NULL;

	if(mExternBundleRef != NULL)
	{
		CFObj<CFURLRef> bundleURL( CFBundleCopyBundleURL( mExternBundleRef ) );
		if(bundleURL != NULL)
		{
			CFObj<CFStringRef> bundlePath = CreatePathFromCFURL(bundleURL, kEscapeNone);
			if(bundlePath != nullptr)
			{
				NSString *path = (__bridge NSString *)bundlePath.Get();
                
                NSBundle *externBundle = [NSBundle bundleWithPath:path];
                NSString *jsonPath = [externBundle pathForResource:dialogJsonName ofType:@"json"];
                if(jsonPath != nil)
                {
                    jsonURL = [NSURL fileURLWithPath:jsonPath];
                }
			}
		}
	}

	if(jsonURL == NULL)
	{
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *jsonPath = [mainBundle pathForResource:dialogJsonName ofType:@"json"];
        if(jsonPath != nil)
        {
            jsonURL = [NSURL fileURLWithPath:jsonPath];
        }
	}

	if(jsonURL == NULL)
	{
		CFBundleRef frameworkBundleRef = mPlugin->GetBundleRef();
		if(frameworkBundleRef != NULL)
		{
			CFObj<CFURLRef> bundleURL( CFBundleCopyBundleURL( frameworkBundleRef ) );
			if(bundleURL != NULL)
			{
				CFObj<CFStringRef> bundlePath = CreatePathFromCFURL(bundleURL, kEscapeNone);
				if(bundlePath != nullptr)
				{
					NSString *path = (__bridge NSString *)bundlePath.Get();
                    NSBundle *omcBundle = [NSBundle bundleWithPath:path];
					if(omcBundle != nil)
					{
                        NSString *jsonPath = [omcBundle pathForResource:dialogJsonName ofType:@"json"];
						if(jsonPath != nil)
						{
							jsonURL = [NSURL fileURLWithPath:jsonPath];
						}
					}
				}
			}
		}
	}

#if DEBUG
	NSLog(@"[OMCActionUIWindowController initWithOmc], jsonURL=%@", jsonURL);
#endif

    if(jsonURL == nil)
    {
        NSLog(@"Cannot find ActionUI JSON file: %@", dialogJsonName);
        return self;
    }

    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    self.hostingController = [ActionUIObjC loadHostingControllerWithURL:jsonURL
                                                                 windowUUID:windowUUID
                                                              isContentView:YES];
    if (self.hostingController == nil)
    {
        NSLog(@"Unable to create a view from ActionUI JSON file: %@", dialogJsonName);
        return self;
    }
    
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 320)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    
    [window setReleasedWhenClosed:NO];
    [window setContentView:self.hostingController.view];
    
    // Autosave name: if a saved frame exists it overrides the fitting size above.
    NSString *autosaveName = [NSString stringWithFormat:@"OMC.%@", dialogJsonName];
    [window setFrameAutosaveName:autosaveName];

    BOOL frameRestored = [window setFrameUsingName:autosaveName];
    if(!frameRestored)
    {
        // First launch — no saved frame yet, use fitting size and center
        // view.fitting size contains ideal size for the content view
       NSSize fittingSize = self.hostingController.view.fittingSize;
        if(fittingSize.width > 10 && fittingSize.height > 10)
            [window setContentSize:fittingSize];
        [window center];
    }

    [window setDelegate:self];
    self.window = window;
    
    // Associated file (same as nib controller)
    OneObjProperties *associatedObj = mCommandRuntimeData->GetAssociatedObject();
    if(associatedObj != nullptr)
    {
        CFURLRef fileURL = associatedObj->url.Get();
        if(fileURL != NULL)
        {
            NSURL *associatedFileURL = (__bridge NSURL *)fileURL;
            window.representedURL = associatedFileURL;
            [window setTitleWithRepresentedFilename:associatedFileURL.path];
            [NSDocumentController.sharedDocumentController noteNewRecentDocumentURL:associatedFileURL];
        }
    }

    // TODO: do not set the handler for each window. this needs to be done once only
    // Global default handler — routes by windowUUID to the right controller instance
    [ActionUIObjC setDefaultActionHandler:^(NSString *actionID, NSString *targetWindowUUID, NSInteger viewID, NSInteger viewPartID, id context) {
        OMCWindowController *controller = [OMCWindowController findControllerByUUID:targetWindowUUID];
        if (controller != nil)
        {
	        [controller dispatchCommand:actionID withContext:(__bridge CFTypeRef)context];
	    }
	    else
	    {
            NSLog(@"Window not found for provided UUID: %@ when handling actionID: %@ from viewID: %ld", targetWindowUUID, actionID, static_cast<long>(viewID));
	    }
    }];

    return self;
}


- (void)dealloc
{
    OMCActionUIDialog *actionUIDialog = (OMCActionUIDialog *)mOMCDialogProxy.Get();
    if(actionUIDialog != nullptr)
        actionUIDialog->SetControlAccessor(nil);

    [self.window setDelegate:nil];
    // hostingController released by property, taking SwiftUI view hierarchy with it
}

#pragma mark - OMCControlAccessor protocol

- (void)setControlStringValue:(NSString *)inValue forControlID:(NSString *)inControlID
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if(windowUUID == nil || inValue == nil || inControlID == nil)
        return;

    NSInteger viewID = [inControlID integerValue];
    [ActionUIObjC setElementValueFromStringWithWindowUUID:windowUUID viewID:viewID value:inValue viewPartID:0];
}

- (void)allControlValues:(NSMutableDictionary *)ioControlValues andProperties:(NSMutableDictionary *)ioCustomProperties withIterator:(SelectionIterator *)inSelIterator
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if(windowUUID == nil)
        return;

    NSDictionary *elementInfo = [ActionUIObjC getElementInfoWithWindowUUID:windowUUID];
    if(elementInfo == nil || elementInfo.count == 0)
        return;

    for(NSNumber *viewIDNumber in elementInfo)
    {
        NSInteger viewID = [viewIDNumber integerValue];
        NSString *value = [ActionUIObjC getElementValueAsStringWithWindowUUID:windowUUID viewID:viewID viewPartID:0];
        if(value != nil)
        {
            NSString *controlID = [viewIDNumber stringValue];
            NSMutableDictionary *partsDict = ioControlValues[controlID];
            if(partsDict == nil)
            {
                partsDict = [NSMutableDictionary dictionaryWithObject:value forKey:@"0"];
                ioControlValues[controlID] = partsDict;
            }
            else
            {
                partsDict[@"0"] = value;
            }
        }
    }
}

- (id)controlValueForID:(NSString *)inControlID forPart:(NSString *)inControlPart withIterator:(SelectionIterator *)inSelIterator outProperties:(CFDictionaryRef *)outCustomProperties
{
    if(outCustomProperties != NULL)
        *outCustomProperties = NULL;

    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if(windowUUID == nil)
        return nil;

    NSInteger viewID = [inControlID integerValue];
    NSInteger viewPartID = (inControlPart != nil) ? [inControlPart integerValue] : 0;

    NSString *value = [ActionUIObjC getElementValueAsStringWithWindowUUID:windowUUID viewID:viewID viewPartID:viewPartID];
    return value;
}

@end

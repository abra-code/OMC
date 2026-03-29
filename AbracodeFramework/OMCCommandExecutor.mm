//
//  OMCCommandExecutor.m
//  Abracode
//
//  Created by Tomasz Kukielka on 4/6/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import "OMCCommandExecutor.h"
#import "OMCWindowController.h"
#include "OMC.h"
#include "OMCFilePanels.h"
#include "ACFPropertyList.h"
#import "OMCObserverDelegate.h"

static NSMutableDictionary *sCachedPlists = NULL;

void OMCDelegateObserverCallback(OmcObserverMessage inMessage, CFIndex inTaskID, CFTypeRef inResult, void *userData)
{
    if (userData == NULL)
    {
        return;
    }
    
    id __weak objcObject = (__bridge id)userData;
    if ([objcObject conformsToProtocol:@protocol(OMCObserverDelegate)])
    {
        id<OMCObserverDelegate> __strong observerDelegate = (id<OMCObserverDelegate>)objcObject;
        [observerDelegate receiveObserverMessage:inMessage forTaskId:inTaskID withData:inResult];
    }
}

static inline
bool IsFileOrFolderActivation(UInt32 activationType)
{
    return ((activationType == kActiveFile) ||
            (activationType == kActiveFolder) ||
            (activationType == kActiveFileOrFolder) ||
            (activationType == kActiveFinderWindow) ||
            (activationType == kActiveFolderExcludeFinderWindow) ||
            (activationType == kActiveFileOrFolderExcludeFinderWindow));
}

@interface OMCCommandExecutor()
+ (CFPropertyListRef)cachedPlistForCommandFile:(NSString *)inFileName;
+ (CFPropertyListRef)cachedPlistForURL:(NSURL *)inURL;
@end


@implementation OMCCommandExecutor

//when useNavDialog = TRUE, missing file context is obtained from nav dialog
//otherwise when the file context is missing the command is not executed
//if USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT is false, the command always executes and no nav dialog is shown
+ (OSStatus)runCommand:(NSString *)inCommandNameOrId forCommandFile:(NSString *)inFileName withContext:(id)inContext useNavDialog:(BOOL)clientAllowsNavDialog allowKeyWindowSubcommand:(BOOL)allowKeyWindowSubcommand delegate:(id)delegate
{
	OSStatus error = userCanceledErr;//pessimistic scenario
	
    CFTypeRef commandRef = nil;
    NSString *ext = [inFileName pathExtension];
    if ([ext isEqualToString:@"omc"]) {
        commandRef = (__bridge CFURLRef)[NSURL fileURLWithPath:inFileName isDirectory:YES];
    }
    else
    {
        commandRef = [OMCCommandExecutor cachedPlistForCommandFile:inFileName];
    }
    
	OMCExecutorRef omcExec = OMCCreateExecutor( commandRef );
	if(omcExec != NULL)
	{
        OMCCommandRef commandRef = OMCFindCommand( omcExec, (__bridge CFStringRef)inCommandNameOrId );
		if( OMCIsValidCommandRef(commandRef) )
		{
            // If the key window is managed by an OMCWindowController, dispatch the command
            // as a dialog subcommand so it inherits the window's dialog context and control values.
            // Exception: commands with OPEN_OBJECT_DIALOG need to run independently to show the open panel.
            OMCWindowController *keyWindowController = allowKeyWindowSubcommand ? [OMCWindowController findControllerForKeyWindow] : nil;
            if (keyWindowController != nil)
            {
                CFDictionaryRef openDialogParams = NULL;
                OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_OpenObjectDialogParams, &openDialogParams);
                if (openDialogParams == NULL) // no open dialog — dispatch as window subcommand
                {
                    [keyWindowController dispatchCommand:inCommandNameOrId withContext:(__bridge CFTypeRef)inContext];
                    OMCReleaseExecutor(omcExec);
                    return noErr;
                }
            }

			error = noErr;

            // evaluate if we have a path object context for requested path OR file or folder activation
            bool hasFiles = false;
            if (inContext != NULL)
            {
                CFTypeID contextType = CFGetTypeID((__bridge CFTypeRef)inContext);
                hasFiles = ((contextType == CFArrayGetTypeID()) || (contextType == CFURLGetTypeID()));
            }
            
            bool requiresNavDialog = false;
            UInt32 activationType = kActiveAlways;
            CFArrayRef selectedFiles = NULL;
            
            if (!hasFiles) // no file context provided. consider carefully whether the command needs files and allows displaying nav dialog
            {
                // does the command description allows using nav dialogs for missing file context (default = true, must be explicitly disallowed)
                UInt32 executionOptions = 0;
                OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_ExecutionOptions, &executionOptions);
                if ((executionOptions & kExecutionOption_UseNavDialogForMissingFileContext) != 0)
                {
                    // do we have file/dir objects referenced in command or declared in environment variables?
                    UInt32 objectsInfo = kOmcCommandNoSpecialObjects;
                    OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_CommandObjects, &objectsInfo);
                    
                    // does the command activation require file/dir?
                    OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_ActivationType, &activationType);
                    requiresNavDialog = ((objectsInfo & kOmcCommandContainsFileObject) != 0) || IsFileOrFolderActivation(activationType);
                }
            }
            
			if (requiresNavDialog && clientAllowsNavDialog) // all good to go with nav dialog
			{
                NSBundle *appBundle = [NSBundle mainBundle];
                NSString *appName = [appBundle objectForInfoDictionaryKey:@"CFBundleName"];
                if(appName == NULL)
                    appName = @"OMCApplet";

                // Check if the command has OPEN_OBJECT_DIALOG customization
                CFDictionaryRef openDialogParams = NULL;
                OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_OpenObjectDialogParams, &openDialogParams);

                CFStringRef dialogMessage = NULL;
                CFArrayRef dialogDefaultName = NULL;
                CFArrayRef dialogDefaultLocation = NULL;
                CFStringRef dialogIdentifier = NULL;
                CFStringRef dialogPrompt = NULL;
                CFArrayRef dialogAllowedContentTypes = NULL;
                UInt32 dialogFlags = 0;

                if (openDialogParams != NULL)
                {
                    dialogFlags = CopyNavDialogParams(openDialogParams, &dialogMessage, &dialogDefaultName, &dialogDefaultLocation, &dialogIdentifier, &dialogPrompt, &dialogAllowedContentTypes);
                    dialogFlags &= ~kOMCFilePanelUseCachedPath; // not applicable to the startup open dialog
                }

                // Use first element of DEFAULT_LOCATION array as default directory path
                CFStringRef dialogDefaultDir = NULL;
                if (dialogDefaultLocation != NULL && CFArrayGetCount(dialogDefaultLocation) > 0)
                    dialogDefaultDir = (CFStringRef)CFArrayGetValueAtIndex(dialogDefaultLocation, 0);

                if (dialogMessage == NULL)
                {
                    dialogMessage = CFCopyLocalizedStringFromTable(CFSTR("Choose Objects To Process"), CFSTR("Localizable"), "");
                }

                // If OPEN_OBJECT_DIALOG didn't set ALLOW_MULTIPLE_ITEMS, default to allowing multiple
                if (openDialogParams == NULL)
                    dialogFlags |= kOMCFilePanelAllowMultipleItems;

                switch(activationType)
                {
                    case kActiveFile:
                    {
                        selectedFiles = CreateCFURLsFromOpenDialog( (__bridge CFStringRef)appName, dialogMessage, NULL, dialogDefaultDir, dialogIdentifier, dialogPrompt, dialogAllowedContentTypes, dialogFlags | kOMCFilePanelCanChooseFiles );
                    }
                    break;

                    case kActiveFolder:
                    case kActiveFinderWindow:
                    case kActiveFolderExcludeFinderWindow:
                    {
                        selectedFiles = CreateCFURLsFromOpenDialog( (__bridge CFStringRef)appName, dialogMessage, NULL, dialogDefaultDir, dialogIdentifier, dialogPrompt, dialogAllowedContentTypes, dialogFlags | kOMCFilePanelCanChooseDirectories );
                    }
                    break;

                    default:
                    {
                        selectedFiles = CreateCFURLsFromOpenDialog( (__bridge CFStringRef)appName, dialogMessage, NULL, dialogDefaultDir, dialogIdentifier, dialogPrompt, dialogAllowedContentTypes, dialogFlags | kOMCFilePanelCanChooseFiles | kOMCFilePanelCanChooseDirectories );
                    }
                    break;
                }

                if (dialogMessage != NULL)
                    CFRelease(dialogMessage);
                if (dialogDefaultName != NULL)
                    CFRelease(dialogDefaultName);
                if (dialogDefaultLocation != NULL)
                    CFRelease(dialogDefaultLocation);
                if (dialogIdentifier != NULL)
                    CFRelease(dialogIdentifier);
                if (dialogPrompt != NULL)
                    CFRelease(dialogPrompt);
                if (dialogAllowedContentTypes != NULL)
                    CFRelease(dialogAllowedContentTypes);
                error = (selectedFiles != NULL) ? noErr : userCanceledErr;
			}
            else if (requiresNavDialog)
            { // we don't have files, we need the nav dialog but command description explicitly disallows it
                error = userCanceledErr; // command will not execute if we don't specify files
            }

            if (error == noErr)
            {
                error = OMCExamineContext( omcExec, commandRef, (selectedFiles != NULL) ? selectedFiles : (__bridge CFTypeRef)inContext );
            }

			if (selectedFiles != NULL)
			{
                if (error == noErr)
                {
                    // add to open recent
                    NSArray<NSURL*> *__weak absoluteURLArray = (__bridge NSArray<NSURL*> *)selectedFiles;
                    for (NSURL *oneFileURL in absoluteURLArray)
                    {
                        [NSDocumentController.sharedDocumentController noteNewRecentDocumentURL:oneFileURL];
                    }
                }

                CFRelease(selectedFiles);
                selectedFiles = NULL;
			}

			if (error == noErr)
			{
                // Check if delegate wants to observe task execution
                if ((delegate != nil) && [delegate conformsToProtocol:@protocol(OMCObserverDelegate)])
                {
                    id<OMCObserverDelegate> observerDelegate = (id<OMCObserverDelegate>)delegate;
                    
                    // Create observer with the delegate as userData (stored weakly there)
                    OMCObserverRef observer = OMCCreateObserver(kOmcObserverAllMessages,
                                                                 OMCDelegateObserverCallback,
                                                                 (__bridge void *)observerDelegate);
                    if (observer != NULL)
                    {
                        [observerDelegate setObserver:observer]; // Delegate takes the ownership of the observer and retains it
                        OMCAddObserver(omcExec, observer);
                        OMCReleaseObserver(observer); // Release our local reference - delegate now owns it
                    }
                }

				error = OMCExecuteCommand( omcExec, commandRef );
				if(error != noErr)
				{
					NSLog(@"OMCRunCommand returned error = %d", (int)error);
				}
			}
		}
		
		OMCReleaseExecutor( omcExec ); // safe to release here. task lives on if execution is asynchronous
	}
		
	return error;
}


+ (CFPropertyListRef)cachedPlistForCommandFile:(NSString *)inFileName
{
	NSURL *commandURL = NULL;
	if( inFileName != NULL )
	{
		inFileName = [inFileName stringByExpandingTildeInPath];
		if( ![inFileName isAbsolutePath] )
		{
			NSBundle *appBundle = [NSBundle mainBundle];
			inFileName = [appBundle pathForResource:inFileName ofType:NULL];
		}
		
		if(inFileName != NULL)
			commandURL = [NSURL fileURLWithPath:inFileName];
	}
	
	return [OMCCommandExecutor cachedPlistForURL:commandURL];
}

+ (CFPropertyListRef)cachedPlistForURL:(NSURL *)inURL
{
	if(inURL == NULL)
		return NULL;

	NSURL *absURL = [inURL absoluteURL];
	if(absURL == NULL)
		return NULL;
	
	if(sCachedPlists != NULL)
	{
        CFPropertyListRef outPlist = (__bridge CFPropertyListRef)([sCachedPlists objectForKey:absURL]);
		if(outPlist != NULL)
			return outPlist;
	}


//not found, load it and cache

    CFPropertyListRef thePlist = CreatePropertyList((__bridge CFURLRef)absURL, kCFPropertyListImmutable);

	if(thePlist == NULL)
		return NULL;

	if(sCachedPlists == nil)
	{
		sCachedPlists = [[NSMutableDictionary alloc] init];
	}

    id __strong propertyList = CFBridgingRelease(thePlist);
    [sCachedPlists setObject:propertyList forKey:absURL];

	return thePlist;
}


@end

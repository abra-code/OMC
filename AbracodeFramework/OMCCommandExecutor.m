//
//  OMCCommandExecutor.m
//  Abracode
//
//  Created by Tomasz Kukielka on 4/6/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import "OMCCommandExecutor.h"
#include "OMC.h"
#include "OMCFilePanels.h"
#include "ACFPropertyList.h"


static NSMutableDictionary *sCachedPlists = NULL;

@implementation OMCCommandExecutor

//when useNavDialog = TRUE, missing file context is obtained from nav dialog
//otherwise when the file context is missing the command is not executed
//if USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT is false, the command always executes and no nav dialog is shown
+ (OSStatus)runCommand:(NSString *)inCommandNameOrId forCommandFile:(NSString *)inFileName withContext:(id)inContext useNavDialog:(BOOL)useNavDialog delegate:(id)delegate
{
	OSStatus error = userCanceledErr;//pessimistic scenario
	
	CFPropertyListRef loadedPlist = [OMCCommandExecutor cachedPlistForCommandFile:inFileName];
	
	OMCExecutorRef omcExec = OMCCreateExecutor( loadedPlist );
	if(omcExec != NULL)
	{
        OMCCommandRef commandRef = OMCFindCommand( omcExec, (__bridge CFStringRef)inCommandNameOrId );
		if( OMCIsValidCommandRef(commandRef) )
		{
			error = noErr;
				
			UInt32 objectsInfo = kOmcCommandNoSpecialObjects;
			OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_CommandObjects, &objectsInfo);
			CFArrayRef docList = NULL;
			BOOL hasFiles = FALSE;
			if( inContext != NULL )
			{
                CFTypeID contextType = CFGetTypeID((__bridge CFTypeRef)inContext);
				hasFiles = ((contextType == CFArrayGetTypeID()) || (contextType == CFURLGetTypeID()));
			}
			
			Boolean useNavDialogForMissingFileContext = true;
			UInt32 executionOptions = 0;
			OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_ExecutionOptions, &executionOptions);
			if( (executionOptions & kExecutionOption_UseNavDialogForMissingFileContext) == 0 )
				useNavDialogForMissingFileContext = false;
	
			if( ((objectsInfo & kOmcCommandContainsFileObject) != 0) && !hasFiles && useNavDialogForMissingFileContext )
			{
				error = userCanceledErr;//command will not execute if we don't specify files
				if(useNavDialog)
				{
					UInt32 activationType = kActiveAlways;
					error = OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_ActivationType, &activationType);
					
					CFStringRef theMessage = CFCopyLocalizedStringFromTable(CFSTR("Choose Objects To Process"), CFSTR("Localizable"), "");
					
					NSBundle *appBundle = [NSBundle mainBundle];
					NSString *appName = [appBundle objectForInfoDictionaryKey:@"CFBundleName"];
					if(appName == NULL)
						appName = @"OMCApplet";
					
					switch(activationType)
					{
						case kActiveFile:
						{
                            docList = CreateCFURLsFromOpenDialog( (__bridge CFStringRef)appName, theMessage, NULL, NULL, kOMCFilePanelCanChooseFiles | kOMCFilePanelAllowMultipleItems );
						}
						break;
							
						case kActiveFolder:
						case kActiveFinderWindow:
						case kActiveFolderExcludeFinderWindow:
						{
                            docList = CreateCFURLsFromOpenDialog( (__bridge CFStringRef)appName, theMessage, NULL, NULL, kOMCFilePanelCanChooseDirectories | kOMCFilePanelAllowMultipleItems );
						}
						break;
							
						default:
						{
                            docList = CreateCFURLsFromOpenDialog( (__bridge CFStringRef)appName, theMessage, NULL, NULL, kOMCFilePanelCanChooseFiles | kOMCFilePanelCanChooseDirectories | kOMCFilePanelAllowMultipleItems );
						}
						break;				
					}
					CFRelease(theMessage);
					error = (docList != NULL) ? noErr : userCanceledErr;
				}
				
				if( error == noErr )
				{
					error = OMCExamineContext( omcExec, commandRef, docList );
					
					if( (error == noErr) && (delegate != NULL) && [delegate respondsToSelector:@selector(noteNewRecentDocumentURL:)] )
					{
						//add to open recent
                        NSArray<NSURL*> *__weak absoluteURLArray = (__bridge NSArray<NSURL*> *)docList;
                        for(NSURL *oneFileURL in absoluteURLArray)
                        {
                            [delegate noteNewRecentDocumentURL:oneFileURL];
                        }
					}
				}
			}
			else
			{
                error = OMCExamineContext( omcExec, commandRef, (__bridge CFTypeRef)inContext );
			}
			
			if(docList != NULL)
			{
				CFRelease(docList);
				docList = NULL;
			}

			if( error == noErr )
			{
				error = OMCExecuteCommand( omcExec, commandRef );
				if(error != noErr)
				{
					NSLog(@"OMCRunCommand returned error = %d", (int)error);
				}
			}
		}
		
		OMCReleaseExecutor( omcExec );//safe to release here. task lives on if execution is asynchronous
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

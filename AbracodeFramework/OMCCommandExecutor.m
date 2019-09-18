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
		OMCCommandRef commandRef = OMCFindCommand( omcExec, (CFStringRef)inCommandNameOrId );
		if( OMCIsValidCommandRef(commandRef) )
		{
			error = noErr;
				
			UInt32 objectsInfo = kOmcCommandNoSpecialObjects;
			OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_CommandObjects, &objectsInfo);
			CFArrayRef docList = NULL;
			BOOL hasFiles = FALSE;
			if( inContext != NULL )
			{
				CFTypeID contextType = CFGetTypeID( inContext );
				hasFiles = ((contextType == CFArrayGetTypeID()) || (contextType == CFURLGetTypeID()));
			}
			
			Boolean useNavDialogForMissingFileContext = true;
			UInt32 executionOptions = 0;
			OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_ExecutionOptions, &objectsInfo);
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
					CFStringRef appName = (CFStringRef)[appBundle objectForInfoDictionaryKey:@"CFBundleName"];
					if(appName == NULL)
						appName = CFSTR("OMCApplet");
					
					switch(activationType)
					{
						case kActiveFile:
						{
							docList = CreateCFURLsFromOpenDialog( appName, theMessage, NULL, NULL, kOMCFilePanelCanChooseFiles | kOMCFilePanelAllowMultipleItems );
						}
						break;
							
						case kActiveFolder:
						case kActiveFinderWindow:
						case kActiveFolderExcludeFinderWindow:
						{
							docList = CreateCFURLsFromOpenDialog( appName, theMessage, NULL, NULL, kOMCFilePanelCanChooseDirectories | kOMCFilePanelAllowMultipleItems );
						}
						break;
							
						default:
						{
							docList = CreateCFURLsFromOpenDialog( appName, theMessage, NULL, NULL, kOMCFilePanelCanChooseFiles | kOMCFilePanelCanChooseDirectories | kOMCFilePanelAllowMultipleItems );
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
						NSArray *absoluteURLArray = (NSArray *)docList;
						NSUInteger fileCount = [absoluteURLArray count];
						NSUInteger i;
						for( i = 0; i < fileCount; i++ )
						{
							id oneFileURL = [absoluteURLArray objectAtIndex:i];
							[delegate noteNewRecentDocumentURL:oneFileURL];
						}
					}
				}
			}
			else
			{
				error = OMCExamineContext( omcExec, commandRef, (CFTypeRef)inContext );
			}
			
			if(docList != NULL)
			{
				CFRelease(docList);
				docList = NULL;
			}

			if( error == noErr )
			{
				//	if(mObserver == NULL)
				//	{
				//		mObserver = OMCCreateObserver( kOmcObserverAllMessages, CocoaExecutorObserverCallback, (void *)self );
				//		OMCAddObserver( omcExec, mObserver );
				//	}
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
		CFPropertyListRef outPlist = [sCachedPlists objectForKey:absURL];
		if(outPlist != NULL)
			return outPlist;
	}


//not found, load it and cache

    CFPropertyListRef thePlist = CreatePropertyList((CFURLRef)absURL, kCFPropertyListImmutable);

	if(thePlist == NULL)
		return NULL;

	if(sCachedPlists == NULL)
	{
		sCachedPlists = [[NSMutableDictionary alloc] init];
	}

	[sCachedPlists setObject:(id)thePlist forKey:(id)absURL];// plist retained
	CFRelease( thePlist );

	return thePlist;
}


@end

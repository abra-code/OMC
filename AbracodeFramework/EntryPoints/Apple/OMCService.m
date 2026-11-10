//
//  OMCService.m
//  OMCService
//
//  Created by Tomasz Kukielka on 1/20/11.
//  Copyright 2011 Abracode. All rights reserved.
//

#import "OMCService.h"
#include "ACFPropertyList.h"

// AppletBuilder writes the legacy NSPasteboard type *name* (not a UTI) into a generated applet's
// Info.plist NSServices entries, e.g. <string>NSStringPboardType</string> for NSSendTypes/NSReturnTypes.
// Match that literal token here so we keep recognizing OMC-generated services without referencing the
// deprecated AppKit constant. This is plist data, not a pasteboard type used at runtime.
static NSString * const kOMCLegacyStringPboardTypeName = @"NSStringPboardType";

void OMCServiceObserverCallback( OmcObserverMessage inMessage, CFIndex inTaskID, CFTypeRef inResult, void *userData )
{
	if(userData == NULL)
    {
        return;
    }
    
    id __weak objcObject = (__bridge id)userData;
    if ([objcObject conformsToProtocol:@protocol(OMCObserverDelegate)])
	{
		id<OMCObserverDelegate> __strong observerDelegate = objcObject;
		[observerDelegate receiveObserverMessage:inMessage forTaskId:inTaskID withData:inResult];
	}
}

@implementation OMCService


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	NSApplication *omcServiceApp = [NSApplication sharedApplication];
	[omcServiceApp setServicesProvider:self];
}

//userData is command name
- (void)runOMCService:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error
{
	NSBundle *appBundle = [NSBundle mainBundle];
    NSURL *commandURL = nil;

    BOOL runningInOMCServiceApp = [appBundle.bundleIdentifier isEqualToString:@"com.abracode.OMCService"];
    // if we are running in OMCService.service app we call OMCCreateExecutor() with commandURL = nil
    // and that will read the command list from
    // "com.abracode.OnMyCommandCMPrefs.plist" in ~/Library/Preferences/
    // otherwise we find Command.plist in the applet bundle here:
    if(!runningInOMCServiceApp)
    {
        // Prefer Command.json over Command.plist in the applet bundle.
        CFURLRef resolvedURL = CopyCommandFileURLInBundle(CFBundleGetMainBundle(), CFSTR("Command"));
        if(resolvedURL == NULL)
        {
            if(error != NULL)
                *error = @"Could not find Command.json or Command.plist in app bundle";
            return;
        }
        commandURL = CFBridgingRelease(resolvedURL);
    }

    OMCExecutorRef omcExec = OMCCreateExecutor( (__bridge CFURLRef)commandURL );
	if(omcExec == NULL)
	{
		if(error != NULL)
			*error = @"Could not create OMC Executor";
		return;
	}

	BOOL prefersTextContext = NO;
	BOOL wantsToReturnText = NO;

	NSDictionary *infoDictionary = [appBundle infoDictionary];
	NSArray *servicesArray = (NSArray *)[infoDictionary objectForKey:@"NSServices"];
	if( (servicesArray != NULL) &&
		[servicesArray isKindOfClass:NSArray.class] &&
		([servicesArray count] > 0) )
	{
		NSDictionary *omcServiceDict = (NSDictionary *)[servicesArray objectAtIndex:0];
		if( (omcServiceDict != NULL) &&
			[omcServiceDict isKindOfClass:NSDictionary.class] )
		{
            NSArray *sendFileTypesArray = (NSArray *)[omcServiceDict objectForKey:@"NSSendFileTypes"];
            if( [sendFileTypesArray isKindOfClass:NSArray.class] && (sendFileTypesArray.count > 0))
            {
                prefersTextContext = NO;
            }
            else
            {
                NSArray *sendTypesArray = (NSArray *)[omcServiceDict objectForKey:@"NSSendTypes"];
                if( [sendTypesArray isKindOfClass:NSArray.class] && (sendTypesArray.count > 0))
                {
                    NSString *oneType = (NSString *)[sendTypesArray objectAtIndex:0];
                    if( [oneType isKindOfClass:NSString.class] &&
                       ([oneType isEqualToString:kOMCLegacyStringPboardTypeName] || [oneType isEqualToString:NSPasteboardTypeString]) )
                    {
                        prefersTextContext = YES;
                    }
                }
            }
            
			NSArray *returnTypesArray = (NSArray *)[omcServiceDict objectForKey:@"NSReturnTypes"];
			if([returnTypesArray isKindOfClass:NSArray.class] && (returnTypesArray.count > 0))
			{
                NSString *oneType = (NSString *)[returnTypesArray objectAtIndex:0];
                if( (oneType != NULL) &&
                    [oneType isKindOfClass:NSString.class] &&
                    ([oneType isEqualToString:kOMCLegacyStringPboardTypeName] || [oneType isEqualToString:NSPasteboardTypeString]) )
                {
                    wantsToReturnText = YES;
                }
			}
		}
	}
	
	id contextObj = nil;
	if(pboard != nil)
	{
        NSArray<NSPasteboardType> *pasteboardTypes = pboard.types;
        
		if(prefersTextContext)
		{
			NSArray *supportedTextTypes = @[NSPasteboardTypeString];
			NSString *bestType = [pboard availableTypeFromArray:supportedTextTypes];
			if(bestType != NULL)
            {
                // NSPasteboard auto-bridges the legacy "NSStringPboardType" content to NSPasteboardTypeString.
                contextObj = [pboard stringForType:NSPasteboardTypeString];
            }
		}

		if((contextObj == nil) && (pasteboardTypes.count > 0)) //also will enter here if prefersTextContext == false
		{ //try files
			NSArray *supportedFileTypes = @[NSPasteboardTypeFileURL];
			NSString *bestType = [pboard availableTypeFromArray:supportedFileTypes];
			if(bestType != NULL)
			{
                // readObjectsForClasses:@[NSURL] also reads legacy "NSFilenamesPboardType" file paths
                // via NSPasteboard's automatic bridging, returning them as NSURLs.
                contextObj = [pboard readObjectsForClasses:@[NSURL.class] options:nil];
			}
			else if(!prefersTextContext)//we don't have file paths and did not try text yet: do it now
			{
				NSArray *supportedTextTypes = @[NSPasteboardTypeString];
				NSString *bestType = [pboard availableTypeFromArray:supportedTextTypes];
				if(bestType != NULL)
                {
                    contextObj = [pboard stringForType:NSPasteboardTypeString];
                }
			}
		}
	}

    OMCCommandRef commandRef = OMCFindCommand( omcExec, (__bridge CFStringRef)userData );
	if( OMCIsValidCommandRef(commandRef) )
	{
        if( noErr == OMCExamineContext(omcExec, commandRef, (__bridge CFTypeRef)(contextObj), kOMCExamineContextDefault) )
		{
			// This request's own observer, text and end: another request may arrive while this one waits
			OMCServiceRequest *request = [[OMCServiceRequest alloc] initReturningText:wantsToReturnText];
			[request observeExecutor:omcExec];

			OSStatus osError = OMCExecuteCommand( omcExec, commandRef );
			if(osError != noErr)
			{
				if(error != NULL)
					*error = [NSString stringWithFormat:@"OMCRunCommand returned error = %d", (int)osError];
			}
			else if(wantsToReturnText)
			{
				//we need to wait here for the result and assemble the text
				[request waitForAllTasksFinished];

				if(request.resultString != NULL)
				{
					NSArray<NSPasteboardType> *supportedTextTypes = @[NSPasteboardTypeString];
					[pboard declareTypes:supportedTextTypes owner:NULL];
					[pboard setString:request.resultString forType:NSPasteboardTypeString];
				}
			}
		}
	}
	else
	{
		if(error != NULL)
			*error = [NSString stringWithFormat:@"Could not find command named\"%@\"", userData];
	}

	OMCReleaseExecutor( omcExec );//safe to release here. task lives on if execution is asynchronous
}


@end

@implementation OMCServiceRequest

- (instancetype)initReturningText:(BOOL)inReturnsText
{
	self = [super init];
	if(self == nil)
		return nil;
	mObserver = NULL;
	mAllTasksFinished = NO;
	_resultString = inReturnsText ? [[NSMutableString alloc] init] : nil;
	return self;
}

- (instancetype)init
{
	return [self initReturningText:NO];
}

- (void)dealloc
{
	OMCUnregisterObserver( mObserver ); // we don't want to listen anymore
	OMCReleaseObserver( mObserver ); // release the observer
	mObserver = NULL;
}

- (void)observeExecutor:(OMCExecutorRef)inExecutor
{
	OMCObserverRef observer = OMCCreateObserver( kOmcObserverAllMessages, OMCServiceObserverCallback, (__bridge void *)self );
	if(observer == NULL)
		return;
	OMCAddObserver( inExecutor, observer );
	[self setObserver:observer]; // retaining and taking ownership
	OMCReleaseObserver(observer); // release local ref
}

- (void)waitForAllTasksFinished
{
	// mAllTasksFinished is set by the observer callback whenever the message arrives: before this runs
	// for a synchronous command (AppleScript, system), which sends it inside OMCExecuteCommand
	NSRunLoop *theRL = [NSRunLoop currentRunLoop];
	while (!mAllTasksFinished && [theRL runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]])
	{
		;
	}
}

- (void)setObserver:(OMCObserverRef)observer
{
    OMCRetainObserver(observer);
    if (observer != mObserver)
    {
        OMCUnregisterObserver(mObserver);
    }
    OMCReleaseObserver(mObserver);

    mObserver = observer;
}

- (void)receiveObserverMessage:(OmcObserverMessage)inMessage forTaskId:(CFIndex)inTaskID withData:(CFTypeRef)inResult
{
	//NSString *messageString = NULL;
	switch(inMessage)
	{
		case kOmcObserverTaskFinished:
			//messageString = @"<<task finished>>";
		break;
		
		case kOmcObserverTaskProgress:
		{
			//messageString = @"<<task progress>>";
            id __weak objcObject = (__bridge id)inResult;
			if([objcObject isKindOfClass:[NSString class]])
			{
                [_resultString appendString:(NSString *)objcObject];
			}
		}
		break;
		
		case kOmcObserverTaskCanceled:
		{
			//messageString = @"<<task canceled>>";
		}
		break;
		
		case kOmcObserverAllTasksFinished:
		{
			//messageString = @"<<all tasks finished>>";
            [self setObserver:nil];
			mAllTasksFinished = YES;
		}
		break;
		
		default:
		break;
	}

#if 0
	if(inMessage == kOmcObserverTaskProgress)//only task progress may carry some text from the execution
	{
		NSRunAlertPanel (
			@"OMC Execution Result",
			@"receiveObserverMessage: %@, taskID=%d, with data:\n%@",
			@"OK",
			NULL,
			NULL,
			messageString,
			(int)inTaskID,
			inResult );
	}
	NSLog( @"receiveObserverMessage: %@, taskID=%d, with data:\n%@", messageString, (int)inTaskID, inResult );
#endif
}

@end

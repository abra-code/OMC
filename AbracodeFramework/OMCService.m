//
//  OMCService.m
//  OMCService
//
//  Created by Tomasz Kukielka on 1/20/11.
//  Copyright 2011 Abracode. All rights reserved.
//

#import "OMCService.h"

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

- (id)init
{
    self = [super init];
	if(self == nil)
		return nil;

    mObserver = NULL;
	mRunLoopStarted = NO;
    return self;
}

- (void)dealloc
{
    OMCUnregisterObserver( mObserver ); // we don't want to listen anymore
    OMCReleaseObserver( mObserver ); // release the observer
    mObserver = NULL;
    
	if(mRunLoopStarted)
	{
		//CFRunLoopStop( CFRunLoopGetCurrent() );
		mRunLoopStarted = NO;
	}
}


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
        NSString *plistPath = [appBundle pathForResource:@"Command" ofType:@"plist"];
        if(plistPath == NULL)
        {
            if(error != NULL)
                *error = @"Could not find Command.plist in app bundle";
            return;
        }
        commandURL = [NSURL fileURLWithPath:plistPath];
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
                       ([oneType isEqualToString:NSStringPboardType] || [oneType isEqualToString:NSPasteboardTypeString]) )
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
                    ([oneType isEqualToString:NSStringPboardType] || [oneType isEqualToString:NSPasteboardTypeString]) )
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
			NSArray *supportedTextTypes = @[NSPasteboardTypeString, NSStringPboardType];
			NSString *bestType = [pboard availableTypeFromArray:supportedTextTypes];
			if(bestType != NULL)
            {
                contextObj = [pboard stringForType:NSPasteboardTypeString];
                if(contextObj == nil)
                {
                    contextObj = [pboard stringForType:NSStringPboardType];
                }
            }
		}

		if((contextObj == nil) && (pasteboardTypes.count > 0)) //also will enter here if prefersTextContext == false
		{ //try files
			NSArray *supportedFileTypes = @[NSFilenamesPboardType, NSPasteboardTypeFileURL];
			NSString *bestType = [pboard availableTypeFromArray:supportedFileTypes];
			if(bestType != NULL)
			{
                contextObj = [pboard readObjectsForClasses:@[NSURL.class] options:nil];
                if(contextObj == nil)
                {
                    contextObj = [pboard propertyListForType:NSFilenamesPboardType];
                }
			}
			else if(!prefersTextContext)//we don't have file paths and did not try text yet: do it now
			{
				NSArray *supportedTextTypes = @[NSPasteboardTypeString, NSStringPboardType];
				NSString *bestType = [pboard availableTypeFromArray:supportedTextTypes];
				if(bestType != NULL)
                {
                    contextObj = [pboard stringForType:NSPasteboardTypeString];
                    if(contextObj == nil)
                    {
                        contextObj = [pboard stringForType:NSStringPboardType];
                    }
                }
			}
		}
	}

    OMCCommandRef commandRef = OMCFindCommand( omcExec, (__bridge CFStringRef)userData );
	if( OMCIsValidCommandRef(commandRef) )
	{
        if( noErr == OMCExamineContext(omcExec, commandRef, (__bridge CFTypeRef)(contextObj)) )
		{
			if(mObserver == NULL)
			{
                OMCObserverRef observer = OMCCreateObserver( kOmcObserverAllMessages, OMCServiceObserverCallback, (__bridge void *)self );
				OMCAddObserver( omcExec, observer );
                [self setObserver:observer]; // retaining and taking ownership
                OMCReleaseObserver(observer); // release local ref
			}
			
			if(wantsToReturnText)
			{
				self.resultString = [[NSMutableString alloc] init];
			}
			
			OSStatus osError = OMCExecuteCommand( omcExec, commandRef );
			if(osError != noErr)
			{
				if(error != NULL)
					*error = [NSString stringWithFormat:@"OMCRunCommand returned error = %d", (int)osError];
			}
			else if(wantsToReturnText)
			{
				//we need to wait here for the result and assemble the text
				//NSLog( @"Starting runloop...");
				mRunLoopStarted = YES;
				//CFRunLoopRun();
				//[[NSRunLoop currentRunLoop] run];
				NSRunLoop *theRL = [NSRunLoop currentRunLoop];
				while (mRunLoopStarted && [theRL runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]])
				{
					;
				}

				if(self.resultString != NULL)
				{
					//NSLog(@"Setting pasteboard text to: %@", mResultString);
					NSArray *supportedTextTypes = @[NSStringPboardType];
					[pboard declareTypes:supportedTextTypes owner:NULL];
					[pboard setString:self.resultString forType:NSStringPboardType];
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
                [self.resultString appendString:(NSString *)objcObject];
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
			
			if(mRunLoopStarted)
			{
				//NSLog( @"Stopping runloop...");
				//CFRunLoopStop( CFRunLoopGetCurrent() );
				mRunLoopStarted = NO;
			}
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

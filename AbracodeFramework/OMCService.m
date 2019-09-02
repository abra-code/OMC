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
		return;
	
	id objcObject = (id)userData;
	if( [objcObject isKindOfClass:[OMCService class] ] )
	{
		OMCService *cocoaDelegate = (OMCService *)objcObject;
		[cocoaDelegate receiveObserverMessage:inMessage forTaskId:inTaskID withData:inResult];
	}
}

@implementation OMCService

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;

    mObserver = NULL;
	mResultString = NULL;
	mRunLoopStarted = NO;
    return self;
}

- (void)dealloc
{
	if( mObserver != NULL )
	{
		OMCUnregisterObserver( mObserver );//we don't want to listen anymore
		OMCReleaseObserver( mObserver );//release the observer
		mObserver = NULL;
	}
	
	[mResultString release];
	mResultString = NULL;
	
	if(mRunLoopStarted)
	{
		//CFRunLoopStop( CFRunLoopGetCurrent() );
		mRunLoopStarted = NO;
	}

	[super dealloc];
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

#if 0 //the latest idea is to have one OMCService and use the main plist
	NSString *plistPath = [appBundle pathForResource:@"Command" ofType:@"plist"];
	if(plistPath == NULL)
	{
		if(error != NULL)
			*error = @"Could not find Command.plist in service bundle";
		return;
	}
	NSURL *commandURL = [NSURL fileURLWithPath:plistPath];
#else
    NSURL *commandURL = NULL;
#endif //0

	OMCExecutorRef omcExec = OMCCreateExecutor( (CFURLRef)commandURL );
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
		[servicesArray isKindOfClass:[NSArray class]] &&
		([servicesArray count] > 0) )
	{
		NSDictionary *omcServiceDict = (NSDictionary *)[servicesArray objectAtIndex:0];
		if( (omcServiceDict != NULL) &&
			[omcServiceDict isKindOfClass:[NSDictionary class]] )
		{
			NSArray *sendTypesArray = (NSArray *)[omcServiceDict objectForKey:@"NSSendTypes"];
			if( (sendTypesArray != NULL) &&
				[sendTypesArray isKindOfClass:[NSArray class]] )
			{
				NSUInteger typesCount = [sendTypesArray count];
				if(typesCount > 0)
				{
					NSString *oneType = (NSString *)[sendTypesArray objectAtIndex:0];
					if( (oneType != NULL) &&
						[oneType isKindOfClass:[NSString class]] &&
						([oneType isEqualToString:NSStringPboardType] || [oneType isEqualToString:NSPasteboardTypeString]) )
					{
						prefersTextContext = YES;
					}
				}
			}

			NSArray *returnTypesArray = (NSArray *)[omcServiceDict objectForKey:@"NSReturnTypes"];
			if( (returnTypesArray != NULL) &&
				[returnTypesArray isKindOfClass:[NSArray class]] )
			{
				NSUInteger typesCount = [returnTypesArray count];
				if(typesCount > 0)
				{
					NSString *oneType = (NSString *)[sendTypesArray objectAtIndex:0];
					if( (oneType != NULL) &&
						[oneType isKindOfClass:[NSString class]] &&
						([oneType isEqualToString:NSStringPboardType] || [oneType isEqualToString:NSPasteboardTypeString]) )
					{
						wantsToReturnText = YES;
					}
				}
			}
		}
	}
	
	CFTypeRef contextRef = NULL;
	if(pboard != NULL)
	{
		if(prefersTextContext)
		{
			NSArray *supportedTextTypes = [NSArray arrayWithObjects: NSStringPboardType, NULL];
			NSString *bestType = [pboard availableTypeFromArray:supportedTextTypes];
			if(bestType != NULL)
				contextRef = (CFTypeRef)[pboard stringForType:NSStringPboardType];
		}

		if(contextRef == NULL)//also will enter here if prefersTextContext == false
		{//try file names
			NSArray *supportedFileTypes = [NSArray arrayWithObjects: NSFilenamesPboardType, NULL];
			NSString *bestType = [pboard availableTypeFromArray:supportedFileTypes];
			if(bestType != NULL)
			{
				contextRef = (CFTypeRef)[pboard propertyListForType:NSFilenamesPboardType];
				//if([resultList isKindOfClass:[NSArray class]])
			}
			else if(!prefersTextContext)//we don't have file paths and did not try text yet: do it now
			{
				NSArray *supportedTextTypes = [NSArray arrayWithObjects: NSStringPboardType, NULL];
				NSString *bestType = [pboard availableTypeFromArray:supportedTextTypes];
				if(bestType != NULL)
					contextRef = (CFTypeRef)[pboard stringForType:NSStringPboardType];
			}
		}
	}

	OMCCommandRef commandRef = OMCFindCommand( omcExec, (CFStringRef)userData );
	if( OMCIsValidCommandRef(commandRef) )
	{
		if( noErr == OMCExamineContext(omcExec, commandRef, contextRef) )
		{
			if(mObserver == NULL)
			{
				mObserver = OMCCreateObserver( kOmcObserverAllMessages, OMCServiceObserverCallback, (void *)self );
				OMCAddObserver( omcExec, mObserver );
			}
			
			if(wantsToReturnText)
			{
				mResultString = [[NSMutableString alloc] initWithCapacity:0];
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

				if(mResultString != NULL)
				{
					//NSLog(@"Setting pasteboard text to: %@", mResultString);
					NSArray *supportedTextTypes = [NSArray arrayWithObjects: NSStringPboardType, NULL];
					[pboard declareTypes:supportedTextTypes owner:NULL];
					[pboard setString:mResultString forType:NSStringPboardType];
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
			if( (inResult != NULL) &&
				[(id)inResult isKindOfClass:[NSString class]] )
			{
				[mResultString appendString:(NSString*)inResult];
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
			OMCUnregisterObserver( mObserver );//we don't want to listen anymore
			OMCReleaseObserver( mObserver );//we are all done, release the observer
			mObserver = NULL;
			
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

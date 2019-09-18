//
//  OMCTestApp.m
//  OMCTestApp
//
//  Created by Tomasz Kukielka on 1/2/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import "OMCTestApp.h"

void OMCTestAppObserverCallback( OmcObserverMessage inMessage, CFIndex inTaskID, CFTypeRef inResult, void *userData )
{
	if(userData == NULL)
		return;
	
	id objcObject = (id)userData;
	if( [objcObject isKindOfClass:[OMCTestAppController class] ] )
	{
		OMCTestAppController *cocoaController = (OMCTestAppController *)objcObject;
		[cocoaController receiveObserverMessage:inMessage forTaskId:inTaskID withData:inResult];
	}
}

@implementation OMCTestAppController

- (id)init
{
    if (![super init])
        return NULL;

    mObserver = NULL;
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

	[super dealloc];
}


- (IBAction)executeExampleCommand:(id)sender
{
	NSBundle *appBundle = [NSBundle mainBundle];
	NSString *plistPath = [appBundle pathForResource:@"Example" ofType:@"plist"];
	if(plistPath != NULL)
	{
		NSURL *commandURL = [NSURL fileURLWithPath:plistPath];
		OSStatus error = OMCRunCommand( (CFURLRef)commandURL, (CFStringRef)@"Example Command", NULL);
		if(error != noErr)
		{
			NSLog(@"OMCRunCommand returned error = %d", (int)error);
		}
	}
	else
	{
		NSLog(@"Example.plist was not found in application resources");
	}
}


- (IBAction)executeCommandWithFileContext:(id)sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	if(openPanel == NULL)
	{
		NSLog(@"Could not create NSOpenPanel");
		return;
	}
	
	[openPanel setMessage:@"Choose a file to compress with gzip"];
	
	NSInteger result = [openPanel runModalForTypes:NULL];
	if(result != NSModalResponseOK)
	{
		return;
	}
	
	NSArray *urlArray = [openPanel URLs];
	
	NSBundle *appBundle = [NSBundle mainBundle];
	NSString *plistPath = [appBundle pathForResource:@"gzip" ofType:@"plist"];
	if(plistPath != NULL)
	{
		NSURL *commandURL = [NSURL fileURLWithPath:plistPath];
		OSStatus error = OMCRunCommand( (CFURLRef)commandURL, (CFStringRef)@"Compress with gzip", (CFTypeRef)urlArray);
		if(error != noErr)
		{
			NSLog(@"OMCRunCommand returned error = %d", (int)error);
		}
	}
	else
	{
		NSLog(@"gzip.plist was not found in application resources");
	}
}

- (IBAction)executeCommandWithText:(id)sender
{
	NSBundle *appBundle = [NSBundle mainBundle];
	NSString *plistPath = [appBundle pathForResource:@"TextContext" ofType:@"plist"];
	if(plistPath != NULL)
	{
		NSURL *commandURL = [NSURL fileURLWithPath:plistPath];
		OSStatus error = OMCRunCommand( (CFURLRef)commandURL, (CFStringRef)@"Show Text Statistics", (CFStringRef)@"The quick brown fox jumps over the lazy dog" );
		
		if(error != noErr)
		{
			NSLog(@"OMCRunCommand returned error = %d", (int)error);
		}
	}
	else
	{
		NSLog(@"TextContext.plist was not found in application resources");
	}
}

- (IBAction)executeExternalBundle:(id)sender
{
	NSBundle *appBundle = [NSBundle mainBundle];
	NSString *externalBundlePath = [appBundle pathForResource:@"Ls Browser" ofType:@"omc"];
	if(externalBundlePath != NULL)
	{
		NSURL *commandURL = [NSURL fileURLWithPath:externalBundlePath];
		NSURL *fileContextURL = [NSURL fileURLWithPath:@"/"];//root directory of startup volume
		OSStatus error = OMCRunCommand( (CFURLRef)commandURL, (CFStringRef)@"Ls Browser", (CFTypeRef)fileContextURL);
		if(error != noErr)
		{
			NSLog(@"OMCRunCommand returned error = %d", (int)error);
		}
	}
	else
	{
		NSLog(@"Ls Browser.omc was not found in application resources");
	}
}


- (IBAction)executeCommandWithObserver:(id)sender
{
	NSBundle *appBundle = [NSBundle mainBundle];
	NSString *plistPath = [appBundle pathForResource:@"ForOutputObserver" ofType:@"plist"];
	if(plistPath != NULL)
	{
		NSURL *commandURL = [NSURL fileURLWithPath:plistPath];
		OMCExecutorRef omcExec = OMCCreateExecutor( (CFURLRef)commandURL );
		if(omcExec != NULL)
		{
			OMCCommandRef commandRef = OMCFindCommand( omcExec, (CFStringRef)@"Echo text" );
			if( OMCIsValidCommandRef(commandRef) )
			{
				if( noErr == OMCExamineContext(omcExec, commandRef, (CFStringRef)@"The quick brown fox jumps over the lazy dog" ) )
				{
					if(mObserver == NULL)
					{
						mObserver = OMCCreateObserver( kOmcObserverAllMessages, OMCTestAppObserverCallback, (void *)self );
						OMCAddObserver( omcExec, mObserver );
					}
					OSStatus error = OMCExecuteCommand( omcExec, commandRef );
					if(error != noErr)
					{
						NSLog(@"OMCRunCommand returned error = %d", (int)error);
					}
				}
			}
			
			OMCReleaseExecutor( omcExec );//safe to release here. task lives on if execution is asynchronous
		}
	}
}


- (void)receiveObserverMessage:(OmcObserverMessage)inMessage forTaskId:(CFIndex)inTaskID withData:(CFTypeRef)inResult
{
	NSString *messageString = NULL;
	switch(inMessage)
	{
		case kOmcObserverTaskFinished:
			messageString = @"<<task finished>>";
		break;
		
		case kOmcObserverTaskProgress:
			messageString = @"<<task progress>>";
		break;
		
		case kOmcObserverTaskCanceled:
			messageString = @"<<task canceled>>";
		break;
		
		case kOmcObserverAllTasksFinished:
		{
			messageString = @"<<all tasks finished>>";
			OMCUnregisterObserver( mObserver );//we don't want to listen anymore
			OMCReleaseObserver( mObserver );//we are all done, release the observer
			mObserver = NULL;
		}
		break;
		
		default:
		break;
	}

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
}

@end


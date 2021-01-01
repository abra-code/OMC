//
//  OMCProgressWindowController.m
//  Abracode
//
//  Created by Tomasz Kukielka on 10/31/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#import "OMCProgressWindowController.h"


@implementation OMCProgressWindowController

- (id)initWithWindowNibName:(NSString *)windowNibName
{
	self = [super initWithWindowNibName:windowNibName];
	if(self == nil)
		return nil;

	mCanceled = NO;
	mIsDeterminate = NO;
	mLastValue = INT_MIN;
	mLastString = NULL;

#if 0 //_DEBUG_
	NSLog(@"OMCProgressWindowController = 0x%X", (void *)self);
	NSLog(@"OMCProgressWindowController window = 0x%X", (void *)[self window]);
#endif
	return self;
}

- (void)dealloc
{
/*  do not call [self window] in dealloc. Our refcount is 0 now and this will try to:
	- load the window
	- revive the controller and retain

	NSWindow *outputWindow = [self window];
	
	if(outputWindow != NULL)
	{
		[outputWindow close];
	}
*/
	if(mLastString != NULL)
		[mLastString release];
	
	[super dealloc];
}

//NULL inText means: "don't change the last one" and the code in OMCDeferredProgress relies on that
- (void)setProgress:(double)inProgress text:(NSString *)inText;
{
#if 0 //_DEBUG_
		if(inText != NULL)
			NSLog(@"setProgress:%f %@", inProgress, inText);
		else
			NSLog(@"setProgress:%f NULL", inProgress);
#endif

#if 0//_DEBUG_
	NSLog(@"[OMCProgressWindowController setProgress:%f]", inProgress);
#endif

	BOOL wantsDeterminate = (inProgress >= 0.0) ? YES : NO;
	if( (mLastValue == INT_MIN) || (wantsDeterminate != mIsDeterminate) )
	{
		[mProgressIndicator setIndeterminate: !wantsDeterminate];
		if(!wantsDeterminate)
			[mProgressIndicator startAnimation:self];

		mIsDeterminate = wantsDeterminate;
		[mProgressIndicator setNeedsDisplay:YES];
	}

	int newValue = round(inProgress);

	if( wantsDeterminate && (newValue > mLastValue ) )
	{
		if(newValue > 100.0)
			newValue = 100.0;
		
		[mProgressIndicator setDoubleValue:(double)newValue];
		[mProgressIndicator setNeedsDisplay:YES];
		mLastValue = newValue;
#if 0 //_DEBUG_
		NSLog(@"Setting progress to %d", newValue);
#endif
	}
	else if(!wantsDeterminate)
	{
		mLastValue = newValue;
	}

	if(inText != NULL)
	{
		BOOL differentString = YES;
		if(mLastString != NULL)
			differentString = ![mLastString isEqualToString:inText];
		
		if(differentString)
		{
			[mStatusText setStringValue:inText];
			[mStatusText setNeedsDisplay:YES];
		}

		if(mLastString != NULL)
			[mLastString release];
		mLastString = inText;
		[mLastString retain];
	}
}

- (IBAction)closeWindow:(id)sender
{
	[[self window] close];
	//TODO: inform OMCDeferredProgress about it and let it die
	mCanceled = YES;
}

- (BOOL)isCanceled
{
	return mCanceled;
}

@end

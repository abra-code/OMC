//
//  OMCProgressWindowController.m
//  Abracode
//
//  Created by Tomasz Kukielka on 10/31/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#import "OMCProgressWindowController.h"
#include "DebugSettings.h"

@implementation OMCProgressWindowController

- (id)initWithWindowNibName:(NSString *)windowNibName
{
	self = [super initWithWindowNibName:windowNibName];
	if(self == nil)
		return nil;

	mCanceled = NO;
	mIsDeterminate = NO;
	mLastValue = INT_MIN;

#if 0 //_DEBUG_
	NSLog(@"OMCProgressWindowController = 0x%X", (void *)self);
	NSLog(@"OMCProgressWindowController window = 0x%X", (void *)[self window]);
#endif

	return self;
}

//NULL inText means: "don't change the last one" and the code in OMCDeferredProgress relies on that
- (void)setProgress:(double)inProgress text:(NSString *)inText;
{
    if(inText != NULL) {
        TRACE_CSTR("setProgress:%f %s\n", inProgress, inText.UTF8String);
    }
    else {
        TRACE_CSTR("setProgress:%f NULL\n", inProgress);
    }

	BOOL wantsDeterminate = (inProgress >= 0.0) ? YES : NO;
    
    TRACE_CSTR("wantsDeterminate:%d, mIsDeterminate: %d mLastValue:%d\n", wantsDeterminate, mIsDeterminate, mLastValue);
	if( (mLastValue == INT_MIN) || (wantsDeterminate != mIsDeterminate) )
	{
        TRACE_CSTR("mProgressIndicator setIndeterminate: %d\n", !wantsDeterminate);
		[mProgressIndicator setIndeterminate: !wantsDeterminate];
		if(wantsDeterminate)
        {
            [mProgressIndicator stopAnimation:self];
        }
        else
        {
            [mProgressIndicator startAnimation:self];
        }
        
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

        TRACE_CSTR("Setting progress to %d\n", newValue);
	}
	else if(!wantsDeterminate)
	{
		mLastValue = newValue;
	}

	if(inText != nil)
	{
		if(![self.lastString isEqualToString:inText])
		{
			[mStatusText setStringValue:inText];
			[mStatusText setNeedsDisplay:YES];
		}

        self.lastString = inText;
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

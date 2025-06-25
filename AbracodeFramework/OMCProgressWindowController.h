//
//  OMCProgressWindowController.h
//  Abracode
//
//  Created by Tomasz Kukielka on 10/31/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface OMCProgressWindowController : NSWindowController
{
	IBOutlet NSProgressIndicator *mProgressIndicator;
	IBOutlet NSTextField *mStatusText;
	BOOL mCanceled;
	BOOL mIsDeterminate;
	int mLastValue;
}

@property (nonatomic, strong) NSString *lastString;

- (void)setProgress:(double)inProgress text:(NSString *)inText;
- (IBAction)closeWindow:(id)sender;
- (BOOL)isCanceled;

@end

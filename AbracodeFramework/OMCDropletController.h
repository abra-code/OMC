//
//  OMCDropletController.h
//  CocoaApp
//
//  Created by Tomasz Kukielka on 4/17/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCDropletController : NSDocumentController<NSApplicationDelegate>
{
	NSString *	commandID;//main/startup command name/id
	NSString *	commandFilePath; //main plist file
	BOOL		_startingUp;
	CGEventFlags _startupModifiers;
	int			_runningCommandCount;
}

@property(retain) IBInspectable NSString * commandID;
@property(retain) IBInspectable NSString * commandFilePath;


- (void)showPrefsDialog:(id)sender;

- (void)openFiles:(NSArray *)absoluteURLArray;

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent;

@end

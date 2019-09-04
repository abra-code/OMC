//
//  OMCDropletController.h
//  CocoaApp
//
//  Created by Tomasz Kukielka on 4/17/08.
//

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCDropletController : NSDocumentController<NSApplicationDelegate>
{
	NSString *	_commandFilePath;
	BOOL		_startingUp;
	CGEventFlags _startupModifiers;
	int			_runningCommandCount;
}

@property (nonatomic, retain) IBInspectable NSString * commandID; // main/startup command name/id
@property (nonatomic, retain) IBInspectable NSString * commandFilePath; //main plist file

- (void)openFiles:(NSArray *)absoluteURLArray;

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent;

@end

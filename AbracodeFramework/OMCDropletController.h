//
//  OMCDropletController.h
//  CocoaApp
//
//  Created by Tomasz Kukielka on 4/17/08.
//

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCDropletController : NSDocumentController<NSApplicationDelegate, NSMenuDelegate>
{
	BOOL		_startingUp;
	CGEventFlags _startupModifiers;
	int			_runningCommandCount;
}

@property (nonatomic, strong) IBInspectable NSString * commandID; // main/startup command name/id
@property (nonatomic, strong) IBInspectable NSString * commandFilePath; //main plist file

- (void)openFiles:(NSArray *)absoluteURLArray;

// Take over the File ▸ Open Recent submenu of the main menu and populate it from
// the shared document controller's recent documents.  Required for programmatic
// (nibless) menu bars: AppKit only auto-manages an Open Recent menu built from a
// nib (systemMenu="recentDocuments"); a menu created in code is not populated
// automatically, even with a clearRecentDocuments: item.
- (void)installOpenRecentMenu;

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent;

@end

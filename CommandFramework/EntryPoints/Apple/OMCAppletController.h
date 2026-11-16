//
//  OMCAppletController.h
//  Abracode
//
//  Created by Tomasz Kukielka on 4/17/08 as OMCDropletController; renamed in 6.0.
//

#import <Cocoa/Cocoa.h>

// The macOS side of OMCApplet.h: the app delegate and document controller of an applet, which
// hands each request to the portable OMCApplet and keeps what only AppKit does.
@interface OMCAppletController : NSDocumentController<NSApplicationDelegate, NSMenuDelegate>

@property (nonatomic, strong) NSString * commandID; // main/startup command name/id
@property (nonatomic, strong) NSString * commandFilePath; //main plist file

- (void)openFiles:(NSArray *)absoluteURLArray;

// Take over the File > Open Recent submenu of the main menu and populate it from
// the shared document controller's recent documents.  Required because the menu
// bar is built in code: AppKit only auto-manages an Open Recent menu built from a
// nib (systemMenu="recentDocuments"); a menu created in code is not populated
// automatically, even with a clearRecentDocuments: item.
- (void)installOpenRecentMenu;

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent;

@end

//
//  OMCCommandMenu.h
//  Abracode
//
//  Created by Tomasz Kukielka on 4/6/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCCommandMenu : NSMenu

@property (nonatomic, strong) IBInspectable NSString * commandFilePath;

// Clears the menu and (re)populates it from the command file (Command.json /
// Command.plist) in the main bundle.  Invoked automatically from awakeFromNib
// for nib-loaded menus; call directly to build the menu programmatically
// (e.g. from a MainMenu.json autoPopulate Commands menu).
- (void)populateFromCommandFile;

- (void)executeCommand:(id)sender;

@end

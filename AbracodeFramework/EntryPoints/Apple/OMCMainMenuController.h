//
//  OMCMainMenuController.h
//  Abracode
//
//  Created by Tomasz Kukielka on 3/30/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCMainMenuController : NSObject

@property (nonatomic, strong) IBInspectable NSString * commandFilePath;

- (void)connectOMCMenuItems:(NSMenu *)inMenu;
- (void)executeCommand:(id)sender;

// Builds the main menu bar programmatically using the shared ActionUIMenuBar
// engine.  The standard macOS bar (App/File/Edit/Window/Help) is always
// installed; an optional MainMenu.json resource layers the applet's CommandMenu
// / CommandGroup additions on top.  Returns YES once the bar is installed.
- (BOOL)installMenuBar;


@end

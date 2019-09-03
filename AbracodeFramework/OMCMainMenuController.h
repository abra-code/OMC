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
{
	NSString *	_commandFilePath;
}

@property (nonatomic, retain) IBInspectable NSString * commandFilePath;

- (void)connectOMCMenuItems:(NSMenu *)inMenu;
- (void)executeCommand:(id)sender;


@end

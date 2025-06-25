//
//  OMCMainMenuController.m
//  Abracode
//
//  Created by Tomasz Kukielka on 3/30/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import "OMCMainMenuController.h"
#import "OMCMenuItem.h"
#import "OMCCommandExecutor.h"

@implementation OMCMainMenuController

- (id)init
{
    self = [super init];
	if(self == nil)
		return nil;

	_commandFilePath = @"Command.plist";

    return self;
}

- (void)awakeFromNib
{
	NSApplication *myApp = [NSApplication sharedApplication];
	if(myApp == NULL)
		return;

	NSMenu *myMenu = [myApp mainMenu];
	
	if(myMenu == NULL)
		return;
		
	[self connectOMCMenuItems:myMenu];
	
}

- (void)setCommandFilePath:(NSString *)inPath
{
	if((inPath != nil) && ([inPath length] > 0))
	{
		_commandFilePath = inPath;
	}
	else
	{
		_commandFilePath = @"Command.plist";
	}
}


- (void) connectOMCMenuItems:(NSMenu *)inMenu
{
	NSInteger i;
	NSInteger itemCount = [inMenu numberOfItems];
	for(i = 0; i < itemCount; i++)
	{
		NSMenuItem *oneItem =  [inMenu itemAtIndex:i];
		if(oneItem != NULL)
		{
			if( [oneItem isKindOfClass:[OMCMenuItem class]] )
			{
				if( [oneItem target] == NULL )//don't override targets preset in IB
				{
					[oneItem setTarget:self];
					[oneItem setAction:@selector(executeCommand:)];
				}
			}

			if( [oneItem hasSubmenu] )
			{
				[self connectOMCMenuItems:[oneItem submenu]];
			}
		}
	}
}

- (void)executeCommand:(id)sender
{
	if( (sender == NULL) || ![sender respondsToSelector:@selector(commandID)] )
		return;

	NSString *myCommandID = [sender commandID];

	/*OSStatus err = */[OMCCommandExecutor runCommand:myCommandID forCommandFile:self.commandFilePath withContext:NULL useNavDialog:YES delegate:self];
}

@end //OMCMainMenuController

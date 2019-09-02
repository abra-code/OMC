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
	if(self == NULL)
		return NULL;
	commandFilePath = @"Command.plist";
	[commandFilePath retain];
    return self;
}

- (void)dealloc
{
    [commandFilePath release];
	[super dealloc];
}

- (void)awakeFromNib
{
	if( [self respondsToSelector: @selector(ibPopulateKeyPaths:)] )//running as plugin in IB?
		return;

	NSApplication *myApp = [NSApplication sharedApplication];
	if(myApp == NULL)
		return;

	NSMenu *myMenu = [myApp mainMenu];
	
	if(myMenu == NULL)
		return;
		
	[self connectOMCMenuItems:myMenu];
	
}

- (NSString *)commandFilePath
{
	return commandFilePath;
}

- (void)setCommandFilePath:(NSString *)inPath
{
	if(inPath != NULL)
	{
		if([inPath length] == 0)
		{
			inPath = NULL;
		}
	}

	if(inPath != NULL)
	{
		[inPath retain];
		[commandFilePath release];
		commandFilePath = inPath;
	}
	else
	{
		[commandFilePath release];
		commandFilePath = @"Command.plist";
		[commandFilePath retain];
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

	/*OSStatus err = */[OMCCommandExecutor runCommand:myCommandID forCommandFile:commandFilePath withContext:NULL useNavDialog:YES delegate:self];
}

@end //OMCMainMenuController

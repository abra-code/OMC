//
//  OMCMainMenuController.m
//  Abracode
//
//  Created by Tomasz Kukielka on 3/30/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import "OMCMainMenuController.h"
#import "OMCMenuItem.h"
#import "OMCCommandMenu.h"
#import "OMCCommandExecutor.h"

@import ActionUIMenuBar;

// Safely read an NSString value from a JSON properties dictionary.
static NSString *OMCMenuStringValue(NSDictionary *properties, NSString *key)
{
	id value = properties[key];
	return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
}

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
	/*OSStatus err = */[OMCCommandExecutor runCommand:myCommandID forCommandFile:self.commandFilePath withContext:NULL useNavDialog:YES allowKeyWindowSubcommand:YES delegate:self];
}

- (BOOL)installMenuBar
{
	// Standard macOS menu bar (App/File/Edit/Window/Help) is always installed.
	[ActionUIMenuBar installDefaultMenuBarWithAppName:nil];

	// MainMenu.json is optional: when present it layers additions/mutations
	// (command menus, command groups) on top of the standard bar.  When absent,
	// the applet keeps just the standard minimal menu bar installed above.
	NSURL *jsonURL = [[NSBundle mainBundle] URLForResource:@"MainMenu" withExtension:@"json"];
	if(jsonURL == nil)
		return YES;

	NSData *jsonData = [NSData dataWithContentsOfURL:jsonURL];
	if(jsonData == nil)
	{
		NSLog(@"OMCMainMenuController: failed to read MainMenu.json at %@", jsonURL);
		return YES;
	}

	NSError *parseError = nil;
	id parsed = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&parseError];
	if(![parsed isKindOfClass:[NSArray class]])
	{
		NSLog(@"OMCMainMenuController: MainMenu.json must be an array of menu elements: %@", parseError);
		return YES;
	}
	NSArray *elements = (NSArray *)parsed;

	// Partition elements: auto-populated Commands menus are handled here (the
	// same dynamic behavior as the nib's OMCCommandMenu); everything else is a
	// static element delegated to the shared ActionUIMenuBar engine.
	NSMutableArray *staticElements = [NSMutableArray array];
	NSMutableArray<NSDictionary *> *autoPopulateMenus = [NSMutableArray array];
	for(id element in elements)
	{
		BOOL isAutoPopulate = NO;
		if([element isKindOfClass:[NSDictionary class]]
		   && [OMCMenuStringValue(element, @"type") isEqualToString:@"CommandMenu"])
		{
			id props = ((NSDictionary *)element)[@"properties"];
			if([props isKindOfClass:[NSDictionary class]])
				isAutoPopulate = [((NSDictionary *)props)[@"autoPopulate"] boolValue];
		}

		if(isAutoPopulate)
			[autoPopulateMenus addObject:(NSDictionary *)element];
		else
			[staticElements addObject:element];
	}

	// Static elements (explicit command Buttons / CommandGroups) → shared engine.
	// Each Button's native actionID is the command id; it becomes an OMCMenuItem
	// wired to executeCommand: — the same dispatch path the nib uses.  NSMenuItem keeps a
	// weak reference to its target, so self must outlive the menu (see
	// OMCApplet/main.m).
	if(staticElements.count > 0)
	{
		NSData *staticData = [NSJSONSerialization dataWithJSONObject:staticElements options:0 error:NULL];
		NSString *staticJSON = (staticData != nil)
			? [[NSString alloc] initWithData:staticData encoding:NSUTF8StringEncoding] : nil;
		if(staticJSON != nil)
		{
			__weak OMCMainMenuController *weakSelf = self;
			[ActionUIMenuBar loadMenuBarCommandsWithJSON:staticJSON
				itemBuilder:^NSMenuItem * _Nullable(NSDictionary<NSString *, id> * _Nonnull properties) {
					OMCMenuItem *item = [[OMCMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
					// Menu-bar items use ActionUI's native actionID; in an OMC applet
					// the actionID is the command id to run.
					NSString *actionID = OMCMenuStringValue(properties, @"actionID");
					if(actionID != nil)
					{
						item.commandID = actionID;
						item.target = weakSelf;
						item.action = @selector(executeCommand:);
					}
					return item;
				}];
		}
	}

	// Auto-populated Commands menus → dynamic OMCCommandMenu, inserted before the
	// Window menu.  OMCCommandMenu wires its own items (target/action), reads the
	// command file itself, and is retained by its NSMenuItem in the main menu.
	for(NSDictionary *menuElement in autoPopulateMenus)
	{
		id props = menuElement[@"properties"];
		NSString *name = [props isKindOfClass:[NSDictionary class]]
			? OMCMenuStringValue((NSDictionary *)props, @"name") : nil;
		if(name.length == 0)
			name = @"Commands";

		OMCCommandMenu *commandMenu = [[OMCCommandMenu alloc] initWithTitle:name];
		commandMenu.commandFilePath = self.commandFilePath;
		[commandMenu populateFromCommandFile];

		NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:name action:NULL keyEquivalent:@""];
		menuItem.submenu = commandMenu;
		[self insertTopLevelMenuItemBeforeWindow:menuItem];
	}

	return YES;
}

// Insert a top-level menu before the Window menu (or Help, else at the end),
// matching the placement ActionUIMenuBar uses for CommandMenu items.
- (void)insertTopLevelMenuItemBeforeWindow:(NSMenuItem *)menuItem
{
	NSMenu *mainMenu = [NSApp mainMenu];
	if(mainMenu == nil)
		return;

	NSInteger windowIndex = -1;
	NSInteger helpIndex = -1;
	NSInteger itemCount = [mainMenu numberOfItems];
	for(NSInteger i = 0; i < itemCount; i++)
	{
		NSString *title = [[mainMenu itemAtIndex:i] submenu].title;
		if((windowIndex < 0) && [title isEqualToString:@"Window"])
			windowIndex = i;
		if((helpIndex < 0) && [title isEqualToString:@"Help"])
			helpIndex = i;
	}

	NSInteger insertIndex = itemCount;
	if(windowIndex >= 0)
		insertIndex = windowIndex;
	else if(helpIndex >= 0)
		insertIndex = helpIndex;

	[mainMenu insertItem:menuItem atIndex:insertIndex];
}

@end //OMCMainMenuController

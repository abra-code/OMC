//
//  OMCCommandMenu.m
//  Abracode
//
//  Created by Tomasz Kukielka on 4/6/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import "OMCCommandMenu.h"
#import "OMCMenuItem.h"
#include "OMCMenuModel.h"
#include "OMCCommandRunner.h"
#include "CFObj.h"
#import "OMCCommandExecutor.h"

// The model's rules are portable (OMCMenuModel.h); this builds an NSMenu from them.

// The submenu of inMenu with this title, made at the end when there is none
static NSMenu *
FindOrAddSubmenu(NSMenu *inMenu, CFStringRef inName)
{
	NSInteger itemCount = [inMenu numberOfItems];
	for(NSInteger i = 0; i < itemCount; i++)
	{
		NSMenuItem *oneItem = [inMenu itemAtIndex:i];
		if( (oneItem != nil) && [oneItem hasSubmenu] )
		{
			NSString *menuName = [oneItem title];
			if( (menuName != nil) && (kCFCompareEqualTo == ::CFStringCompare((__bridge CFStringRef)menuName, inName, 0)) )
				return [oneItem submenu];
		}
	}

	NSMenuItem *newMenuItem = [[NSMenuItem alloc] initWithTitle:(__bridge NSString *)inName action:NULL keyEquivalent:@""];
	[inMenu addItem:newMenuItem];
	NSMenu *subMenu = [[NSMenu alloc] initWithTitle:(__bridge NSString *)inName];
	[inMenu setSubmenu:subMenu forItem:newMenuItem];
	return subMenu;
}

@implementation OMCCommandMenu

- (id)init
{
    self = [super init];
	if(self == nil)
		return nil;

	_commandFilePath = @"Command.plist";

    return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if(self == nil)
		return nil;

	_commandFilePath = @"Command.plist";

    return self;
}

- (id)initWithTitle:(NSString *)aTitle
{
	self = [super initWithTitle:aTitle];
	if(self == nil)
		return nil;

	_commandFilePath = @"Command.plist";

    return self;
}

- (void)awakeFromNib
{
	[self populateFromCommandFile];
}

- (void)populateFromCommandFile
{
	//remove all items first (should only be a one placeholder anyway)
	NSInteger itemCount = [self numberOfItems];
	NSInteger i;
	for(i=(itemCount-1); i >= 0 ; i--)
	{
		[self removeItemAtIndex:i];
	}

	// The command file as the runner reads it for the same name (OMCCommandRunner.h)
	CFObj<CFURLRef> commandURL( OMCCopyCommandFileURL((__bridge CFStringRef)self.commandFilePath) );
	OMCMenuModel model;
	if( !OMCBuildCommandsMenuModel(commandURL, model) )
		return;

	for(const OMCMenuItemEntry &entry : model.items)
	{
		NSMenu *subMenu = self;
		for(const CFObj<CFStringRef> &oneName : OMCCopySubmenuNames(entry.submenuPath))
			subMenu = FindOrAddSubmenu(subMenu, oneName);

		if(entry.name == nullptr)
			continue;

		NSString *title = (__bridge NSString *)entry.name.Get();
		OMCMenuItem *newItem = [[OMCMenuItem alloc] initWithTitle:title action:@selector(executeCommand:) keyEquivalent:@""];
		if(newItem != nil)
		{
			[newItem setTarget:self];
			[newItem setCommandID:(__bridge NSString *)entry.commandID.Get()];
			// The name the command is run by when it has no id of its own: the title, localized
			// as it is (OMCCommandsMenuItemCommandToRun)
			[newItem setRepresentedObject:title];
			[subMenu addItem:newItem];
		}
	}
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

- (void)executeCommand:(id)sender
{
	if( sender == nil )
		return;
	
	NSString *myCommandID = nil;
	NSString *myName = nil;//names in this menu might not be command names if localized
	
	if( [sender respondsToSelector:@selector(representedObject)] )
	{
		myName = [sender representedObject];//the item's title, localized when the command is (populateFromCommandFile)
		if(	![myName isKindOfClass:[NSString class]] )
			myName = nil;
	}

	if( [sender respondsToSelector:@selector(commandID)] )
		myCommandID = [sender commandID];
	
	NSString *commandToRun = (__bridge NSString *)OMCCommandsMenuItemCommandToRun((__bridge CFStringRef)myCommandID, (__bridge CFStringRef)myName);
	if( commandToRun == nil )
		return;

	/*OSStatus err = */[OMCCommandExecutor runCommand:commandToRun forCommandFile:self.commandFilePath withContext:NULL useNavDialog:YES allowKeyWindowSubcommand:YES delegate:self];
}

@end

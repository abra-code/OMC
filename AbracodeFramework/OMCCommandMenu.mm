//
//  OMCCommandMenu.m
//  Abracode
//
//  Created by Tomasz Kukielka on 4/6/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import "OMCCommandMenu.h"
#include "OnMyCommand.h"
#import "OMCCommandExecutor.h"
#import "OMCMenuItem.h"
#include "ARefCounted.h"
#include "CFObj.h"
#include "StAEDesc.h"

typedef struct OneSubmenuName
{
	OneSubmenuName(CFStringRef inName, OneSubmenuName *inNext)
		: name(inName, kCFObjRetain), next(inNext)
	{
	}
	
	~OneSubmenuName(void)
	{}

	CFObj<CFStringRef> name;
	AUniquePtr<OneSubmenuName> next;
	
} OneSubmenuName;

OneSubmenuName *
CreateSubmenuNameChain(CFURLRef submenuPath, OneSubmenuName *inChild)
{
	CFObj<CFStringRef> menuName( ::CFURLCopyLastPathComponent(submenuPath) );
	if(	(menuName == NULL) || (::CFStringGetLength(menuName) == 0) || 
		(kCFCompareEqualTo == ::CFStringCompare( menuName, CFSTR("/"), 0)) )
	{
		return inChild;
	}
	
	OneSubmenuName *newHead = new OneSubmenuName(menuName, inChild);
	CFObj<CFURLRef> parentPath( ::CFURLCreateCopyDeletingLastPathComponent( kCFAllocatorDefault, submenuPath ) );
	return CreateSubmenuNameChain(parentPath, newHead);
}

NSMenu *
FindOrAddSubmenu(NSMenu * inMenu, OneSubmenuName *inSubmenu)
{
	if( inMenu == NULL )
		return NULL;
	
	if( (inSubmenu == NULL) || (inSubmenu->name == NULL) )
		return inMenu;

	NSMenu * subMenu = NULL;
	NSInteger itemCount = [inMenu numberOfItems];
	NSInteger i;

	for(i = 0; i < itemCount; i++)
	{
		NSMenuItem *oneItem =  [inMenu itemAtIndex:i];
		if( (oneItem != NULL) && [oneItem hasSubmenu] )
		{
			NSString *menuName = [oneItem title];
			if( (menuName != NULL) && (kCFCompareEqualTo == ::CFStringCompare( (CFStringRef)menuName, inSubmenu->name, 0)) )
			{
				subMenu = [oneItem submenu];
				break;
			}
		}		
	}

	if(subMenu == NULL)
	{//create a new one
		NSMenuItem *newMenuItem = [[NSMenuItem alloc] initWithTitle:(__bridge NSString *)(CFStringRef)inSubmenu->name action:NULL keyEquivalent:@""];
		[inMenu addItem:newMenuItem];

		subMenu = [[NSMenu alloc] initWithTitle:(__bridge NSString *)(CFStringRef)inSubmenu->name];
		[inMenu setSubmenu:subMenu forItem:newMenuItem];
	}
	
	if(inSubmenu->next != nullptr)//recursively dig deeper
		subMenu = FindOrAddSubmenu(subMenu, inSubmenu->next);

	return subMenu;
}


OSStatus
PopulateCommandsMenu(OnMyCommandCM *inPlugin, NSMenu *topMenu)
{
	if( (inPlugin == NULL) || (topMenu == NULL) )
		return paramErr;
	
	CFStringRef defaultMenuName = CFSTR("/");
	CFStringRef rootMenuName = defaultMenuName;

	CommandDescription *commandList = inPlugin->GetCommandList();
	UInt32 commandCount = inPlugin->GetCommandCount();
	if( commandList == NULL )
		return NULL;

	UInt32 oldCommandIndex = inPlugin->GetCurrentCommandIndex();

	for(UInt32 i = 0; i < commandCount; i++)
	{
		if( commandList[i].isSubcommand ) //it is a subcommand, do not add to menu
			continue;

		if( commandList[i].disabled )
			continue;//disabled item, don't add it
		
		inPlugin->SetCurrentCommandIndex(i);
		
		CFBundleRef localizationBundle = NULL;
		if(commandList[i].localizationTableName != NULL)//client wants to be localized
		{
			localizationBundle = inPlugin->GetCurrentCommandExternBundle();
			if(localizationBundle == NULL)
				localizationBundle = CFBundleGetMainBundle();
		}

		CFObj<CFStringRef> submenuPathStr;
		if( commandList[i].submenuName == NULL)
		{
			submenuPathStr.Adopt(defaultMenuName, kCFObjRetain);
		}
		else
		{
			submenuPathStr.Adopt(commandList[i].submenuName, kCFObjRetain);
			CFIndex subLen = ::CFStringGetLength(submenuPathStr);
			UniChar firstChar = 0;
			if(subLen > 0)
				firstChar = ::CFStringGetCharacterAtIndex(submenuPathStr, 0);
			
			//check for ".." which means root level
			if( firstChar == (UniChar)'.' )
			{
				CFIndex theLen = CFStringGetLength(submenuPathStr);
				if( (theLen == 2) && (CFStringGetCharacterAtIndex(submenuPathStr, 1) == (UniChar)'.') )
				{
					submenuPathStr.Adopt(rootMenuName, kCFObjRetain);
					firstChar = (UniChar)'/';
				}
			}
			
			if(firstChar != (UniChar)'/')
			{
				CFMutableStringRef newName = ::CFStringCreateMutable(kCFAllocatorDefault, 0);
				if(newName != NULL)
				{
					::CFStringAppend( newName, CFSTR("/") );
					::CFStringAppend( newName, submenuPathStr );
					submenuPathStr.Adopt(newName);
				}
			}
		}
		
		CFObj<CFURLRef> submenuPath(::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, submenuPathStr, kCFURLPOSIXPathStyle, true));
		AUniquePtr<OneSubmenuName> menuChain( CreateSubmenuNameChain(submenuPath, NULL) );
		NSMenu * subMenu = FindOrAddSubmenu(topMenu, menuChain);
		if( (subMenu != NULL) && (commandList[i].name != NULL) )
		{
            NSString *__strong localizedName = (NSString *)CFBridgingRelease( ::CFStringCreateByCombiningStrings(kCFAllocatorDefault, commandList[i].name, CFSTR("")) );
			if(commandList[i].localizationTableName != NULL)
			{
                localizedName = (NSString*)CFBridgingRelease(::CFCopyLocalizedStringFromTableInBundle((CFStringRef)localizedName, commandList[i].localizationTableName, localizationBundle, ""));
			}

			OMCMenuItem *newItem = [[OMCMenuItem alloc] initWithTitle:localizedName action:@selector(executeCommand:) keyEquivalent:@""];
			if(newItem != NULL)
			{
				[newItem setTarget:topMenu];
                [newItem setCommandID:(__bridge NSString *)(commandList[i].commandID)];
				//CFIndex retCount = CFGetRetainCount((CFStringRef)staticName);
                [newItem setRepresentedObject: localizedName];//the original non-localized name stuffed here. retained object
				//retCount = CFGetRetainCount((CFStringRef)staticName);
				[subMenu addItem:newItem];
			}
		}
	}
	
	inPlugin->SetCurrentCommandIndex(oldCommandIndex);

	return noErr;
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
	//remove all items first (should only be a one placeholder anyway)
	NSInteger itemCount = [self numberOfItems];
	NSInteger i;
	for(i=(itemCount-1); i >= 0 ; i--)
	{
		[self removeItemAtIndex:i];
	}

	//populate menu and register commands
	
	OSStatus error = noErr;
	NSBundle *appBundle = [NSBundle mainBundle];
	NSString *plistPath = [appBundle pathForResource:self.commandFilePath ofType:nil];
	if(plistPath == nil)
		return;

	NSURL *commandURL = [NSURL fileURLWithPath:plistPath];
	if(commandURL == nil)
		return;

    ARefCountedObj<OnMyCommandCM> omcPlugin( new OnMyCommandCM( (__bridge CFURLRef)commandURL ), kARefCountDontRetain );
	omcPlugin->SetCMPluginMode(false);
	StAEDesc contextDesc;//empty context
	error = omcPlugin->ExamineContext(contextDesc, NULL);
	if( error == noErr )
	{
		PopulateCommandsMenu(omcPlugin, self);
		omcPlugin->PostMenuCleanup();//currently doing nothing, just for completeness
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
		myName = [sender representedObject];//the original non-localized name is here
		if(	![myName isKindOfClass:[NSString class]] )
			myName = nil;
	}

	if( [sender respondsToSelector:@selector(commandID)] )
		myCommandID = [sender commandID];
	
	if( (myCommandID == nil) && (myName == nil) )
		return;

	if(myCommandID == nil)
		myCommandID = myName;
	else
	{
		NSUInteger commandIDLength = [myCommandID length];
		if(commandIDLength == 0)
		{
			myCommandID = myName;
		}
        else if( (commandIDLength == 4) && [myCommandID isEqualToString:(__bridge NSString *)kOMCTopCommandID] )//not interesting ID
		{
			myCommandID = myName;
		}
		//else: unique ID for top command, let's use it instead of the name
	}

	if( myCommandID == nil )
		return;

	/*OSStatus err = */[OMCCommandExecutor runCommand:myCommandID forCommandFile:self.commandFilePath withContext:NULL useNavDialog:YES delegate:self];
}

@end

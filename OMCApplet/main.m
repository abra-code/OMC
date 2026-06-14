//
//  main.m
//  OMCApplet
//
//  Created by Tomasz Kukielka on 6/7/08.
//  Copyright Abracode Inc 2008. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Abracode/OMCMainMenuController.h>
#import <Abracode/OMCDropletController.h>

UInt32 GetAbracodeFrameworkVersion(void);

#define MINIMUM_OMC_VERSION 20000

int main(int argc, char *argv[])
{
	if(GetAbracodeFrameworkVersion() < MINIMUM_OMC_VERSION)
		return 1;

	@autoreleasepool
	{
		// Menu bar bootstrap.  Legacy applets name a MainMenu.nib via the
		// NSMainNibFile Info.plist key and let NSApplicationMain load it.
		// Nibless applets (OMC 5.1+) omit NSMainNibFile and build the menu bar
		// programmatically: the standard macOS bar always, plus optional
		// additions/mutations from a MainMenu.json resource when one is present.
		NSString *mainNibName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSMainNibFile"];
		if(mainNibName.length == 0)
		{
			NSApplication *app = [NSApplication sharedApplication];

			// OMCDropletController is the app delegate and the shared
			// NSDocumentController — the same role the nib's instance filled via
			// awakeFromNib.  It runs the applet's default command for New ("Run")
			// and Open…, accepts dropped files and URLs, drives the Open Recent
			// menu, and validates those File items as enabled (its
			// -validateUserInterfaceItem: returns YES for newDocument:/openDocument:).
			// Without it those items have no responder and appear disabled.
			// NSApplication.delegate is weak, so hold a strong reference for the
			// app's lifetime.
			static OMCDropletController *sDropletController = nil;
			sDropletController = [[OMCDropletController alloc] init];
			[app setDelegate:sDropletController];

			// OMCMainMenuController owns the JSON menu bar and the Commands menu.
			// NSMenuItem holds a weak reference to its target, so the controller
			// must outlive the menu — keep a strong reference for the app's lifetime.
			static OMCMainMenuController *sMenuController = nil;
			sMenuController = [[OMCMainMenuController alloc] init];
			[sMenuController installMenuBar];

			// AppKit does not auto-manage a programmatically built Open Recent
			// menu (only nib menus tagged systemMenu="recentDocuments"), so the
			// droplet controller populates it from the recent documents itself.
			[sDropletController installOpenRecentMenu];

			[app run];
			return 0;
		}
	}

	// Legacy path: NSApplicationMain loads MainMenu.nib named by NSMainNibFile.
	return NSApplicationMain(argc, (const char **) argv);
}

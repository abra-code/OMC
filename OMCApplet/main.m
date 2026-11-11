//
//  main.m
//  OMCApplet
//
//  Created by Tomasz Kukielka on 6/7/08.
//  Copyright Abracode Inc 2008. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Abracode/OMCMainMenuController.h>
#import <Abracode/OMCAppletController.h>

UInt32 GetAbracodeFrameworkVersion(void);

#define MINIMUM_OMC_VERSION 20000

int main(int argc, char *argv[])
{
	if(GetAbracodeFrameworkVersion() < MINIMUM_OMC_VERSION)
		return 1;

	@autoreleasepool
	{
		// The menu bar is built in code: the standard macOS bar always, plus optional
		// additions from a MainMenu.json resource. A MainMenu.nib (NSMainNibFile), which
		// applets before 5.1 used, is no longer loaded (removed in 6.0).
		NSApplication *app = [NSApplication sharedApplication];

		// OMCAppletController is the app delegate and the shared NSDocumentController.
		// It runs the applet's default command for New ("Run") and Open..., accepts dropped
		// files and URLs, drives the Open Recent menu, and validates those File items as
		// enabled (its -validateUserInterfaceItem: returns YES for newDocument:/openDocument:).
		// Without it those items have no responder and appear disabled.
		// NSApplication.delegate is weak, so hold a strong reference for the
		// app's lifetime.
		static OMCAppletController *sAppletController = nil;
		sAppletController = [[OMCAppletController alloc] init];
		[app setDelegate:sAppletController];

		// OMCMainMenuController owns the JSON menu bar and the Commands menu.
		// NSMenuItem holds a weak reference to its target, so the controller
		// must outlive the menu - keep a strong reference for the app's lifetime.
		static OMCMainMenuController *sMenuController = nil;
		sMenuController = [[OMCMainMenuController alloc] init];
		[sMenuController installMenuBar];

		// AppKit does not auto-manage a programmatically built Open Recent
		// menu (only nib menus tagged systemMenu="recentDocuments"), so the
		// applet controller populates it from the recent documents itself.
		[sAppletController installOpenRecentMenu];

		[app run];
	}
	return 0;
}

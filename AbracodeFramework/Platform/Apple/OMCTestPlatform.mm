//
//  OMCTestPlatform.mm
//  Abracode
//
//  macOS implementation of Platform/OMCTestPlatform.h.
//

#import <Cocoa/Cocoa.h>
#import "OMCWindowController.h"
#include "OMCTestPlatform.h"

bool
OMCTestPlatformDispatchToKeyWindow(CFStringRef inCommandNameOrId, CFTypeRef inContext)
{
	// The same as the menu's hook in OMCCommandExecutor.mm.
	OMCWindowController *keyWindowController = [OMCWindowController findControllerForKeyWindow];
	if(keyWindowController == nil)
		return false;
	[keyWindowController dispatchCommand:(__bridge NSString *)inCommandNameOrId withContext:inContext];
	return true;
}

bool
OMCTestPlatformHasWindow(CFStringRef inWindowUUID)
{
	if(inWindowUUID == nullptr)
		return false;
	return ([OMCWindowController findControllerByUUID:(__bridge NSString *)inWindowUUID] != nil);
}

bool
OMCTestPlatformDispatchToWindow(CFStringRef inWindowUUID, CFStringRef inCommandNameOrId, CFTypeRef inContext)
{
	if(inWindowUUID == nullptr)
		return false;
	OMCWindowController *controller = [OMCWindowController findControllerByUUID:(__bridge NSString *)inWindowUUID];
	if(controller == nil)
		return false;
	[controller dispatchCommand:(__bridge NSString *)inCommandNameOrId withContext:inContext];
	return true;
}

bool
OMCTestPlatformCloseWindow(CFStringRef inWindowUUID)
{
	if(inWindowUUID == nullptr)
		return false;
	OMCWindowController *controller = [OMCWindowController findControllerByUUID:(__bridge NSString *)inWindowUUID];
	if(controller == nil)
		return false;
	// The close button's way (windowShouldClose:, then windowWillClose: and the end command), without
	// making the window key or activating the application.
	[controller.window performClose:nil];
	return true;
}

void
OMCTestPlatformRequestQuit(void)
{
	[NSApp terminate:nil];
}

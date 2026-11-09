//
//  OMCTestPlatform.mm
//  Abracode
//
//  macOS implementation of Platform/OMCTestPlatform.h.
//

#import <Cocoa/Cocoa.h>
#import "OMCWindowController.h"
#include "OMCTestPlatform.h"
#include "OMCActionUIWindow.h"

bool
OMCTestPlatformDispatchToKeyWindow(CFStringRef inCommandNameOrId, CFTypeRef inContext)
{
	// The same as the menu's hook in OMCCommandExecutor.mm: an ActionUI command window, else a nib dialog
	if(std::shared_ptr<OMCActionUIWindow> keyWindow = OMCActionUIWindow::FindKeyWindow())
	{
		keyWindow->DispatchCommand(inCommandNameOrId, inContext);
		return true;
	}
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
	return (OMCActionUIWindow::Find(inWindowUUID) != nullptr) ||
			([OMCWindowController findControllerByUUID:(__bridge NSString *)inWindowUUID] != nil);
}

bool
OMCTestPlatformDispatchToWindow(CFStringRef inWindowUUID, CFStringRef inCommandNameOrId, CFTypeRef inContext)
{
	if(inWindowUUID == nullptr)
		return false;
	if(std::shared_ptr<OMCActionUIWindow> window = OMCActionUIWindow::Find(inWindowUUID))
	{
		window->DispatchCommand(inCommandNameOrId, inContext);
		return true;
	}
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
	NSWindow *window = nil;
	if(std::shared_ptr<OMCActionUIWindow> actionUIWindow = OMCActionUIWindow::Find(inWindowUUID))
	{
		window = (__bridge NSWindow *)actionUIWindow->GetNativeWindow();
	}
	else
	{
		OMCWindowController *controller = [OMCWindowController findControllerByUUID:(__bridge NSString *)inWindowUUID];
		if(controller == nil)
			return false;
		window = controller.window;
	}
	// The close button's way (windowShouldClose:, then windowWillClose: and the end command), without
	// making the window key or activating the application.
	[window performClose:nil]; // nothing when the command's window has no document
	return true;
}

void
OMCTestPlatformRequestQuit(void)
{
	[NSApp terminate:nil];
}

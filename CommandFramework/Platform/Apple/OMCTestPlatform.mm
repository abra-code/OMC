//
//  OMCTestPlatform.mm
//  Abracode
//
//  macOS implementation of Platform/OMCTestPlatform.h.
//

#import <Cocoa/Cocoa.h>
#include "OMCTestPlatform.h"
#include "OMCActionUIWindow.h"

bool
OMCTestPlatformDispatchToKeyWindow(CFStringRef inCommandNameOrId, CFTypeRef inContext)
{
	// The same as the menu's hook in OMCCommandExecutor.mm: the key window, when it is an ActionUI command window
	std::shared_ptr<OMCActionUIWindow> keyWindow = OMCActionUIWindow::FindKeyWindow();
	if(keyWindow == nullptr)
		return false;
	keyWindow->DispatchCommand(inCommandNameOrId, inContext);
	return true;
}

bool
OMCTestPlatformHasWindow(CFStringRef inWindowUUID)
{
	if(inWindowUUID == nullptr)
		return false;
	return (OMCActionUIWindow::Find(inWindowUUID) != nullptr);
}

bool
OMCTestPlatformDispatchToWindow(CFStringRef inWindowUUID, CFStringRef inCommandNameOrId, CFTypeRef inContext)
{
	if(inWindowUUID == nullptr)
		return false;
	std::shared_ptr<OMCActionUIWindow> window = OMCActionUIWindow::Find(inWindowUUID);
	if(window == nullptr)
		return false;
	window->DispatchCommand(inCommandNameOrId, inContext);
	return true;
}

bool
OMCTestPlatformCloseWindow(CFStringRef inWindowUUID)
{
	if(inWindowUUID == nullptr)
		return false;
	std::shared_ptr<OMCActionUIWindow> actionUIWindow = OMCActionUIWindow::Find(inWindowUUID);
	if(actionUIWindow == nullptr)
		return false;
	NSWindow *window = (__bridge NSWindow *)actionUIWindow->GetNativeWindow();
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

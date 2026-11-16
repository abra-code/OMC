//
//  OMCTestPlatform.cpp (Linux)
//  Abracode
//
//  The Linux implementation of Platform/OMCTestPlatform.h, the platform's part of the
//  integration-test surface (OMCTestHost.h). Finding a command window and running a command as its
//  subcommand go through the portable window registry (OMCActionUIWindow), as on macOS
//  (Platform/Apple/OMCTestPlatform.mm); closing a window and quitting are GTK's and the app shell's.
//  Main thread only.
//

#include "OMCTestPlatform.h"
#include "OMCActionUIWindow.h"
#include "OMCAppShell.h"
#include <gtk/gtk.h>

bool
OMCTestPlatformDispatchToKeyWindow(CFStringRef inCommandNameOrId, CFTypeRef inContext)
{
	// The same as the menu's hook (EntryPoints/Linux/OMCAppletMenu.cpp): the key window, when it is
	// an ActionUI command window
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
	GtkWindow *window = static_cast<GtkWindow *>(actionUIWindow->GetNativeWindow());
	// The close button's way: the close request, which the window host answers as for a click (the
	// end command; a window that may not close stays), without making the window active
	if(window != nullptr)
		gtk_window_close(window);
	return true;
}

void
OMCTestPlatformRequestQuit(void)
{
	OMCQuitThisApp(); // as the app's Quit: app.will.terminate runs
}

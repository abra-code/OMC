//
//  OMCAppShell.cpp (Linux)
//  Abracode
//
//  The calls the engine makes of the app shell (Platform/OMCAppShell.h), on the GApplication of
//  the Linux applet (EntryPoints/Linux/OMCAppletMain.cpp). Main thread.
//

#include "OMCAppShell.h"
#include "Linux/OMCModalLoop.h"
#include "OMCTestHost.h"
#include "ACFString.h"
#include "OMCLog.h"
#include <gtk/gtk.h>
#include <string>

void
OMCActivateThisApp(void)
{
	// GTK cannot raise an app as such: its most recently active window comes to the front
	GApplication *app = g_application_get_default();
	if(!GTK_IS_APPLICATION(app))
		return;
	GtkWindow *window = gtk_application_get_active_window(GTK_APPLICATION(app));
	if(window != nullptr)
		gtk_window_present(window);
}

void
OMCQuitThisApp(void)
{
	// As the app's Quit: the shutdown signal runs app.will.terminate; a blocking window's modal run
	// or a waiting alert ends too, or the application's loop would never get control back
	GApplication *app = g_application_get_default();
	if(app != nullptr)
		g_application_quit(app);
	OMCEndModalLoops();
}

void
OMCNoteRecentDocument(CFURLRef fileURL)
{
	if(fileURL == nullptr)
		return;
	// A test launch works on the test's own files, deleted when it ends: as on macOS
	// (OMCNoteRecentDocumentURL), they are not added to the user's recent files
	if(OMCTestHostIsActive())
	{
		OMCTestHostNoteSkippedRecentDocument();
		return;
	}
	std::string uri = ACFStringToUTF8(CFURLGetString(fileURL));
	if(uri.empty())
		return;
	// The desktop's recent files list (recently-used.xbel), which Open Recent and file choosers show
	GtkRecentManager *manager = gtk_recent_manager_get_default();
	if(manager != nullptr)
		(void)gtk_recent_manager_add_item(manager, uri.c_str());
}

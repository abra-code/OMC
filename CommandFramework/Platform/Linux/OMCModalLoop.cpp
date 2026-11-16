//
//  OMCModalLoop.cpp
//  Abracode
//
//  See OMCModalLoop.h. Linux only.
//

#include "OMCModalLoop.h"
#include <algorithm>
#include <vector>

namespace
{

// The loops OMCRunModalLoop is running, innermost last
std::vector<GMainLoop *> sRunningLoops;

} // namespace

void
OMCRunModalLoop(GMainLoop *inLoop)
{
	if(inLoop == nullptr)
		return;
	sRunningLoops.push_back(inLoop);
	g_main_loop_run(inLoop);
	sRunningLoops.erase(std::remove(sRunningLoops.begin(), sRunningLoops.end(), inLoop), sRunningLoops.end());
}

void
OMCEndModalLoops()
{
	for(GMainLoop *loop : sRunningLoops)
	{
		if(g_main_loop_is_running(loop))
			g_main_loop_quit(loop);
	}
}

GtkWindow *
OMCModalParentWindow()
{
	GApplication *app = g_application_get_default();
	if(!GTK_IS_APPLICATION(app))
		return nullptr;
	// GTK keeps a hidden window as the active one; a dialog over it would not show
	GtkWindow *window = gtk_application_get_active_window(GTK_APPLICATION(app));
	if((window != nullptr) && gtk_widget_get_visible(GTK_WIDGET(window)))
		return window;
	for(GList *item = gtk_application_get_windows(GTK_APPLICATION(app)); item != nullptr; item = item->next)
	{
		if(gtk_widget_get_visible(GTK_WIDGET(item->data)))
			return GTK_WINDOW(item->data);
	}
	return nullptr;
}

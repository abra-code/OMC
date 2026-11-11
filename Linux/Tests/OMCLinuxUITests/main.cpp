//
//  OMCLinuxUITests/main.cpp
//  Abracode
//
//  Linux checks of the platform UI that a person answers: the alerts and notices of
//  Platform/Linux/OMCPlatformAlerts.cpp. The program runs its own AdwApplication in the desktop
//  session and answers each alert itself, as a person would: it finds the dialog among the
//  application's windows and clicks a button (or closes it), from a timer set before the alert,
//  which blocks. It can save what the dialogs look like: OMCLinuxUITests [folder for PNG files].
//
//  Needs a desktop session (on the agent-vm box: XDG_RUNTIME_DIR, WAYLAND_DISPLAY,
//  DBUS_SESSION_BUS_ADDRESS of its GNOME session). Exit status: 0 all passed, 1 a check failed.
//

#include "OMCAlerts.h"
#include "Linux/OMCModalLoop.h"
#include <adwaita.h>
#include <cstdio>
#include <cstring>
#include <functional>
#include <initializer_list>
#include <string>
#include <vector>

namespace
{

int sPassed = 0;
int sFailed = 0;
std::string sPNGFolder;

void
Check(const char *inName, bool inOK, const std::string &inDetail = std::string())
{
	if(inOK)
	{
		sPassed++;
		printf("ok   %s\n", inName);
	}
	else
	{
		sFailed++;
		printf("FAIL %s%s%s\n", inName, inDetail.empty() ? "" : ": ", inDetail.c_str());
	}
	fflush(stdout);
}

// The first widget of inType at or under inWidget
GtkWidget *
FindWidget(GtkWidget *inWidget, GType inType)
{
	if(inWidget == nullptr)
		return nullptr;
	if(g_type_is_a(G_OBJECT_TYPE(inWidget), inType))
		return inWidget;
	for(GtkWidget *child = gtk_widget_get_first_child(inWidget); child != nullptr; child = gtk_widget_get_next_sibling(child))
	{
		GtkWidget *found = FindWidget(child, inType);
		if(found != nullptr)
			return found;
	}
	return nullptr;
}

// The alert dialog shown now, in any of the process's windows
GtkWidget *
FindAlertDialog()
{
	GListModel *toplevels = gtk_window_get_toplevels();
	guint count = g_list_model_get_n_items(toplevels);
	for(guint i = 0; i < count; i++)
	{
		GtkWidget *window = GTK_WIDGET(g_list_model_get_item(toplevels, i));
		GtkWidget *found = gtk_widget_get_visible(window) ? FindWidget(window, ADW_TYPE_ALERT_DIALOG) : nullptr;
		g_object_unref(window);
		if(found != nullptr)
			return found;
	}
	return nullptr;
}

// The button of inDialog titled inTitle
GtkWidget *
FindButton(GtkWidget *inWidget, const char *inTitle)
{
	if(inWidget == nullptr)
		return nullptr;
	if(GTK_IS_BUTTON(inWidget))
	{
		const char *label = gtk_button_get_label(GTK_BUTTON(inWidget));
		if((label != nullptr) && (strcmp(label, inTitle) == 0))
			return inWidget;
	}
	for(GtkWidget *child = gtk_widget_get_first_child(inWidget); child != nullptr; child = gtk_widget_get_next_sibling(child))
	{
		GtkWidget *found = FindButton(child, inTitle);
		if(found != nullptr)
			return found;
	}
	return nullptr;
}

// Saves the window inWidget is in as <folder>/<inName>.png, when a folder was given
void
Capture(GtkWidget *inWidget, const char *inName)
{
	if(sPNGFolder.empty() || (inWidget == nullptr))
		return;
	GtkWidget *window = GTK_WIDGET(gtk_widget_get_root(inWidget));
	int width = gtk_widget_get_width(window);
	int height = gtk_widget_get_height(window);
	GdkPaintable *paintable = gtk_widget_paintable_new(window);
	GtkSnapshot *snapshot = gtk_snapshot_new();
	gdk_paintable_snapshot(paintable, snapshot, width, height);
	GskRenderNode *node = gtk_snapshot_free_to_node(snapshot);
	if(node != nullptr)
	{
		GskRenderer *renderer = gtk_native_get_renderer(GTK_NATIVE(window));
		graphene_rect_t bounds = GRAPHENE_RECT_INIT(0, 0, (float)width, (float)height);
		GdkTexture *texture = gsk_renderer_render_texture(renderer, node, &bounds);
		std::string path = sPNGFolder + "/" + inName + ".png";
		(void)gdk_texture_save_to_png(texture, path.c_str());
		g_object_unref(texture);
		gsk_render_node_unref(node);
	}
	g_object_unref(paintable);
}

// Runs inAction after inMilliseconds, from the main loop (the alert's nested loop runs it)
guint
After(guint inMilliseconds, std::function<void()> inAction)
{
	auto *action = new std::function<void()>(std::move(inAction));
	return g_timeout_add_full(G_PRIORITY_DEFAULT, inMilliseconds, [](gpointer inData) -> gboolean {
		(*static_cast<std::function<void()> *>(inData))();
		return G_SOURCE_REMOVE;
	}, action, [](gpointer inData) { delete static_cast<std::function<void()> *>(inData); });
}

// Lets the main loop run for a while (a dialog's animation, its close)
void
Pump(guint inMilliseconds)
{
	gint64 end = g_get_monotonic_time() + (gint64)inMilliseconds * 1000;
	while(g_get_monotonic_time() < end)
		g_main_context_iteration(nullptr, FALSE);
}

// How inButtons (the other, alternate and default buttons that are there, in that order) are laid
// out: "left to right" side by side in that order, "default on top" stacked from the default up
std::string
ButtonOrder(std::initializer_list<GtkWidget *> inButtons)
{
	GtkWidget *root = nullptr;
	std::vector<graphene_point_t> points;
	for(GtkWidget *button : inButtons)
	{
		if(button == nullptr)
			return "a button is missing";
		if(root == nullptr)
			root = GTK_WIDGET(gtk_widget_get_root(button));
		graphene_point_t origin = GRAPHENE_POINT_INIT(0, 0), point = origin;
		(void)gtk_widget_compute_point(button, root, &origin, &point);
		points.push_back(point);
	}
	bool leftToRight = true, defaultOnTop = true;
	for(size_t i = 1; i < points.size(); i++)
	{
		leftToRight = leftToRight && (points[i - 1].x < points[i].x) && (points[i - 1].y == points[i].y);
		defaultOnTop = defaultOnTop && (points[i - 1].y > points[i].y) && (points[i - 1].x == points[i].x);
	}
	return leftToRight ? "left to right" : (defaultOnTop ? "default on top" : "other order");
}

const char *
ResponseName(OMCAlertResponse inResponse)
{
	switch(inResponse)
	{
		case kOMCAlertDefaultResponse: return "default";
		case kOMCAlertAlternateResponse: return "alternate";
		case kOMCAlertOtherResponse: return "other";
		default: return "none";
	}
}

void
RunChecks(GApplication *inApp)
{
	{
		// No window: the alert is a window of its own; the other button answers
		bool found = false;
		std::string order;
		After(800, [&] {
			GtkWidget *dialog = FindAlertDialog();
			found = (dialog != nullptr);
			Capture(dialog, "alert-standalone");
			GtkWidget *other = FindButton(dialog, "Other");
			order = ButtonOrder({other, FindButton(dialog, "Cancel"), FindButton(dialog, "OK")});
			if(other != nullptr)
				gtk_widget_activate(other);
			else
				OMCEndModalLoops(); // not found: the alert would wait forever (the checks fail instead)
		});
		OMCAlertResponse response = OMCPlatformShowAlert(kOMCAlertLevelStop, CFSTR("Delete the file?"), CFSTR("It cannot be undone."),
														CFSTR("OK"), CFSTR("Cancel"), CFSTR("Other"));
		Check("an alert with no window shows as a window of its own", found);
		// three buttons do not fit side by side in an alert of its own: libadwaita stacks them
		Check("its buttons are other, alternate, default, in an order", (order == "left to right") || (order == "default on top"), order);
		Check("clicking the other button answers other", response == kOMCAlertOtherResponse, ResponseName(response));
		Pump(400);
		Check("and the alert is gone", FindAlertDialog() == nullptr);
	}

	GtkWidget *window = adw_application_window_new(GTK_APPLICATION(inApp));
	gtk_window_set_title(GTK_WINDOW(window), "OMC Linux UI tests");
	gtk_window_set_default_size(GTK_WINDOW(window), 480, 320);
	adw_application_window_set_content(ADW_APPLICATION_WINDOW(window), gtk_label_new("The applet's window"));
	gtk_window_present(GTK_WINDOW(window));
	Pump(500);

	{
		// Over the application's window; the default button answers
		bool overWindow = false;
		std::string order;
		After(800, [&] {
			GtkWidget *dialog = FindAlertDialog();
			overWindow = (dialog != nullptr) && (GTK_WIDGET(gtk_widget_get_root(dialog)) == window);
			Capture(dialog, "alert-over-window");
			GtkWidget *ok = FindButton(dialog, "Proceed");
			order = ButtonOrder({FindButton(dialog, "Cancel"), ok});
			if(ok != nullptr)
				gtk_widget_activate(ok);
			else
				OMCEndModalLoops();
		});
		OMCAlertResponse response = OMCPlatformShowAlert(kOMCAlertLevelCaution, CFSTR("Greet everyone?"), CFSTR("A message for the applet's window"),
														CFSTR("Proceed"), CFSTR("Cancel"), nullptr);
		Check("with a window, the alert shows over it", overWindow);
		Check("two buttons are side by side, the alternate left of the default", order == "left to right", order);
		Check("clicking the default button answers default", response == kOMCAlertDefaultResponse, ResponseName(response));
	}

	{
		// Closed (Escape): the alternate answers
		After(800, [&] {
			GtkWidget *dialog = FindAlertDialog();
			if(dialog != nullptr)
				(void)adw_dialog_close(ADW_DIALOG(dialog));
			else
				OMCEndModalLoops();
		});
		OMCAlertResponse response = OMCPlatformShowAlert(kOMCAlertLevelNote, CFSTR("Closed"), nullptr, CFSTR("OK"), CFSTR("Cancel"), nullptr);
		Check("closing an alert with a Cancel button answers alternate", response == kOMCAlertAlternateResponse, ResponseName(response));
	}

	{
		// Closed with only a default button: the default answers
		After(800, [&] {
			GtkWidget *dialog = FindAlertDialog();
			if(dialog != nullptr)
				(void)adw_dialog_close(ADW_DIALOG(dialog));
			else
				OMCEndModalLoops();
		});
		OMCAlertResponse response = OMCPlatformShowAlert(kOMCAlertLevelNote, CFSTR("Only OK"), nullptr, CFSTR("OK"), nullptr, nullptr);
		Check("closing an alert with only a default button answers default", response == kOMCAlertDefaultResponse, ResponseName(response));
	}

	{
		// A quit ends the wait: no answer, and the alert goes
		After(800, [] { OMCEndModalLoops(); });
		OMCAlertResponse response = OMCPlatformShowAlert(kOMCAlertLevelStop, CFSTR("Quitting"), nullptr, CFSTR("OK"), CFSTR("Cancel"), nullptr);
		Check("a quit while an alert waits ends it with no answer", response == kOMCAlertNoResponse, ResponseName(response));
		Pump(400);
		Check("and the alert is gone", FindAlertDialog() == nullptr);
	}

	{
		// A notice does not wait, and stays until its button
		gint64 before = g_get_monotonic_time();
		OMCPlatformShowNotice(CFSTR("Done"), CFSTR("The command finished."), CFSTR("OK"), nullptr);
		gint64 elapsed = g_get_monotonic_time() - before;
		Check("a notice returns at once", elapsed < 500 * 1000, std::to_string(elapsed / 1000) + " ms");
		Pump(800);
		GtkWidget *dialog = FindAlertDialog();
		Check("and shows until it is answered", dialog != nullptr);
		Capture(dialog, "notice");
		GtkWidget *ok = FindButton(dialog, "OK");
		if(ok != nullptr)
			gtk_widget_activate(ok);
		Pump(400);
		Check("then its button closes it", FindAlertDialog() == nullptr);
	}

	{
		// The window goes while an alert waits over it (a script closes it): the wait ends, no answer
		After(800, [&] { gtk_window_destroy(GTK_WINDOW(window)); });
		bool stuck = false;
		guint safety = After(5000, [&] { stuck = true; OMCEndModalLoops(); });
		OMCAlertResponse response = OMCPlatformShowAlert(kOMCAlertLevelNote, CFSTR("Window goes"), nullptr, CFSTR("OK"), CFSTR("Cancel"), nullptr);
		if(!stuck)
			g_source_remove(safety);
		Check("when its window goes, an alert ends with no answer", !stuck && (response == kOMCAlertNoResponse),
				stuck ? "still waiting after 5 s" : ResponseName(response));
	}
}

} // namespace

int
main(int argc, char *argv[])
{
	if(argc > 1)
		sPNGFolder = argv[1];
	AdwApplication *app = adw_application_new("com.abracode.omc.linuxuitests", G_APPLICATION_NON_UNIQUE);
	g_signal_connect(app, "activate", G_CALLBACK(+[](GApplication *inApp, gpointer) {
		g_application_hold(inApp);
		RunChecks(inApp);
		g_application_release(inApp);
		g_application_quit(inApp);
	}), nullptr);
	int status = g_application_run(G_APPLICATION(app), 0, nullptr);
	g_object_unref(app);
	printf("%d passed, %d failed\n", sPassed, sFailed);
	return ((status == 0) && (sFailed == 0)) ? 0 : 1;
}

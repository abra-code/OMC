//
//  OMCLinuxUITests/main.cpp
//  Abracode
//
//  Linux checks of the platform UI that a person answers: the alerts and notices of
//  Platform/Linux/OMCPlatformAlerts.cpp and the file panels of OMCPlatformFilePanels.cpp. The
//  program runs its own AdwApplication in the desktop session and answers each one itself, as a
//  person would: it finds the dialog among the application's windows and clicks a button (or
//  closes it, or picks files in GTK's file chooser), from a timer set before the call, which
//  blocks. It can save what the dialogs look like: OMCLinuxUITests [folder for PNG files].
//  The panels: GTK shows the desktop's file chooser through its portal, in another process, which
//  no check can click. So the program turns the portals off for itself (GDK_DEBUG=no-portals, read
//  when GTK starts) and drives GTK's own chooser. OMCLinuxUITests --portals keeps them and checks
//  only that a quit ends a panel waiting in the portal.
//
//  Needs a desktop session (on the agent-vm box: XDG_RUNTIME_DIR, WAYLAND_DISPLAY,
//  DBUS_SESSION_BUS_ADDRESS of its GNOME session). Exit status: 0 all passed, 1 a check failed.
//

#include "OMCAlerts.h"
#include "OMCFilePanels.h"
#include "CFObj.h"
#include "Linux/OMCModalLoop.h"
#include <adwaita.h>
#include <glib/gstdio.h>
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

#pragma mark - File panels

// GtkFileDialog shows GTK's file chooser, GtkFileChooserDialog, which GTK 4.10 deprecated for
// applications to make themselves; a test drives it through those calls
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

// The file chooser shown now, among the process's windows
GtkWidget *
FindFileChooser()
{
	GListModel *toplevels = gtk_window_get_toplevels();
	guint count = g_list_model_get_n_items(toplevels);
	GtkWidget *found = nullptr;
	for(guint i = 0; (i < count) && (found == nullptr); i++)
	{
		GtkWidget *window = GTK_WIDGET(g_list_model_get_item(toplevels, i));
		if(GTK_IS_FILE_CHOOSER(window) && gtk_widget_get_visible(window))
			found = window;
		g_object_unref(window);
	}
	return found;
}

void
ChooseFile(GtkWidget *inChooser, const std::string &inPath)
{
	GFile *file = g_file_new_for_path(inPath.c_str());
	(void)gtk_file_chooser_set_file(GTK_FILE_CHOOSER(inChooser), file, nullptr);
	g_object_unref(file);
}

std::string
ChooserFolder(GtkWidget *inChooser)
{
	GFile *folder = gtk_file_chooser_get_current_folder(GTK_FILE_CHOOSER(inChooser));
	char *path = (folder != nullptr) ? g_file_get_path(folder) : nullptr;
	std::string result = (path != nullptr) ? path : "";
	g_free(path);
	if(folder != nullptr)
		g_object_unref(folder);
	return result;
}

std::string
URLPath(CFURLRef inURL)
{
	char path[4096];
	if((inURL == nullptr) || !CFURLGetFileSystemRepresentation(inURL, true, (UInt8 *)path, sizeof(path)))
		return "(none)";
	return path;
}

CFStringRef
CFString(const std::string &inText)
{
	return CFStringCreateWithCString(kCFAllocatorDefault, inText.c_str(), kCFStringEncodingUTF8);
}

void
WriteFile(const std::string &inPath)
{
	(void)g_file_set_contents(inPath.c_str(), "x", 1, nullptr);
}

// The panel shows; at its timer the test looks at it, then answers after a while (the chooser
// loads the folder asynchronously)
void
AnswerPanel(std::function<void(GtkWidget *)> inLook, std::function<void(GtkWidget *)> inAnswer)
{
	After(1000, [inLook, inAnswer] {
		GtkWidget *chooser = FindFileChooser();
		if(chooser == nullptr)
		{
			OMCEndModalLoops(); // not found: the panel would wait forever (the checks fail instead)
			return;
		}
		inLook(chooser);
		After(600, [chooser, inAnswer] {
			if(FindFileChooser() != chooser)
			{
				OMCEndModalLoops();
				return;
			}
			inAnswer(chooser);
		});
	});
}

void
Respond(GtkWidget *inChooser, int inResponse)
{
	gtk_dialog_response(GTK_DIALOG(inChooser), inResponse);
}

void
RunPanelChecks(GApplication *inApp)
{
	char *made = g_dir_make_tmp("omc-ui-test-XXXXXX", nullptr);
	if(made == nullptr)
	{
		Check("a folder for the panels' files", false);
		return;
	}
	std::string folder = made;
	g_free(made);
	std::string image = folder + "/picture.png";
	std::string text = folder + "/notes.txt";
	std::string subfolder = folder + "/Projects";
	WriteFile(image);
	WriteFile(text);
	(void)g_mkdir(subfolder.c_str(), 0755);
	CFObj<CFStringRef> folderString(CFString(folder));

	GtkWidget *window = adw_application_window_new(GTK_APPLICATION(inApp));
	gtk_window_set_title(GTK_WINDOW(window), "OMC Linux UI tests: panels");
	gtk_window_set_default_size(GTK_WINDOW(window), 480, 320);
	adw_application_window_set_content(ADW_APPLICATION_WINDOW(window), gtk_label_new("The applet's window"));
	gtk_window_present(GTK_WINDOW(window));
	Pump(500);

	{
		// Open one file: the message is the title, the prompt the accept button, the folder and the
		// allowed types are set, over the window
		std::string title, startFolder, filterName;
		bool hasPrompt = false, overWindow = false, single = false;
		AnswerPanel([&](GtkWidget *inChooser) {
			const char *t = gtk_window_get_title(GTK_WINDOW(inChooser));
			title = (t != nullptr) ? t : "";
			hasPrompt = (FindButton(inChooser, "Convert") != nullptr);
			overWindow = (gtk_window_get_transient_for(GTK_WINDOW(inChooser)) == GTK_WINDOW(window));
			single = !gtk_file_chooser_get_select_multiple(GTK_FILE_CHOOSER(inChooser)) &&
					(gtk_file_chooser_get_action(GTK_FILE_CHOOSER(inChooser)) == GTK_FILE_CHOOSER_ACTION_OPEN);
			startFolder = ChooserFolder(inChooser);
			GtkFileFilter *filter = gtk_file_chooser_get_filter(GTK_FILE_CHOOSER(inChooser));
			const char *name = (filter != nullptr) ? gtk_file_filter_get_name(filter) : nullptr;
			filterName = (name != nullptr) ? name : "(none)";
			Capture(inChooser, "open-panel");
			ChooseFile(inChooser, image);
		}, [](GtkWidget *inChooser) { Respond(inChooser, GTK_RESPONSE_ACCEPT); });
		const void *types[] = { CFSTR("public.image"), CFSTR("com.example.unknown"), CFSTR("public.png") };
		CFObj<CFArrayRef> allowed(CFArrayCreate(kCFAllocatorDefault, types, 3, &kCFTypeArrayCallBacks));
		CFObj<CFArrayRef> urls(OMCPlatformRunOpenPanel(CFSTR("Panel Applet"), CFSTR("Choose a picture to convert"), nullptr, folderString,
														nullptr, CFSTR("Convert"), allowed, kOMCFilePanelCanChooseFiles));
		Check("an open panel's title is the message", title == "Choose a picture to convert", title);
		Check("its accept button is the prompt", hasPrompt);
		Check("it shows over the window", overWindow);
		Check("it chooses one file", single);
		Check("it starts in the default folder", startFolder == folder, startFolder);
		Check("the allowed types are its filter (an unknown one adds nothing)", filterName == "Images, PNG image", filterName);
		bool one = (urls != nullptr) && (CFArrayGetCount(urls) == 1);
		std::string path = one ? URLPath((CFURLRef)CFArrayGetValueAtIndex(urls, 0)) : "(none)";
		Check("the chosen file comes back as its URL", path == image, path);
		Pump(400);
		Check("and the panel is gone", FindFileChooser() == nullptr);
	}

	{
		// Several files allowed; canceled: no answer
		bool multiple = false, noFilter = false;
		AnswerPanel([&](GtkWidget *inChooser) {
			multiple = gtk_file_chooser_get_select_multiple(GTK_FILE_CHOOSER(inChooser));
			noFilter = (gtk_file_chooser_get_filter(GTK_FILE_CHOOSER(inChooser)) == nullptr);
		}, [](GtkWidget *inChooser) { Respond(inChooser, GTK_RESPONSE_CANCEL); });
		const void *types[] = { CFSTR("public.data") };
		CFObj<CFArrayRef> allowed(CFArrayCreate(kCFAllocatorDefault, types, 1, &kCFTypeArrayCallBacks));
		CFObj<CFArrayRef> urls(OMCPlatformRunOpenPanel(CFSTR("Panel Applet"), nullptr, nullptr, folderString, nullptr, nullptr, allowed,
														kOMCFilePanelCanChooseFiles | kOMCFilePanelAllowMultipleItems));
		Check("with multiple items allowed, the panel chooses several", multiple);
		Check("a type that allows any file sets no filter", noFilter);
		Check("canceling an open panel answers nothing", urls == nullptr);
	}

	{
		// Folders only: a folder comes back as a directory URL
		bool folderAction = false;
		AnswerPanel([&](GtkWidget *inChooser) {
			folderAction = (gtk_file_chooser_get_action(GTK_FILE_CHOOSER(inChooser)) == GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER);
			ChooseFile(inChooser, subfolder);
		}, [](GtkWidget *inChooser) { Respond(inChooser, GTK_RESPONSE_ACCEPT); });
		CFObj<CFArrayRef> urls(OMCPlatformRunOpenPanel(CFSTR("Panel Applet"), CFSTR("Choose a folder"), nullptr, folderString, nullptr, nullptr,
														nullptr, kOMCFilePanelCanChooseDirectories));
		Check("with directories only, the panel chooses a folder", folderAction);
		CFURLRef url = ((urls != nullptr) && (CFArrayGetCount(urls) == 1)) ? (CFURLRef)CFArrayGetValueAtIndex(urls, 0) : nullptr;
		std::string path = URLPath(url);
		Check("the chosen folder comes back as a directory URL", (path == subfolder) && (url != nullptr) && CFURLHasDirectoryPath(url), path);
	}

	{
		// Save: the default name, the name typed, the folder
		std::string startName;
		bool saveAction = false;
		AnswerPanel([&](GtkWidget *inChooser) {
			saveAction = (gtk_file_chooser_get_action(GTK_FILE_CHOOSER(inChooser)) == GTK_FILE_CHOOSER_ACTION_SAVE);
			char *name = gtk_file_chooser_get_current_name(GTK_FILE_CHOOSER(inChooser));
			startName = (name != nullptr) ? name : "";
			g_free(name);
			Capture(inChooser, "save-panel");
			gtk_file_chooser_set_current_name(GTK_FILE_CHOOSER(inChooser), "Report final.txt");
		}, [](GtkWidget *inChooser) { Respond(inChooser, GTK_RESPONSE_ACCEPT); });
		CFObj<CFURLRef> url(OMCPlatformRunSavePanel(CFSTR("Panel Applet"), CFSTR("Save the report"), CFSTR("Report.txt"), folderString,
													nullptr, CFSTR("Save"), nullptr, 0));
		Check("a save panel saves", saveAction);
		Check("its name field starts with the default name", startName == "Report.txt", startName);
		std::string path = URLPath(url);
		Check("the saved file's URL is the folder and the name typed", path == folder + "/Report final.txt", path);
	}

	{
		// A quit while a panel waits: no answer, and the panel goes
		After(1000, [] { OMCEndModalLoops(); });
		CFObj<CFURLRef> url(OMCPlatformRunSavePanel(CFSTR("Panel Applet"), nullptr, CFSTR("Quit.txt"), folderString, nullptr, nullptr, nullptr, 0));
		Check("a quit while a panel waits ends it with no answer", url == nullptr);
		Pump(600);
		Check("and the panel is gone", FindFileChooser() == nullptr);
	}

	gtk_window_destroy(GTK_WINDOW(window));
	Pump(200);
	(void)remove(image.c_str());
	(void)remove(text.c_str());
	(void)g_rmdir(subfolder.c_str());
	(void)g_rmdir(folder.c_str());
}

// With the portals: a panel shows in the desktop's chooser; a quit ends it
void
RunPortalChecks()
{
	bool inProcess = true;
	After(1500, [&] {
		inProcess = (FindFileChooser() != nullptr);
		OMCEndModalLoops();
	});
	gint64 before = g_get_monotonic_time();
	CFObj<CFURLRef> url(OMCPlatformRunSavePanel(CFSTR("Panel Applet"), CFSTR("Quit while the portal shows this"), CFSTR("Quit.txt"),
												nullptr, nullptr, nullptr, nullptr, 0));
	gint64 elapsed = (g_get_monotonic_time() - before) / 1000;
	Check("a portal panel waits for its answer", elapsed >= 1400, std::to_string(elapsed) + " ms");
	Check("in the portal's chooser, not GTK's own in this process", !inProcess);
	Check("and a quit ends it with no answer", url == nullptr);
}

#pragma GCC diagnostic pop

} // namespace

int
main(int argc, char *argv[])
{
	static bool sPortals = false;
	for(int i = 1; i < argc; i++)
	{
		if(strcmp(argv[i], "--portals") == 0)
			sPortals = true;
		else
			sPNGFolder = argv[i];
	}
	if(!sPortals)
	{
		// Before GTK starts, which reads it: GTK's own file chooser, in this process
		const char *debug = g_getenv("GDK_DEBUG");
		std::string value = ((debug != nullptr) && (debug[0] != 0)) ? std::string(debug) + ",no-portals" : "no-portals";
		g_setenv("GDK_DEBUG", value.c_str(), TRUE);
	}
	AdwApplication *app = adw_application_new("com.abracode.omc.linuxuitests", G_APPLICATION_NON_UNIQUE);
	g_signal_connect(app, "activate", G_CALLBACK(+[](GApplication *inApp, gpointer) {
		g_application_hold(inApp);
		if(sPortals)
			RunPortalChecks();
		else
		{
			RunChecks(inApp);
			RunPanelChecks(inApp);
		}
		g_application_release(inApp);
		g_application_quit(inApp);
	}), nullptr);
	int status = g_application_run(G_APPLICATION(app), 0, nullptr);
	g_object_unref(app);
	printf("%d passed, %d failed\n", sPassed, sFailed);
	return ((status == 0) && (sFailed == 0)) ? 0 : 1;
}

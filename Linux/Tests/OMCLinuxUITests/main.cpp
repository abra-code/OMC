//
//  OMCLinuxUITests/main.cpp
//  Abracode
//
//  Linux checks of the platform UI that a person answers: the alerts and notices of
//  Platform/Linux/OMCPlatformAlerts.cpp and the file panels of OMCPlatformFilePanels.cpp, and the
//  applet's menu (EntryPoints/Linux/OMCAppletMenu.cpp), chosen as a click would, and the
//  clipboard and host info (OMCClipboard.cpp, OMCHostInfo.cpp), forgetting a closed window's
//  ActionUI model (OMCActionUIModels.cpp), and the ActionUI add-ons (OMCActionUIAddOns.cpp). The
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
#include "OMCAppletMenu.h"
#include "OMCClipboard.h"
#include "OMCActionUIModels.h"
#include "OMCActionUIAddOns.h"
#include "OMCHostInfo.h"
#include "OMCConstants.h"
#include "ACFString.h"
#include "ACFJSON.h"
#include "ActionUIC.h"
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

#pragma mark - The applet's menu

// The menu as text: a section as "[...]", a submenu as "Title>[...]", an item as its label
std::string
MenuOutline(GMenuModel *inModel)
{
	std::string text;
	int count = g_menu_model_get_n_items(inModel);
	for(int i = 0; i < count; i++)
	{
		if(!text.empty())
			text += ", ";
		char *label = nullptr;
		(void)g_menu_model_get_item_attribute(inModel, i, "label", "s", &label);
		GMenuModel *section = g_menu_model_get_item_link(inModel, i, "section");
		GMenuModel *submenu = g_menu_model_get_item_link(inModel, i, "submenu");
		if(section != nullptr)
			text += "[" + MenuOutline(section) + "]";
		else if(submenu != nullptr)
			text += std::string((label != nullptr) ? label : "?") + ">[" + MenuOutline(submenu) + "]";
		else
			text += (label != nullptr) ? label : "?";
		if(section != nullptr)
			g_object_unref(section);
		if(submenu != nullptr)
			g_object_unref(submenu);
		g_free(label);
	}
	return text;
}

// The action (without "app.") of the item a path of labels leads to, through sections and submenus
std::string
MenuItemAction(GMenuModel *inModel, std::vector<std::string> inPath)
{
	if(inPath.empty())
		return "";
	int count = g_menu_model_get_n_items(inModel);
	for(int i = 0; i < count; i++)
	{
		std::string found;
		GMenuModel *section = g_menu_model_get_item_link(inModel, i, "section");
		if(section != nullptr)
		{
			found = MenuItemAction(section, inPath);
			g_object_unref(section);
			if(!found.empty())
				return found;
			continue;
		}
		char *label = nullptr;
		(void)g_menu_model_get_item_attribute(inModel, i, "label", "s", &label);
		bool matches = (label != nullptr) && (inPath.front() == label);
		g_free(label);
		if(!matches)
			continue;
		GMenuModel *submenu = g_menu_model_get_item_link(inModel, i, "submenu");
		if(submenu != nullptr)
		{
			found = MenuItemAction(submenu, std::vector<std::string>(inPath.begin() + 1, inPath.end()));
			g_object_unref(submenu);
			return found;
		}
		if(inPath.size() != 1)
			return "";
		char *action = nullptr;
		(void)g_menu_model_get_item_attribute(inModel, i, "action", "s", &action);
		found = (action != nullptr) ? action : "";
		g_free(action);
		return (found.compare(0, 4, "app.") == 0) ? found.substr(4) : found;
	}
	return "";
}

std::string
Accelerator(GApplication *inApp, const std::string &inAction)
{
	char **accels = gtk_application_get_accels_for_action(GTK_APPLICATION(inApp), ("app." + inAction).c_str());
	std::string first = ((accels != nullptr) && (accels[0] != nullptr)) ? accels[0] : "(none)";
	g_strfreev(accels);
	return first;
}

// Waits (running the main loop) until inPath exists, at most 5 s
bool
WaitForFile(const std::string &inPath)
{
	gint64 end = g_get_monotonic_time() + 5 * G_USEC_PER_SEC;
	while(g_get_monotonic_time() < end)
	{
		if(g_file_test(inPath.c_str(), G_FILE_TEST_EXISTS))
			return true;
		g_main_context_iteration(nullptr, FALSE);
		g_usleep(10 * 1000);
	}
	return false;
}

std::string Joined(const std::vector<std::string> &inItems); // below, with the add-on checks

int sMainCommandRuns = 0;
int sQuits = 0;
std::vector<std::string> sOpenedRecentFiles;

// Removes this program's files from the desktop's recent list (GTK's, which records the adding app)
void
ForgetOwnRecentFiles()
{
	GtkRecentManager *manager = gtk_recent_manager_get_default();
	GList *items = gtk_recent_manager_get_items(manager);
	for(GList *item = items; item != nullptr; item = item->next)
	{
		GtkRecentInfo *info = static_cast<GtkRecentInfo *>(item->data);
		if(gtk_recent_info_has_application(info, g_get_application_name()))
			(void)gtk_recent_manager_remove_item(manager, gtk_recent_info_get_uri(info), nullptr);
		gtk_recent_info_unref(info);
	}
	g_list_free(items);
}

// Waits (running the main loop) until inCondition holds, at most 3 s
bool
WaitUntil(std::function<bool()> inCondition)
{
	gint64 end = g_get_monotonic_time() + 3 * G_USEC_PER_SEC;
	while(g_get_monotonic_time() < end)
	{
		if(inCondition())
			return true;
		g_main_context_iteration(nullptr, FALSE);
		g_usleep(10 * 1000);
	}
	return inCondition();
}

void
RunMenuChecks(GApplication *inApp)
{
	char *made = g_dir_make_tmp("omc-menu-test-XXXXXX", nullptr);
	if(made == nullptr)
	{
		Check("a folder for the menu's commands", false);
		return;
	}
	std::string folder = made;
	g_free(made);
	auto command = [&folder](const char *inName, const char *inID, const char *inSubmenu, const char *inMark) {
		std::string json = std::string("{\"NAME\": \"") + inName + "\", \"ACTIVATION_MODE\": \"act_always\", "
							"\"EXECUTION_MODE\": \"exe_shell_script\", \"COMMAND\": [\"/usr/bin/touch '" + folder + "/" + inMark + "'\"]";
		if(inID != nullptr)
			json += std::string(", \"COMMAND_ID\": \"") + inID + "\"";
		if(inSubmenu != nullptr)
			json += std::string(", \"SUBMENU_NAME\": \"") + inSubmenu + "\"";
		return json + "}";
	};
	std::string commandFile = folder + "/Command.json";
	auto removeFolder = [&folder] {
		for(const char *name : {"main.ran", "top.ran", "half.ran", "named.ran", "static.ran", "Command.json"})
			(void)remove((folder + "/" + name).c_str());
		(void)g_rmdir(folder.c_str());
	};
	std::string commands = "{\"VERSION\": 2, \"COMMAND_LIST\": [" +
		command("Main", nullptr, nullptr, "main.ran") + ", " +
		command("Top Command", "test.top", nullptr, "top.ran") + ", " +
		command("Half", "test.half", "Images/Resize", "half.ran") + ", " +
		command("Named", nullptr, nullptr, "named.ran") + ", " +
		command("Static Target", "test.static", nullptr, "static.ran") + "]}";
	(void)g_file_set_contents(commandFile.c_str(), commands.c_str(), -1, nullptr);

	const char *mainMenuJSON = R"([
		{"type": "CommandMenu", "properties": {"name": "Tools"}, "children": [
			{"type": "Button", "properties": {"title": "Run Static", "actionID": "test.static"}},
			{"type": "Menu", "properties": {"title": "More"}, "children": [
				{"type": "Button", "properties": {"title": "Run Top", "actionID": "test.top"}}]}]},
		{"type": "CommandMenu", "properties": {"autoPopulate": true}}])";
	CFObj<CFDataRef> data(CFDataCreate(kCFAllocatorDefault, (const UInt8 *)mainMenuJSON, (CFIndex)strlen(mainMenuJSON)));
	CFObj<CFArrayRef> mainMenu((CFArrayRef)ACFJSONCreatePropertyList(data, kCFPropertyListImmutable, nullptr));
	ForgetOwnRecentFiles();
	Pump(300);
	OMCAppletMenuActions actions {};
	actions.runMainCommand = [](void *) { sMainCommandRuns++; };
	actions.openFile = [](void *, CFURLRef inFileURL) { sOpenedRecentFiles.push_back(URLPath(inFileURL)); };
	actions.quit = [](void *) { sQuits++; };
	actions.context = nullptr;
	CFObj<CFStringRef> commandFileString(CFString(commandFile));
	Check("the applet's menu loads", OMCInstallAppletMenu(mainMenu, commandFileString, actions));

	// A window ActionUI fills has the menu button in its header bar
	GtkWidget *window = adw_application_window_new(GTK_APPLICATION(inApp));
	bool filled = actionUILoadIntoHostWindowFromJSON(window, R"({"type": "Text", "properties": {"text": "The applet's window"}})",
														"5B4C3D2E-0000-4000-8000-00000000AA01", nullptr);
	gtk_window_present(GTK_WINDOW(window));
	Pump(500);
	// ActionUI's primary menu: the menu button with a menu model (a header bar may hold others)
	std::function<GtkWidget *(GtkWidget *)> findMenuButton = [&findMenuButton](GtkWidget *inWidget) -> GtkWidget * {
		if(GTK_IS_MENU_BUTTON(inWidget) && (gtk_menu_button_get_menu_model(GTK_MENU_BUTTON(inWidget)) != nullptr))
			return inWidget;
		for(GtkWidget *child = gtk_widget_get_first_child(inWidget); child != nullptr; child = gtk_widget_get_next_sibling(child))
		{
			GtkWidget *found = findMenuButton(child);
			if(found != nullptr)
				return found;
		}
		return nullptr;
	};
	GtkWidget *button = filled ? findMenuButton(window) : nullptr;
	GMenuModel *menu = (button != nullptr) ? gtk_menu_button_get_menu_model(GTK_MENU_BUTTON(button)) : nullptr;
	std::string fillDetail = filled ? "no menu button with a menu" : "not filled";
	if(!filled)
	{
		char *error = actionUIGetLastError();
		fillDetail += std::string(": ") + ((error != nullptr) ? error : "?");
		free(error);
	}
	Check("a filled window has the menu button", menu != nullptr, fillDetail);
	if(menu == nullptr)
	{
		gtk_window_destroy(GTK_WINDOW(window));
		removeFolder();
		return;
	}
	std::string outline = MenuOutline(menu);
	std::string expected = "[New, Open\xE2\x80\xA6, Open Recent>[Clear Menu]], "
		"[Tools>[Run Static, More>[Run Top]], Commands>[Main, Top Command, Images>[Resize>[Half]], Named, Static Target]], "
		"[About OMCLinuxUITests], [Quit]";
	Check("the menu: New and Open, the applet's menus with the Commands menu in submenus, About, Quit", outline == expected, outline);

	struct Choice { std::vector<std::string> path; const char *mark; const char *name; };
	for(const Choice &choice : {
			Choice{{"Commands", "Images", "Resize", "Half"}, "half.ran", "a command in nested submenus runs"},
			Choice{{"Commands", "Named"}, "named.ran", "a command without an id of its own runs by its name"},
			Choice{{"Tools", "Run Static"}, "static.ran", "a MainMenu.json Button runs the command its actionID names"},
			Choice{{"Tools", "More", "Run Top"}, "top.ran", "and one in a MainMenu.json Menu"} })
	{
		std::string action = MenuItemAction(menu, choice.path);
		if(!action.empty())
			g_action_group_activate_action(G_ACTION_GROUP(inApp), action.c_str(), nullptr);
		Check(choice.name, !action.empty() && WaitForFile(folder + "/" + choice.mark), action.empty() ? "no such item" : action);
	}

	std::string newAction = MenuItemAction(menu, {"New"});
	std::string openAction = MenuItemAction(menu, {"Open\xE2\x80\xA6"});
	std::string quitAction = MenuItemAction(menu, {"Quit"});
	for(const std::string &action : {newAction, openAction, quitAction})
	{
		if(!action.empty())
			g_action_group_activate_action(G_ACTION_GROUP(inApp), action.c_str(), nullptr);
	}
	Check("New and Open run the main command", sMainCommandRuns == 2, std::to_string(sMainCommandRuns));
	Check("Quit quits", sQuits == 1, std::to_string(sQuits));
	Check("New is Ctrl+N", Accelerator(inApp, newAction) == "<Control>n", Accelerator(inApp, newAction));
	Check("Open is Ctrl+O", Accelerator(inApp, openAction) == "<Control>o", Accelerator(inApp, openAction));
	Check("Quit is Ctrl+Q", Accelerator(inApp, quitAction) == "<Control>q", Accelerator(inApp, quitAction));

	// Open Recent follows the desktop's recent list: this program's files, newest first
	std::string older = folder + "/older notes.txt";
	std::string newer = folder + "/newer notes.txt";
	(void)g_file_set_contents(older.c_str(), "x", 1, nullptr);
	(void)g_file_set_contents(newer.c_str(), "x", 1, nullptr);
	GtkRecentManager *recentManager = gtk_recent_manager_get_default();
	for(const std::string &path : {older, newer})
	{
		char *uri = g_filename_to_uri(path.c_str(), nullptr, nullptr);
		(void)gtk_recent_manager_add_item(recentManager, uri);
		// One after the other: GTK adds a file once it has its type (asynchronously), noting the time
		// to the microsecond, which the list orders by
		(void)WaitUntil([&] { return gtk_recent_manager_has_item(recentManager, uri) != FALSE; });
		g_free(uri);
	}
	std::string recentOutline;
	bool updated = WaitUntil([&] {
		recentOutline = MenuOutline(menu);
		return recentOutline.find("Open Recent>[[newer notes.txt, older notes.txt], [Clear Menu]]") != std::string::npos;
	});
	Check("Open Recent lists the applet's recent files, newest first, then Clear Menu", updated, recentOutline);
	// What the menu button shows: its popover keeps a page per submenu; there must be one Open Recent
	// page, as the menu is now (ActionUI gives the button a new popover after each rebuild)
	std::vector<std::string> recentPages;
	GtkPopover *popover = gtk_menu_button_get_popover(GTK_MENU_BUTTON(button));
	GtkWidget *stack = (popover != nullptr) ? FindWidget(GTK_WIDGET(popover), GTK_TYPE_STACK) : nullptr;
	if(stack != nullptr)
	{
		GListModel *pages = G_LIST_MODEL(gtk_stack_get_pages(GTK_STACK(stack)));
		for(guint i = 0; i < g_list_model_get_n_items(pages); i++)
		{
			GtkStackPage *page = GTK_STACK_PAGE(g_list_model_get_item(pages, i));
			const char *name = gtk_stack_page_get_name(page);
			if((name != nullptr) && (strcmp(name, "Open Recent") == 0))
			{
				std::string labels;
				std::function<void(GtkWidget *)> collect = [&](GtkWidget *inWidget) {
					if(GTK_IS_LABEL(inWidget) && (gtk_label_get_text(GTK_LABEL(inWidget))[0] != 0))
						labels += (labels.empty() ? "" : ", ") + std::string(gtk_label_get_text(GTK_LABEL(inWidget)));
					for(GtkWidget *child = gtk_widget_get_first_child(inWidget); child != nullptr; child = gtk_widget_get_next_sibling(child))
						collect(child);
				};
				collect(gtk_stack_page_get_child(page));
				recentPages.push_back(labels);
			}
			g_object_unref(page);
		}
		g_object_unref(pages);
	}
	Check("the menu button shows one Open Recent, as it is now",
			(recentPages.size() == 1) && (recentPages[0] == "Open Recent, newer notes.txt, older notes.txt, Clear Menu"), Joined(recentPages));
	std::string olderAction = MenuItemAction(menu, {"Open Recent", "older notes.txt"});
	if(!olderAction.empty())
		g_action_group_activate_action(G_ACTION_GROUP(inApp), olderAction.c_str(), nullptr);
	Check("choosing one opens that file", (sOpenedRecentFiles.size() == 1) && (sOpenedRecentFiles[0] == older),
			sOpenedRecentFiles.empty() ? "nothing opened" : sOpenedRecentFiles[0]);
	std::string clearAction = MenuItemAction(menu, {"Open Recent", "Clear Menu"});
	if(!clearAction.empty())
		g_action_group_activate_action(G_ACTION_GROUP(inApp), clearAction.c_str(), nullptr);
	bool cleared = WaitUntil([&] {
		recentOutline = MenuOutline(menu);
		return recentOutline.find("Open Recent>[Clear Menu]") != std::string::npos;
	});
	Check("Clear Menu empties it", cleared, recentOutline);
	(void)remove(older.c_str());
	(void)remove(newer.c_str());

	gtk_window_destroy(GTK_WINDOW(window));
	actionUIRemoveWindow("5B4C3D2E-0000-4000-8000-00000000AA01");
	Pump(200);
	removeFolder();
}

#pragma mark - Clipboard and host info

std::string
TextOf(CFStringRef inString)
{
	return (inString != nullptr) ? ACFStringToUTF8(inString) : "(none)";
}

// A clipboard owner that offers text and never writes it, as an app that does not answer: GDK does
// not end such a read when it is canceled, so only the engine's own time limit ends the wait
struct SilentOwner { GdkContentProvider parent; };
struct SilentOwnerClass { GdkContentProviderClass parent; };
G_DEFINE_TYPE(SilentOwner, silent_owner, GDK_TYPE_CONTENT_PROVIDER)

void
silent_owner_init(SilentOwner *inOwner)
{
	(void)inOwner;
}

void
silent_owner_class_init(SilentOwnerClass *inClass)
{
	GdkContentProviderClass *providerClass = GDK_CONTENT_PROVIDER_CLASS(inClass);
	providerClass->ref_formats = [](GdkContentProvider *) -> GdkContentFormats * {
		const char *mimeTypes[] = {"text/plain;charset=utf-8"};
		return gdk_content_formats_new(mimeTypes, 1);
	};
	providerClass->write_mime_type_async = [](GdkContentProvider *inOwner, const char *, GOutputStream *, int, GCancellable *inCancellable,
												GAsyncReadyCallback inCallback, gpointer inData) {
		// Kept unanswered on the owner, freed with it
		g_object_set_data_full(G_OBJECT(inOwner), "write", g_task_new(inOwner, inCancellable, inCallback, inData), g_object_unref);
	};
	providerClass->write_mime_type_finish = [](GdkContentProvider *, GAsyncResult *inResult, GError **outError) -> gboolean {
		return g_task_propagate_boolean(G_TASK(inResult), outError);
	};
}

void
RunClipboardAndHostChecks(GApplication *inApp)
{
	(void)inApp;
	GdkClipboard *clipboard = gdk_display_get_clipboard(gdk_display_get_default());

	gdk_clipboard_set_text(clipboard, "one\ntwo\rthree");
	Check("text on the clipboard is text", OMCIsTextInClipboard());
	CFObj<CFStringRef> asIs(OMCCopyClipboardText(kTextReplaceNothing));
	Check("the clipboard's text, as it is", TextOf(asIs) == "one\ntwo\rthree", TextOf(asIs));
	CFObj<CFStringRef> crs(OMCCopyClipboardText(kTextReplaceLFsWithCRs));
	Check("with line feeds made returns", TextOf(crs) == "one\rtwo\rthree", TextOf(crs));
	CFObj<CFStringRef> lfs(OMCCopyClipboardText(kTextReplaceCRsWithLFs));
	Check("with returns made line feeds", TextOf(lfs) == "one\ntwo\nthree", TextOf(lfs));

	gdk_clipboard_set_text(clipboard, "\xC5\xBC\xC3\xB3\xC5\x82w"); // Polish "zolw" with its accents, in UTF-8
	CFObj<CFStringRef> unicode(OMCCopyClipboardText(kTextReplaceNothing));
	Check("text beyond ASCII comes back whole", (unicode != nullptr) && (CFStringGetLength(unicode) == 4), TextOf(unicode));

	const guchar pixel[4] = {255, 0, 0, 255};
	GBytes *bytes = g_bytes_new(pixel, sizeof(pixel));
	GdkTexture *texture = gdk_memory_texture_new(1, 1, GDK_MEMORY_R8G8B8A8, bytes, 4);
	gdk_clipboard_set_texture(clipboard, texture);
	g_object_unref(texture);
	g_bytes_unref(bytes);
	Check("a picture on the clipboard is not text", !OMCIsTextInClipboard());
	CFObj<CFStringRef> none(OMCCopyClipboardText(kTextReplaceNothing));
	Check("and gives no text", none == nullptr, TextOf(none));
	Check("pasting into another app is refused", !OMCPasteIntoFrontApp());

	GdkContentProvider *silentOwner = GDK_CONTENT_PROVIDER(g_object_new(silent_owner_get_type(), nullptr));
	gdk_clipboard_set_content(clipboard, silentOwner);
	g_object_unref(silentOwner);
	gint64 readStart = g_get_monotonic_time();
	CFObj<CFStringRef> unanswered(OMCCopyClipboardText(kTextReplaceNothing));
	double readSeconds = (double)(g_get_monotonic_time() - readStart) / G_USEC_PER_SEC;
	Check("an owner that never answers gives no text, in about 2 seconds", (unanswered == nullptr) && (readSeconds < 4.0),
			TextOf(unanswered) + " after " + std::to_string(readSeconds) + " s");
	gdk_clipboard_set_text(clipboard, "");

	CFObj<CFStringRef> hostName(OMCCopyHostAppName());
	Check("the host app's name (no bundle here: GLib's application name)", TextOf(hostName) == "OMCLinuxUITests", TextOf(hostName));
	CFObj<CFStringRef> ownName(OMCCopyAppNameForPID(getpid()));
	Check("this process's name is the host app's", TextOf(ownName) == TextOf(hostName), TextOf(ownName));
	CFObj<CFStringRef> initName(OMCCopyAppNameForPID(1));
	Check("another process's name is its command name", (initName != nullptr) && (CFStringGetLength(initName) > 0), TextOf(initName));
	// The box's windows started from a script never get the focus: the front app is not the applet
	pid_t frontPID = OMCGetFrontAppPID();
	CFObj<CFStringRef> frontName(OMCCopyFrontAppName());
	CFObj<CFStringRef> frontID(OMCCopyFrontAppBundleIdentifier());
	Check("with no focused applet window the front app is unknown", (frontPID == 0) && (frontName == nullptr) && (frontID == nullptr),
			std::to_string((long)frontPID) + " " + TextOf(frontName));
	Check("no modifier keys are held", OMCGetKeyboardModifiers() == 0, std::to_string(OMCGetKeyboardModifiers()));
}

#pragma mark - A closed window's model

void
RunModelChecks(GApplication *inApp)
{
	const char *uuid = "5B4C3D2E-0000-4000-8000-00000000AA02";
	GtkWidget *window = adw_application_window_new(GTK_APPLICATION(inApp));
	bool filled = actionUILoadIntoHostWindowFromJSON(window, R"({"type": "TextField", "id": 1, "properties": {"text": "kept"}})", uuid, nullptr);
	gtk_window_present(GTK_WINDOW(window));
	Pump(300);
	gtk_window_destroy(GTK_WINDOW(window));
	Pump(200);
	auto hasModel = [uuid] {
		char *info = actionUIGetElementInfoJSON(uuid);
		bool has = (info != nullptr) && (strcmp(info, "{}") != 0) && (strcmp(info, "null") != 0);
		free(info);
		return has;
	};
	Check("a closed window keeps its ActionUI model", filled && hasModel());
	CFObj<CFStringRef> uuidString(CFString(uuid));
	OMCPlatformForgetActionUIModel(uuidString);
	Check("until OMC forgets it", !hasModel());
	OMCPlatformForgetActionUIModel(uuidString); // an unknown window is ignored
	OMCPlatformForgetActionUIModel(nullptr);
}

#pragma mark - The ActionUI add-ons

// The add-on element types ActionUI shows as "<type> is not available on Linux yet" in inWidget
std::vector<std::string>
PlaceholderTypes(GtkWidget *inWidget)
{
	std::vector<std::string> types;
	if(GTK_IS_LABEL(inWidget))
	{
		const char *text = gtk_label_get_text(GTK_LABEL(inWidget));
		std::string label = (text != nullptr) ? text : "";
		size_t at = label.find(" is not available on Linux yet");
		if(at != std::string::npos)
			types.push_back(label.substr(0, at));
	}
	for(GtkWidget *child = gtk_widget_get_first_child(inWidget); child != nullptr; child = gtk_widget_get_next_sibling(child))
	{
		std::vector<std::string> more = PlaceholderTypes(child);
		types.insert(types.end(), more.begin(), more.end());
	}
	return types;
}

// Fills a window with one element of each add-on and returns the types shown as placeholders;
// outLoaded is false when the document was not loaded at all, which also shows no placeholder
std::vector<std::string>
ShowAddOnElements(GApplication *inApp, const char *inUUID, const char *inPNGName, bool &outLoaded)
{
	const char *document = R"({"type": "VStack", "children": [
		{"type": "RichText", "id": 1, "properties": {"markdown": "**Rich** text"}},
		{"type": "Diff", "id": 2, "properties": {"oldText": "one\ntwo\n", "newText": "one\nthree\n"}},
		{"type": "CachedImage", "id": 3, "properties": {"intrinsicSize": {"width": 32, "height": 32}}},
		{"type": "HostSurface", "id": 4, "properties": {"surfaceName": "omc.test.surface", "idealWidth": 64, "idealHeight": 32}}]})";
	GtkWidget *window = adw_application_window_new(GTK_APPLICATION(inApp));
	gtk_window_set_default_size(GTK_WINDOW(window), 480, 400);
	outLoaded = actionUILoadIntoHostWindowFromJSON(window, document, inUUID, nullptr);
	gtk_window_present(GTK_WINDOW(window));
	Pump(600);
	Capture(window, inPNGName);
	std::vector<std::string> placeholders = PlaceholderTypes(window);
	gtk_window_destroy(GTK_WINDOW(window));
	actionUIRemoveWindow(inUUID);
	Pump(200);
	return placeholders;
}

std::string
Joined(const std::vector<std::string> &inItems)
{
	std::string text;
	for(const std::string &item : inItems)
		text += (text.empty() ? "" : ", ") + item;
	return text.empty() ? "(none)" : text;
}

void
RunAddOnChecks(GApplication *inApp)
{
	bool loaded = false;
	std::vector<std::string> before = ShowAddOnElements(inApp, "5B4C3D2E-0000-4000-8000-00000000AA03", "addons-before", loaded);
	Check("before registration the add-on elements are placeholders",
			loaded && (Joined(before) == "RichText, Diff, CachedImage, HostSurface"), loaded ? Joined(before) : "not loaded");
	OMCRegisterActionUIAddOns();
	std::vector<std::string> after = ShowAddOnElements(inApp, "5B4C3D2E-0000-4000-8000-00000000AA04", "addons-after", loaded);
	Check("registered: RichText, Diff, CachedImage and HostSurface render", loaded && after.empty(), loaded ? Joined(after) : "not loaded");
}

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
			RunMenuChecks(inApp);
			RunClipboardAndHostChecks(inApp);
			RunModelChecks(inApp);
			RunAddOnChecks(inApp);
		}
		g_application_release(inApp);
		g_application_quit(inApp);
	}), nullptr);
	int status = g_application_run(G_APPLICATION(app), 0, nullptr);
	g_object_unref(app);
	printf("%d passed, %d failed\n", sPassed, sFailed);
	return ((status == 0) && (sFailed == 0)) ? 0 : 1;
}

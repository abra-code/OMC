//
//  OMCPlatformFilePanels.cpp (Linux)
//  Abracode
//
//  The Linux implementation of OMCPlatformRunSavePanel and OMCPlatformRunOpenPanel
//  (Platform/OMCFilePanels.h; named apart from the portable OMCFilePanels.cpp, as the Linux build's
//  shims share one folder): GTK's GtkFileDialog,
//  over the application's active window, or as a window of its own when there is none. GTK shows
//  the desktop's file chooser through its portal when the desktop has one (GNOME does), else its own.
//  Each call waits for the answer in a nested GLib main loop (OMCModalLoop.h, so a quit ends the
//  wait: no answer, the panel is canceled).
//  What macOS's panels take and GTK's do not, or differently:
//  - The message: GtkFileDialog has a title and no message line. The title is the message, or the
//    client name (the applet's) when there is no message, which macOS shows as the panel's title.
//  - Allowed content types are uniform type identifiers ("public.image"); the common ones are known
//    by their MIME types and become one filter (an unknown one allows nothing more, and with none
//    known any file can be chosen, as on macOS). A save panel does not add an extension.
//  - Files and folders at once: GTK chooses one or the other; files then, as ActionUI's panels do.
//  - The identifier (where macOS keeps the panel's last folder), showing hidden files (the person
//    turns it on in the panel, Ctrl+H) and the default name of an open panel (ignored on macOS too)
//    are not used.
//  Without GTK (no display, or a process that has not made its application) no panel can be shown:
//  the calls log and answer as a cancel would.
//  Main thread only.
//

#include "OMCFilePanels.h"
#include "Linux/OMCModalLoop.h"
#include "OMCLog.h"
#include "ACFString.h"
#include "CFObj.h"
#include <gtk/gtk.h>
#include <algorithm>
#include <map>
#include <string>
#include <vector>

namespace
{

enum class PanelMode
{
	OpenFile,
	OpenFiles,
	SelectFolder,
	SelectFolders,
	Save
};

// The common uniform type identifiers, by their MIME types (as ActionUI's panels know them,
// ActionUIAdwaitaApplication/AppPanels.swift)
const std::map<std::string, std::vector<std::string>> &
MIMETypesForIdentifier()
{
	static const auto *sTypes = new std::map<std::string, std::vector<std::string>> {
		{"public.data", {"application/octet-stream", "*/*"}},
		{"public.item", {"*/*"}},
		{"public.content", {"*/*"}},
		{"public.image", {"image/*"}},
		{"public.jpeg", {"image/jpeg"}},
		{"public.png", {"image/png"}},
		{"public.tiff", {"image/tiff"}},
		{"public.heic", {"image/heic"}},
		{"com.compuserve.gif", {"image/gif"}},
		{"org.webmproject.webp", {"image/webp"}},
		{"com.microsoft.bmp", {"image/bmp"}},
		{"public.svg-image", {"image/svg+xml"}},
		{"public.text", {"text/*"}},
		{"public.plain-text", {"text/plain"}},
		{"public.utf8-plain-text", {"text/plain"}},
		{"public.json", {"application/json"}},
		{"public.xml", {"application/xml", "text/xml"}},
		{"public.html", {"text/html"}},
		{"public.comma-separated-values-text", {"text/csv"}},
		{"public.python-script", {"text/x-python", "text/x-python3"}},
		{"public.shell-script", {"application/x-shellscript"}},
		{"com.adobe.pdf", {"application/pdf"}},
		{"public.audio", {"audio/*"}},
		{"public.movie", {"video/*"}},
		{"public.video", {"video/*"}},
		{"public.mpeg-4", {"video/mp4"}},
		{"public.zip-archive", {"application/zip"}},
	};
	return *sTypes;
}

// The MIME types inAllowedContentTypes allows; empty when they restrict nothing (none known, or
// one that allows any file)
std::vector<std::string>
AllowedMIMETypes(CFArrayRef inAllowedContentTypes)
{
	std::vector<std::string> mimeTypes;
	if(inAllowedContentTypes == nullptr)
		return mimeTypes;
	const auto &known = MIMETypesForIdentifier();
	CFIndex count = CFArrayGetCount(inAllowedContentTypes);
	for(CFIndex i = 0; i < count; i++)
	{
		CFTypeRef item = CFArrayGetValueAtIndex(inAllowedContentTypes, i);
		if((item == nullptr) || (CFGetTypeID(item) != CFStringGetTypeID()))
			continue;
		auto found = known.find(ACFStringToUTF8((CFStringRef)item));
		if(found == known.end())
			continue;
		for(const std::string &mimeType : found->second)
		{
			if(mimeType == "*/*")
				return std::vector<std::string>();
			mimeTypes.push_back(mimeType);
		}
	}
	return mimeTypes;
}

// What the panel's filter menu calls inMIMEType: GIO's description of an exact type ("PNG image"),
// a plain name for the families of the identifiers above (GIO says "image/* type")
std::string
FilterName(const std::string &inMIMEType)
{
	static const std::map<std::string, std::string> sFamilies {
		{"image/*", "Images"}, {"text/*", "Text"}, {"audio/*", "Audio"}, {"video/*", "Video"}
	};
	auto family = sFamilies.find(inMIMEType);
	if(family != sFamilies.end())
		return family->second;
	char *description = g_content_type_get_description(inMIMEType.c_str());
	std::string name = (description != nullptr) ? description : inMIMEType;
	g_free(description);
	return name;
}

GtkFileDialog *
MakeFileDialog(CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultDirPath,
				CFStringRef inPrompt, CFArrayRef inAllowedContentTypes)
{
	GtkFileDialog *dialog = gtk_file_dialog_new();
	// GTK's own chooser, modal even with no parent, takes the input of the application's windows
	// while it waits, as the macOS panels do
	gtk_file_dialog_set_modal(dialog, TRUE);
	std::string title = ACFStringToUTF8(inMessage);
	if(title.empty())
		title = ACFStringToUTF8(inClientName);
	if(!title.empty())
		gtk_file_dialog_set_title(dialog, title.c_str());
	std::string prompt = ACFStringToUTF8(inPrompt);
	if(!prompt.empty())
		gtk_file_dialog_set_accept_label(dialog, prompt.c_str());
	std::string folder = ACFStringToUTF8(inDefaultDirPath);
	if(!folder.empty())
	{
		GFile *file = g_file_new_for_path(folder.c_str());
		gtk_file_dialog_set_initial_folder(dialog, file);
		g_object_unref(file);
	}
	std::vector<std::string> mimeTypes = AllowedMIMETypes(inAllowedContentTypes);
	if(!mimeTypes.empty())
	{
		GtkFileFilter *allowed = gtk_file_filter_new();
		std::vector<std::string> names;
		std::string name;
		for(const std::string &mimeType : mimeTypes)
		{
			gtk_file_filter_add_mime_type(allowed, mimeType.c_str());
			std::string typeName = FilterName(mimeType);
			if(std::find(names.begin(), names.end(), typeName) != names.end())
				continue; // public.xml's two types are one "XML document"
			name += (name.empty() ? "" : ", ") + typeName;
			names.push_back(typeName);
		}
		gtk_file_filter_set_name(allowed, name.c_str());
		GListStore *filters = g_list_store_new(GTK_TYPE_FILE_FILTER);
		g_list_store_append(filters, allowed);
		gtk_file_dialog_set_filters(dialog, G_LIST_MODEL(filters));
		gtk_file_dialog_set_default_filter(dialog, allowed);
		g_object_unref(filters);
		g_object_unref(allowed);
	}
	return dialog;
}

// One panel's wait. On the heap: when a quit ends the wait first, the panel's callback comes
// later (canceled) and frees it
struct PanelWait
{
	GMainLoop *loop {nullptr};
	PanelMode mode {PanelMode::OpenFile};
	bool answered {false};
	bool abandoned {false};
	std::vector<std::string> paths; // the chosen files' paths; empty: canceled
};

void
AddLocalPath(GFile *inFile, std::vector<std::string> &outPaths)
{
	// A chosen file with no local path (a remote location a portal offers) is left out
	char *path = (inFile != nullptr) ? g_file_get_path(inFile) : nullptr;
	if(path != nullptr)
	{
		outPaths.push_back(path);
		g_free(path);
	}
}

void
OnPanelAnswered(GObject *inDialog, GAsyncResult *inResult, gpointer inWait)
{
	PanelWait *wait = static_cast<PanelWait *>(inWait);
	GtkFileDialog *dialog = GTK_FILE_DIALOG(inDialog);
	GError *error = nullptr;
	switch(wait->mode)
	{
		case PanelMode::OpenFiles:
		case PanelMode::SelectFolders:
		{
			GListModel *files = (wait->mode == PanelMode::OpenFiles)
								? gtk_file_dialog_open_multiple_finish(dialog, inResult, &error)
								: gtk_file_dialog_select_multiple_folders_finish(dialog, inResult, &error);
			if(files != nullptr)
			{
				guint count = g_list_model_get_n_items(files);
				for(guint i = 0; i < count; i++)
				{
					GFile *file = G_FILE(g_list_model_get_item(files, i));
					AddLocalPath(file, wait->paths);
					g_object_unref(file);
				}
				g_object_unref(files);
			}
		}
		break;

		default:
		{
			GFile *file = nullptr;
			if(wait->mode == PanelMode::OpenFile)
				file = gtk_file_dialog_open_finish(dialog, inResult, &error);
			else if(wait->mode == PanelMode::SelectFolder)
				file = gtk_file_dialog_select_folder_finish(dialog, inResult, &error);
			else
				file = gtk_file_dialog_save_finish(dialog, inResult, &error);
			AddLocalPath(file, wait->paths);
			if(file != nullptr)
				g_object_unref(file);
		}
		break;
	}
	if(error != nullptr)
	{
		// Dismissed (the person canceled) and Cancelled (a quit) are answers, not failures
		if(!g_error_matches(error, GTK_DIALOG_ERROR, GTK_DIALOG_ERROR_DISMISSED) &&
			!g_error_matches(error, GTK_DIALOG_ERROR, GTK_DIALOG_ERROR_CANCELLED) &&
			!g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
			OMCLogMessage("file panel failed: %s", error->message);
		g_error_free(error);
	}

	if(wait->abandoned)
	{
		delete wait; // nobody waits any more
		return;
	}
	wait->answered = true;
	if(g_main_loop_is_running(wait->loop))
		g_main_loop_quit(wait->loop);
}

// Shows the panel and waits for its answer: the chosen paths, empty when canceled or ended by a quit
std::vector<std::string>
RunPanel(GtkFileDialog *inDialog, PanelMode inMode)
{
	PanelWait *wait = new PanelWait();
	wait->loop = g_main_loop_new(nullptr, FALSE);
	wait->mode = inMode;
	GCancellable *cancellable = g_cancellable_new();
	GtkWindow *parent = OMCModalParentWindow();
	switch(inMode)
	{
		case PanelMode::OpenFile: gtk_file_dialog_open(inDialog, parent, cancellable, OnPanelAnswered, wait); break;
		case PanelMode::OpenFiles: gtk_file_dialog_open_multiple(inDialog, parent, cancellable, OnPanelAnswered, wait); break;
		case PanelMode::SelectFolder: gtk_file_dialog_select_folder(inDialog, parent, cancellable, OnPanelAnswered, wait); break;
		case PanelMode::SelectFolders: gtk_file_dialog_select_multiple_folders(inDialog, parent, cancellable, OnPanelAnswered, wait); break;
		case PanelMode::Save: gtk_file_dialog_save(inDialog, parent, cancellable, OnPanelAnswered, wait); break;
	}
	if(!wait->answered)
		OMCRunModalLoop(wait->loop); // returns at the answer, or when a quit ends it
	std::vector<std::string> paths;
	g_main_loop_unref(wait->loop);
	wait->loop = nullptr;
	if(wait->answered)
	{
		paths = std::move(wait->paths);
		delete wait;
	}
	else
	{
		// Ended by a quit: the panel is canceled, and its callback, which still comes, frees the wait
		wait->abandoned = true;
		g_cancellable_cancel(cancellable);
	}
	g_object_unref(cancellable);
	return paths;
}

CFURLRef
CreateFileURL(const std::string &inPath, bool inIsDirectory)
{
	return CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (const UInt8 *)inPath.c_str(), (CFIndex)inPath.size(), inIsDirectory);
}

} // namespace

CFURLRef
OMCPlatformRunSavePanel(CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath,
						CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inAdditonalFlags)
{
	(void)inIdentifier; (void)inAdditonalFlags;
	if(!gtk_is_initialized())
	{
		OMCLogMessage("save panel not shown (no GTK): %s", OMCLogCString(inMessage).c_str());
		return nullptr;
	}
	GtkFileDialog *dialog = MakeFileDialog(inClientName, inMessage, inDefaultDirPath, inPrompt, inAllowedContentTypes);
	std::string name = ACFStringToUTF8(inDefaultName);
	if(!name.empty())
		gtk_file_dialog_set_initial_name(dialog, name.c_str());
	std::vector<std::string> paths = RunPanel(dialog, PanelMode::Save);
	g_object_unref(dialog);
	return paths.empty() ? nullptr : CreateFileURL(paths.front(), false);
}

CFArrayRef
OMCPlatformRunOpenPanel(CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath,
						CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inAdditonalFlags)
{
	(void)inDefaultName; (void)inIdentifier; // an open panel has no name field, on macOS either
	if(!gtk_is_initialized())
	{
		OMCLogMessage("open panel not shown (no GTK): %s", OMCLogCString(inMessage).c_str());
		return nullptr;
	}
	bool files = ((inAdditonalFlags & kOMCFilePanelCanChooseFiles) != 0);
	bool folders = ((inAdditonalFlags & kOMCFilePanelCanChooseDirectories) != 0);
	bool multiple = ((inAdditonalFlags & kOMCFilePanelAllowMultipleItems) != 0);
	PanelMode mode = (folders && !files)
					? (multiple ? PanelMode::SelectFolders : PanelMode::SelectFolder)
					: (multiple ? PanelMode::OpenFiles : PanelMode::OpenFile);
	bool choosesFolders = (mode == PanelMode::SelectFolder) || (mode == PanelMode::SelectFolders);

	GtkFileDialog *dialog = MakeFileDialog(inClientName, inMessage, inDefaultDirPath, inPrompt,
											choosesFolders ? nullptr : inAllowedContentTypes);
	std::vector<std::string> paths = RunPanel(dialog, mode);
	g_object_unref(dialog);
	if(paths.empty())
		return nullptr;

	CFObj<CFMutableArrayRef> urls(CFArrayCreateMutable(kCFAllocatorDefault, (CFIndex)paths.size(), &kCFTypeArrayCallBacks));
	for(const std::string &path : paths)
	{
		CFObj<CFURLRef> url(CreateFileURL(path, choosesFolders));
		if(url != nullptr)
			CFArrayAppendValue(urls, url);
	}
	return urls.Detach();
}

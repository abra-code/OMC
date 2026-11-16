//
//  OMCWindowHost.cpp (Linux)
//  Abracode
//
//  The Linux implementation of Platform/OMCWindowHost.h: an AdwApplicationWindow of the applet's
//  application (EntryPoints/Linux/OMCAppletMain.cpp), filled with the ActionUI document by
//  actionUILoadIntoHostWindowFromURL, which builds its header bar, toasts and the document's modals
//  and registers the window under its UUID. The rules are the macOS host's
//  (Platform/Apple/OMCWindowHost.mm): a window is counted once it is shown until it closes; Close()
//  and the destructor do not run the closed-by-user callback; a callback runs from a copy, since it
//  may delete the window object; the document's model stays until the destructor removes it (unless
//  the spec keeps it).
//  Where Linux differs:
//  - placement, cascading, levels: a Wayland desktop places windows itself; a floating window is
//    kept above the app's active window (transient), nothing more;
//  - sizes: the layout area is below ActionUI's header bar, whose height ActionUI measured when it
//    filled the window (actionUIGetWindowBarsHeight), added to a content or layout size;
//  - the saved frame (frameAutosaveName) is not kept yet (the design note's question 3);
//  - a modal run is a nested GLib main loop, with the window modal over the app's active window.
//  Main thread only.
//

#include "OMCWindowHost.h"
#include "Linux/OMCModalLoop.h"
#include "OMCEngineBundle.h"
#include "OMCLog.h"
#include "ACFString.h"
#include "CFObj.h"
#include "ActionUIC.h"
#include <adwaita.h>
#include <string>

namespace
{

int sOpenHostedWindowCount = 0;

// The height of the bars ActionUI put above the layout area (its header bar, a subtitle line), as
// it measured them when it filled the window: what a size below the bars adds to make the window's
int
BarsHeight(CFStringRef inWindowUUID)
{
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	double height = actionUIGetWindowBarsHeight(uuid.c_str());
	return (height > 0) ? (int)height : 0;
}

class OMCLinuxHostedWindow : public OMCHostedWindow
{
public:
							OMCLinuxHostedWindow(GtkWindow *inWindow, CFStringRef inWindowUUID, const OMCHostedWindowSpec &inSpec,
												std::function<void()> inOnClosedByUser)
								: mWindow(GTK_WINDOW(g_object_ref(inWindow))), mWindowUUID(inWindowUUID, kCFObjRetain),
								mOnClosedByUser(std::move(inOnClosedByUser)), mSpec(inSpec)
							{
								// only the sizes and flags are kept: the references are not retained
								mSpec.documentName = nullptr;
								mSpec.documentURL = nullptr;
								mSpec.windowUUID = nullptr;
								mSpec.title = nullptr;
								mSpec.frameAutosaveName = nullptr;
								g_signal_connect(mWindow, "close-request", G_CALLBACK(OnCloseRequest), this);
								g_signal_connect(mWindow, "notify::is-active", G_CALLBACK(OnActiveChanged), this);
								g_signal_connect(mWindow, "map", G_CALLBACK(OnMap), this);
								// Ctrl+W closes a closable window, as Command-W does on macOS (GtkWindow's own
								// window.close action, which asks close-request)
								if(mSpec.closable)
								{
									GtkEventController *shortcuts = gtk_shortcut_controller_new();
									gtk_shortcut_controller_add_shortcut(GTK_SHORTCUT_CONTROLLER(shortcuts),
										gtk_shortcut_new(gtk_shortcut_trigger_parse_string("<Control>w"), gtk_named_action_new("window.close")));
									gtk_widget_add_controller(GTK_WIDGET(mWindow), shortcuts);
								}
							}

	virtual					~OMCLinuxHostedWindow() override
							{
								g_signal_handlers_disconnect_by_data(mWindow, this);
								Close();
								g_object_unref(mWindow);
								if(mSpec.removesModelWhenDestroyed)
								{
									std::string uuid = ACFStringToUTF8(mWindowUUID);
									actionUIRemoveWindow(uuid.c_str());
								}
							}

	virtual CFStringRef		GetWindowUUID() const override { return mWindowUUID; }

	virtual void			Show() override
							{
								if(mClosed)
									return;
								if(!mShown)
								{
									mShown = true;
									sOpenHostedWindowCount++;
								}
								gtk_window_present(mWindow);
							}

	virtual void			SizeToContent() override
							{
								if(mClosed || mShown)
									return;
								// -1: the content's natural size, in each dimension the spec left at 0
								int width = 0;
								int height = 0;
								gtk_window_get_default_size(mWindow, &width, &height);
								gtk_window_set_default_size(mWindow, (mSpec.contentWidth > 0) ? width : -1, (mSpec.contentHeight > 0) ? height : -1);
							}

	virtual void			Close() override
							{
								if(mClosed)
									return;
								MarkClosed(); // before the window goes: its close request then knows it was not the user
								gtk_window_destroy(mWindow);
							}

	virtual void			SetRepresentedFile(CFURLRef inFileURL) override
							{
								if(inFileURL == nullptr)
									return;
								CFObj<CFStringRef> name(CFURLCopyLastPathComponent(inFileURL));
								SetTitle(name);
							}

	virtual void			SetTitle(CFStringRef inTitle) override
							{
								if(inTitle == nullptr)
									return;
								std::string title = ACFStringToUTF8(inTitle);
								gtk_window_set_title(mWindow, title.c_str());
							}

	virtual bool			IsKey() const override { return !mClosed && gtk_window_is_active(mWindow); }

	virtual void			SetTopLeftPosition(double inLeft, double inTop) override
							{
								(void)inLeft; // the desktop places windows (Wayland)
								(void)inTop;
							}

	virtual void			SetLayoutSize(double inWidth, double inHeight) override
							{
								if(mClosed || (inWidth <= 0) || (inHeight <= 0))
									return;
								gtk_window_set_default_size(mWindow, (int)inWidth, (int)inHeight + BarsHeight(mWindowUUID));
							}

	virtual void			SetKeyChangeCallbacks(std::function<void()> inOnBecameKey, std::function<void()> inOnResignedKey) override
							{
								mOnBecameKey = std::move(inOnBecameKey);
								mOnResignedKey = std::move(inOnResignedKey);
							}

	virtual void *			GetNativeWindow() const override { return mWindow; }

	virtual void			RunModal() override
							{
								if(mClosed || (mModalLoop != nullptr))
									return;
								GtkApplication *app = gtk_window_get_application(mWindow);
								GtkWindow *active = (app != nullptr) ? gtk_application_get_active_window(app) : nullptr;
								if((active != nullptr) && (active != mWindow))
									gtk_window_set_transient_for(mWindow, active);
								gtk_window_set_modal(mWindow, TRUE);
								Show();
								// Showing may run the key callback (an activation subcommand), which may close
								// the window: a run would then wait for nothing
								if(mClosed)
									return;
								mModalLoop = g_main_loop_new(nullptr, FALSE);
								OMCRunModalLoop(mModalLoop); // a quit ends it too (OMCModalLoop.h)
								g_main_loop_unref(mModalLoop);
								mModalLoop = nullptr;
								if(!mClosed)
									gtk_window_set_modal(mWindow, FALSE);
							}

	virtual void			EndModal() override
							{
								if((mModalLoop != nullptr) && g_main_loop_is_running(mModalLoop))
									g_main_loop_quit(mModalLoop);
							}

private:
	void					MarkClosed()
							{
								EndModal();
								mClosed = true;
								if(mShown)
								{
									mShown = false;
									sOpenHostedWindowCount--;
								}
							}

	// The user closed the window (its close button, Ctrl+W, the desktop, or a close by other code):
	// the closed-by-user callback, then the window goes (false lets GTK destroy it). A window that is
	// not closable refuses: only the engine closes it (Close), as the progress window on macOS has
	// no close button and no Command-W.
	static gboolean			OnCloseRequest(GtkWindow *inWindow, gpointer inSelf)
							{
								(void)inWindow;
								OMCLinuxHostedWindow *self = static_cast<OMCLinuxHostedWindow *>(inSelf);
								if(self->mClosed)
									return FALSE;
								if(!self->mSpec.closable)
									return TRUE;
								self->MarkClosed();
								// a copy: the callback may delete self, and with it the member while it runs;
								// self's destructor then finds it closed and leaves the window to GTK, which
								// destroys it after this
								std::function<void()> callback = self->mOnClosedByUser;
								if(callback)
									callback(); // may delete self
								return FALSE;
							}

	static void				OnActiveChanged(GObject *inWindow, GParamSpec *, gpointer inSelf)
							{
								OMCLinuxHostedWindow *self = static_cast<OMCLinuxHostedWindow *>(inSelf);
								if(self->mClosed)
									return;
								// a copy: the callback may delete self, and with it the member while it runs
								std::function<void()> callback = gtk_window_is_active(GTK_WINDOW(inWindow)) ? self->mOnBecameKey : self->mOnResignedKey;
								if(callback)
									callback(); // may delete self
							}

	// The first time the window is on screen: the document's size limits can be read now (GTK
	// measures styled widgets only)
	static void				OnMap(GtkWidget *inWindow, gpointer inSelf)
							{
								(void)inWindow;
								OMCLinuxHostedWindow *self = static_cast<OMCLinuxHostedWindow *>(inSelf);
								if(self->mLimitsApplied || !self->mSpec.sizeLimitsFromDocument)
									return;
								self->mLimitsApplied = true;
								self->ApplyDocumentSizeLimits();
							}

	// A document whose minimum and maximum are the same makes a window of fixed size, as on macOS.
	// The minimum needs nothing: GTK keeps a window at least as large as its content's measured
	// minimum plus the bars (and a size request here would defeat the scrolling ActionUI gives a
	// document larger than the screen). GTK 4 has no maximum window size.
	void					ApplyDocumentSizeLimits()
							{
								std::string uuid = ACFStringToUTF8(mWindowUUID);
								double minWidth = 0, minHeight = 0, maxWidth = 0, maxHeight = 0;
								if(!actionUIGetContentSizeLimits(uuid.c_str(), &minWidth, &minHeight, &maxWidth, &maxHeight))
									return;
								if((minWidth <= 10.0) || (minHeight <= 10.0))
									return; // as macOS: no limits worth keeping
								bool isFixedSize = ((maxWidth - minWidth) < 1.0) && ((maxHeight - minHeight) < 1.0);
								if(isFixedSize)
									gtk_window_set_resizable(mWindow, FALSE);
							}

	GtkWindow *				mWindow;
	CFObj<CFStringRef>		mWindowUUID;
	std::function<void()>	mOnClosedByUser;
	std::function<void()>	mOnBecameKey;
	std::function<void()>	mOnResignedKey;
	OMCHostedWindowSpec		mSpec;
	GMainLoop *				mModalLoop {nullptr};
	bool					mShown {false};
	bool					mClosed {false};
	bool					mLimitsApplied {false};
};

// The document's file path, from the spec's URL or the engine's resource of that name
std::string
DocumentPath(const OMCHostedWindowSpec &inSpec)
{
	CFObj<CFURLRef> documentURL;
	if(inSpec.documentURL != nullptr)
	{
		documentURL.Adopt(inSpec.documentURL, kCFObjRetain);
	}
	else if(inSpec.documentName != nullptr)
	{
		CFBundleRef engineBundle = OMCGetEngineBundle();
		if(engineBundle != nullptr)
			documentURL.Adopt(CFBundleCopyResourceURL(engineBundle, inSpec.documentName, CFSTR("json"), nullptr));
		if(documentURL == nullptr)
			OMCLogMessage("the built-in document %s is missing from the engine's bundle", OMCLogCString(inSpec.documentName).c_str());
	}
	char path[PATH_MAX];
	if((documentURL == nullptr) || !CFURLGetFileSystemRepresentation(documentURL, true, (UInt8 *)path, sizeof(path)))
		return std::string();
	return path;
}

} // namespace

std::unique_ptr<OMCHostedWindow>
OMCCreateHostedWindow(const OMCHostedWindowSpec &inSpec, std::function<void()> inOnClosedByUser)
{
	std::string documentPath = DocumentPath(inSpec);
	if(documentPath.empty())
		return nullptr;

	GApplication *app = g_application_get_default();
	if(!GTK_IS_APPLICATION(app))
	{
		OMCLogMessage("no window for %s: the process has no GTK application", documentPath.c_str());
		return nullptr;
	}

	CFObj<CFStringRef> windowUUID;
	if(inSpec.windowUUID != nullptr)
	{
		windowUUID.Adopt(inSpec.windowUUID, kCFObjRetain);
	}
	else
	{
		CFObj<CFUUIDRef> uuid(CFUUIDCreate(kCFAllocatorDefault));
		windowUUID.Adopt(CFUUIDCreateString(kCFAllocatorDefault, uuid));
	}
	std::string uuidText = ACFStringToUTF8(windowUUID);

	GtkWidget *window = adw_application_window_new(GTK_APPLICATION(app));
	g_object_ref(window); // not floating (GTK's toplevel list holds it): a reference of ours until the hosted window takes its own
	if(!actionUILoadIntoHostWindowFromURL(window, documentPath.c_str(), uuidText.c_str(), nullptr))
	{
		OMCLogMessage("cannot load the ActionUI document %s", documentPath.c_str());
		gtk_window_destroy(GTK_WINDOW(window));
		g_object_unref(window);
		return nullptr;
	}

	if(inSpec.title != nullptr)
	{
		std::string title = ACFStringToUTF8(inSpec.title);
		gtk_window_set_title(GTK_WINDOW(window), title.c_str());
	}
	gtk_window_set_deletable(GTK_WINDOW(window), inSpec.closable);
	gtk_window_set_resizable(GTK_WINDOW(window), inSpec.resizable);
	if((inSpec.contentWidth > 0) || (inSpec.contentHeight > 0))
	{
		// The spec's content size is the layout area's, below the bars: the bars' height is added
		int width = 0;
		int height = 0;
		gtk_window_get_default_size(GTK_WINDOW(window), &width, &height);
		gtk_window_set_default_size(GTK_WINDOW(window), (inSpec.contentWidth > 0) ? (int)inSpec.contentWidth : width,
									(inSpec.contentHeight > 0) ? (int)inSpec.contentHeight + BarsHeight(windowUUID) : height);
	}
	if(inSpec.level != OMCHostedWindowLevel::normal)
	{
		GtkWindow *active = gtk_application_get_active_window(GTK_APPLICATION(app));
		if((active != nullptr) && (active != GTK_WINDOW(window)))
			gtk_window_set_transient_for(GTK_WINDOW(window), active);
	}

	std::unique_ptr<OMCHostedWindow> hosted(new OMCLinuxHostedWindow(GTK_WINDOW(window), windowUUID, inSpec, std::move(inOnClosedByUser)));
	g_object_unref(window); // the hosted window keeps its own reference
	return hosted;
}

void
OMCResetHostedWindowCascading()
{
	// nothing to reset: the desktop places windows
}

int
OMCOpenHostedWindowCount()
{
	return sOpenHostedWindowCount;
}

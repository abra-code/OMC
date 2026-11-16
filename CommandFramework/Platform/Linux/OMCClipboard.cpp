//
//  OMCClipboard.cpp (Linux)
//  Abracode
//
//  The Linux implementation of Platform/OMCClipboard.h: the desktop's clipboard through GDK (the
//  default display's GdkClipboard).
//  - Plain text only, as on macOS: the text a command gets as its clipboard context.
//  - GDK reads a clipboard another app owns asynchronously, so the read waits in a nested GLib
//    main loop (OMCModalLoop.h, so a quit ends it: no text), for at most 2 seconds: a clipboard
//    owner that never answers must not hang the applet.
//  - On Wayland an app gets the clipboard only while one of its windows has the keyboard focus:
//    a command run from the applet's menu or window sees it; one started with no applet window in
//    front (a file opened from the file manager) may see none.
//  - In an OMC test launch nothing reads the desktop's clipboard: the run's own general pasteboard
//    is read, as on macOS (OMCTestHost.h), through the framework's pasteboard tool
//    (pasteboard/linux/pasteboard keeps named pasteboards as files; the engine's environment has
//    OMC_TEST_PASTEBOARD_PREFIX, which makes the tool's "general" the run's board).
//  - No paste into the front app: Wayland gives an app no way to send keystrokes to another.
//  Main thread only.
//

#include "OMCClipboard.h"
#include "OMCConstants.h"
#include "OMCTestHost.h"
#include "OMCEngineBundle.h"
#include "CFObj.h"
#include "Linux/OMCModalLoop.h"
#include "OMCLog.h"
#include <gtk/gtk.h>
#include <atomic>
#include <climits>
#include <string>

namespace
{

const guint kReadTimeoutMilliseconds = 2000;

// In an OMC test launch: the text of the run's own general pasteboard, read with the framework's
// pasteboard tool (Support/pasteboard; not the harness's support folder, which may hold recording
// stubs). False when there is none, or the tool cannot be run.
bool
ReadTestClipboardText(std::string &outText)
{
	outText.clear();
	CFBundleRef engineBundle = OMCGetEngineBundle();
	if(engineBundle == nullptr)
		return false;
	CFObj<CFURLRef> supportFilesURL( ::CFBundleCopySupportFilesDirectoryURL(engineBundle) );
	if(supportFilesURL == nullptr)
		return false;
	CFObj<CFURLRef> supportURL( ::CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, supportFilesURL, CFSTR("Support"), true) );
	if(supportURL == nullptr)
		return false;
	CFObj<CFURLRef> toolURL( ::CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, supportURL, CFSTR("pasteboard"), false) );
	char toolPath[PATH_MAX];
	if((toolURL == nullptr) || !::CFURLGetFileSystemRepresentation(toolURL, true, (UInt8 *)toolPath, sizeof(toolPath)))
		return false;

	char generalName[] = "general";
	char getOperation[] = "get";
	char *arguments[] = { toolPath, generalName, getOperation, nullptr };
	gchar *output = nullptr;
	gint waitStatus = 0;
	GError *error = nullptr;
	gboolean ran = g_spawn_sync(nullptr, arguments, nullptr, G_SPAWN_STDERR_TO_DEV_NULL, nullptr, nullptr,
								&output, nullptr, &waitStatus, &error);
	if(!ran)
	{
		OMCLogMessage("the test's clipboard could not be read with %s: %s", toolPath, (error != nullptr) ? error->message : "unknown error");
		if(error != nullptr)
			g_error_free(error);
		return false;
	}
	bool succeeded = g_spawn_check_wait_status(waitStatus, nullptr);
	if(succeeded && (output != nullptr))
		outText = output;
	g_free(output);
	if(!succeeded)
		OMCLogMessage("the test's clipboard could not be read with %s: the tool failed", toolPath);
	return succeeded && !outText.empty();
}

// The clipboard's text as a CFString, with the line ends a command asked for
CFStringRef
CreateClipboardString(std::string &ioText, long inReplaceOption)
{
	if(inReplaceOption == kTextReplaceLFsWithCRs)
	{
		for(char &character : ioText)
		{
			if(character == '\n')
				character = '\r';
		}
	}
	else if(inReplaceOption == kTextReplaceCRsWithLFs)
	{
		for(char &character : ioText)
		{
			if(character == '\r')
				character = '\n';
		}
	}
	return CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)ioText.data(), (CFIndex)ioText.size(), kCFStringEncodingUTF8, false);
}

GdkClipboard *
DesktopClipboard()
{
	if(!gtk_is_initialized() || OMCTestHostIsActive())
		return nullptr;
	GdkDisplay *display = gdk_display_get_default();
	return (display != nullptr) ? gdk_display_get_clipboard(display) : nullptr;
}

// One read's wait. On the heap: when a quit or the time limit ends the wait first, the read's
// callback, if it comes later (canceled), frees it
struct ReadWait
{
	GMainLoop *loop {nullptr};
	GCancellable *cancellable {nullptr}; // the read's, while the time limit is attached
	bool answered {false};
	bool abandoned {false};
	bool timedOut {false};
	bool hasText {false};
	std::string text;
};

void
OnTextRead(GObject *inClipboard, GAsyncResult *inResult, gpointer inWait)
{
	ReadWait *wait = static_cast<ReadWait *>(inWait);
	GError *error = nullptr;
	char *text = gdk_clipboard_read_text_finish(GDK_CLIPBOARD(inClipboard), inResult, &error);
	if(text != nullptr)
	{
		wait->hasText = true;
		wait->text = text;
		g_free(text);
	}
	if(error != nullptr)
	{
		if(!g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
			OMCLogMessage("the clipboard's text could not be read: %s", error->message);
		g_error_free(error);
	}
	if(wait->abandoned)
	{
		delete wait;
		return;
	}
	wait->answered = true;
	if(g_main_loop_is_running(wait->loop))
		g_main_loop_quit(wait->loop);
}

} // namespace

bool
OMCIsTextInClipboard()
{
	if(OMCTestHostIsActive())
	{
		std::string testText;
		return ReadTestClipboardText(testText);
	}
	GdkClipboard *clipboard = DesktopClipboard();
	if(clipboard == nullptr)
		return false;
	GdkContentFormats *formats = gdk_clipboard_get_formats(clipboard);
	if(formats == nullptr)
		return false;
	// Text this process put there (a string), or a type another app offers that GDK reads as a
	// string: exactly what gdk_clipboard_read_text_async can read (X11 target names such as
	// UTF8_STRING, which some apps also offer, are not among them)
	GdkContentFormats *readable = gdk_content_formats_union_deserialize_gtypes(gdk_content_formats_ref(formats));
	bool isText = gdk_content_formats_contain_gtype(readable, G_TYPE_STRING);
	gdk_content_formats_unref(readable);
	return isText;
}

CFStringRef
OMCCopyClipboardText(long inReplaceOption)
{
	if(OMCTestHostIsActive())
	{
		std::string testText;
		if(!ReadTestClipboardText(testText))
			return nullptr;
		return CreateClipboardString(testText, inReplaceOption);
	}
	GdkClipboard *clipboard = DesktopClipboard();
	if((clipboard == nullptr) || !OMCIsTextInClipboard()) // no text: nothing to read (a read would fail)
		return nullptr;

	ReadWait *wait = new ReadWait();
	wait->loop = g_main_loop_new(nullptr, FALSE);
	GCancellable *cancellable = g_cancellable_new();
	gdk_clipboard_read_text_async(clipboard, cancellable, OnTextRead, wait);
	// A clipboard owner that does not answer: the read is canceled and the wait ends, as GDK does not
	// end every canceled read (one from an owner in this process that never writes waits on). The
	// source is held, so it can be destroyed whether it fired or not, before the wait can be freed.
	wait->cancellable = cancellable;
	GSource *timeout = g_timeout_source_new(kReadTimeoutMilliseconds);
	g_source_set_callback(timeout, [](gpointer inWait) -> gboolean {
		ReadWait *wait = static_cast<ReadWait *>(inWait);
		wait->timedOut = true;
		g_cancellable_cancel(wait->cancellable); // may answer the read at once, which ends the wait
		if(g_main_loop_is_running(wait->loop))
			g_main_loop_quit(wait->loop);
		return G_SOURCE_REMOVE;
	}, wait, nullptr);
	(void)g_source_attach(timeout, nullptr);
	if(!wait->answered)
		OMCRunModalLoop(wait->loop); // returns at the answer, at the time limit, or when a quit ends it
	g_source_destroy(timeout);
	g_source_unref(timeout);
	wait->cancellable = nullptr;
	g_main_loop_unref(wait->loop);
	wait->loop = nullptr;

	bool hasText = false;
	std::string text;
	if(wait->answered)
	{
		hasText = wait->hasText;
		text = std::move(wait->text);
		delete wait;
	}
	else
	{
		// Ended by a quit or the time limit: the read is canceled, and its callback, when it comes,
		// frees the wait (a read GDK never ends keeps it)
		if(wait->timedOut)
			OMCLogMessage("the clipboard's owner did not give its text within %u ms: no clipboard text", kReadTimeoutMilliseconds);
		wait->abandoned = true;
		g_cancellable_cancel(cancellable);
	}
	g_object_unref(cancellable);
	if(!hasText)
		return nullptr;
	return CreateClipboardString(text, inReplaceOption);
}

bool
OMCPasteIntoFrontApp()
{
	static std::atomic<bool> sLogged {false};
	if(!sLogged.exchange(true))
		OMCLogMessage("PASTE_AFTER_EXECUTION: Linux has no way to paste into another app (Wayland sends no keystrokes for an app); nothing is pasted");
	return false;
}

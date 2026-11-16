//
//  OMCAppletMain.cpp
//  Abracode
//
//  The Linux applet's app shell: an AdwApplication
//  that reports the app's events to the portable applet (OMCApplet.h) and lifecycle
//  (OMCAppLifecycle.h), as EntryPoints/Apple/OMCAppletController.mm does on macOS.
//  - startup: the app will launch (app.will.launch); the applet and its menu are made (OMCAppletMenu.h).
//  - command-line (the applet's own, or a second launch's handed over): no arguments is an
//    activate; files go to OMCApplet::OpenURLs (gathered and run as one main command), URLs on
//    another scheme (the applet's own) to OMCApplet::HandleURL exactly as given; the first one
//    also finishes the launch (app.did.launch).
//  - activate: the first one is the untitled launch (the main command, OMCApplet::OpenUntitled),
//    then the launch has finished; a later one is a reopen (a second launch with no files): the
//    main command again when the applet says so, else the app comes to the front.
//  - open (a file manager opening files over D-Bus): as the command line's files and URLs.
//  - shutdown: app.will.terminate.
//  The application is unique by the bundle's identifier: a second launch hands its files to the
//  running applet over D-Bus and exits, as a macOS applet is one process. With no session bus it
//  runs alone (NON_UNIQUE).
//  The applet quits by itself once the launch has finished and it has no window and no command
//  still running: on Linux an applet with no window would otherwise go on running unseen. SIGTERM
//  and SIGINT quit it as its Quit would. Main thread (GLib's default main context) only.
//

#include "OMCAppletMain.h"
#include "OMCAppletMenu.h"
#include "OMCApplet.h"
#include "OMCAppLifecycle.h"
#include "OMCAppShell.h"
#include "OMCCommandRunner.h"
#include "OMCURLParse.h"
#include "OMCEngineActivity.h"
#include "OMCTestHost.h"
#include "ActionUIC.h"
#include "OMCWindowHost.h"
#include "Linux/OMCDesktopRegistration.h"
#include "Linux/OMCRuntimeRecord.h"
#include "OMCLog.h"
#include "ACFString.h"
#include "CFObj.h"
#include <adwaita.h>
#include <glib-unix.h>
#include <signal.h>
#include <cstring>
#include <memory>
#include <string>

namespace
{

// The applet's command file in its bundle (Command.json preferred, OMCCopyCommandFileURL)
CFStringRef CommandFile() { return CFSTR("Command.json"); }

struct AppletHost
{
	std::unique_ptr<OMCApplet>	applet;
	bool						launchFinished {false};
	int							idleChecks {0};		// consecutive idle checks, see CheckIdle
	guint						idleSource {0};
};

AppletHost *sHost = nullptr;

#pragma mark - OMCAppletActions

OSStatus
AppletRunMainCommand(void *inActionContext, CFTypeRef inContext)
{
	(void)inActionContext;
	return OMCRunCommandFromFile(nullptr, CommandFile(), inContext, true /*nav dialog*/, false /*key window*/, nullptr, false, nullptr);
}

void
AppletRunURL(void *inActionContext, CFStringRef inURL)
{
	(void)inActionContext;
	// Parsed by OMCParseURL, which keeps NSURLComponents' rules (OMCURLParse.h), as on macOS
	// (OMCCommandExecutor.mm); the decisions about what the URL may run are OMCRunCommandForURL's
	CFObj<CFStringRef> host;
	CFObj<CFArrayRef> queryItems;
	bool isValidURL = (inURL != nullptr) && (CFStringGetLength(inURL) > 0) && OMCParseURL(inURL, host, queryItems);
	OSStatus err = OMCRunCommandForURL(inURL, isValidURL, host, queryItems, CommandFile(), nullptr);
	(void)err;
}

OSStatus
AppletRunService(void *inActionContext, CFStringRef inCommandID, CFArrayRef inFileURLs)
{
	(void)inActionContext;
	// As macOS Services run it (OMCService.m): the command by its id, the files as its context
	return OMCRunCommandFromFile(inCommandID, CommandFile(), inFileURLs, false /*nav dialog*/, false /*key window*/, nullptr, false, nullptr);
}

void
AppletNoteRecentDocument(void *inActionContext, CFURLRef inFileURL)
{
	(void)inActionContext;
	OMCNoteRecentDocument(inFileURL);
}

void
AppletDidOpenGatheredFiles(void *inActionContext)
{
	(void)inActionContext; // a GApplication's open needs no answer
}

#pragma mark - The menu's actions

void
MenuRunMainCommand(void *inContext)
{
	(void)inContext;
	// New and Open, as on macOS (OMCAppletController's newDocument: and openDocument:)
	if((sHost != nullptr) && sHost->applet)
		sHost->applet->RunMainCommand();
}

void
MenuOpenFile(void *inContext, CFURLRef inFileURL)
{
	(void)inContext;
	// An Open Recent item, as on macOS: notes it as recent again and runs the main command with it
	if((sHost != nullptr) && sHost->applet && (inFileURL != nullptr))
		sHost->applet->OpenFile(inFileURL);
}

void
MenuQuit(void *inContext)
{
	(void)inContext;
	OMCQuitThisApp();
}

#pragma mark - The application's signals

// The launch has finished: the startup modifiers no longer count, then app.did.launch
void
FinishLaunching()
{
	if((sHost == nullptr) || sHost->launchFinished)
		return;
	sHost->launchFinished = true;
	sHost->applet->DidFinishLaunching();
	OMCHandleAppLifecycleEvent(OMCAppLifecycleEvent::DidLaunch);
	// Which Swift runtime this applet uses, for command-engine-cleanup
	OMCRecordRuntimeUse();
	// Whether this copy is on the desktop's app list, and the question if not (in the background)
	OMCOfferDesktopRegistration();
}

long
AppWindowCount(GApplication *inApp)
{
	return (long)g_list_length(gtk_application_get_windows(GTK_APPLICATION(inApp)));
}

void
OnStartup(GApplication *inApp, gpointer)
{
	(void)inApp;
	// ActionUI's main-actor work (its C calls from other threads, the remote bridge's answers) runs
	// under GLib's loop from now, not only once the first window is filled: the launch commands and
	// a Python handler may need it before any window
	actionUIInstallMainLoopBridge();
	OMCHandleAppLifecycleEvent(OMCAppLifecycleEvent::WillLaunch);
	OMCAppletActions actions;
	actions.runMainCommand = AppletRunMainCommand;
	actions.runURL = AppletRunURL;
	actions.noteRecentDocument = AppletNoteRecentDocument;
	actions.didOpenGatheredFiles = AppletDidOpenGatheredFiles;
	actions.runService = AppletRunService;
	actions.context = nullptr;
	sHost->applet.reset(new OMCApplet(actions));
	// The menu in every window's header bar: New, Open, the applet's MainMenu.json, Quit
	OMCAppletMenuActions menuActions {};
	menuActions.runMainCommand = MenuRunMainCommand;
	menuActions.openFile = MenuOpenFile;
	menuActions.quit = MenuQuit;
	menuActions.context = nullptr;
	CFObj<CFArrayRef> mainMenu(OMCCopyAppletMainMenuElements());
	(void)OMCInstallAppletMenu(mainMenu, CommandFile(), menuActions);
	// Released only by quitting: the idle check below decides when an applet with nothing to show is done
	g_application_hold(inApp);
}

void
OnActivate(GApplication *inApp, gpointer)
{
	if(!sHost->applet)
		return;
	sHost->idleChecks = 0; // an event restarts the idle count (CheckIdle)
	if(!sHost->launchFinished)
	{
		(void)sHost->applet->OpenUntitled();
		FinishLaunching();
		return;
	}
	bool hasVisibleWindows = false;
	for(GList *window = gtk_application_get_windows(GTK_APPLICATION(inApp)); window != nullptr; window = window->next)
		hasVisibleWindows = hasVisibleWindows || gtk_widget_get_visible(GTK_WIDGET(window->data));
	if(sHost->applet->ShouldHandleReopen(hasVisibleWindows, OMCOpenHostedWindowCount(), AppWindowCount(inApp)))
		sHost->applet->RunMainCommand();
	else
		OMCActivateThisApp();
}

void
OnOpen(GApplication *inApp, GFile **inFiles, gint inFileCount, const gchar *inHint, gpointer)
{
	(void)inApp;
	(void)inHint;
	if(!sHost->applet)
		return;
	sHost->idleChecks = 0; // an event restarts the idle count: files gathered now count (CheckIdle)
	CFObj<CFMutableArrayRef> fileURLs(CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks));
	for(gint i = 0; i < inFileCount; i++)
	{
		gchar *uri = g_file_get_uri(inFiles[i]);
		if(uri == nullptr)
			continue;
		if(g_file_has_uri_scheme(inFiles[i], "file"))
		{
			CFObj<CFURLRef> url(CFURLCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)uri, (CFIndex)strlen(uri), kCFStringEncodingUTF8, nullptr));
			if(url != nullptr)
				CFArrayAppendValue(fileURLs, url);
		}
		else
		{
			CFObj<CFStringRef> urlString(CFStringCreateWithCString(kCFAllocatorDefault, uri, kCFStringEncodingUTF8));
			if(urlString != nullptr)
				sHost->applet->HandleURL(urlString);
		}
		g_free(uri);
	}
	if(CFArrayGetCount(fileURLs) > 0)
		sHost->applet->OpenURLs(fileURLs);
	FinishLaunching();
}

// The file manager's request to run one of the applet's services (the Command Workshop file manager plug-in):
// --command-service <command id> <file or file URI>... The applet runs only a command its Info.plist
// offers as a file service (OMCApplet::RunService).
const char *kServiceOption = "--command-service";

// The command line's files (from inFirst on), each a path relative to the launching shell's folder
// or a file:// URI, as file URLs; an argument on another scheme is no file and is left out
CFMutableArrayRef
CreateFileURLsFromArguments(GApplicationCommandLine *inCommandLine, gchar **inArguments, gint inFirst, gint inCount)
{
	CFMutableArrayRef fileURLs = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
	for(gint i = inFirst; (fileURLs != nullptr) && (i < inCount); i++)
	{
		const char *scheme = g_uri_peek_scheme(inArguments[i]); // interned, lowercase; not freed
		if( (scheme != nullptr) && (strcmp(scheme, "file") != 0) )
			continue;
		GFile *file = g_application_command_line_create_file_for_arg(inCommandLine, inArguments[i]);
		gchar *uri = g_file_get_uri(file);
		if(uri != nullptr)
		{
			CFObj<CFURLRef> url(CFURLCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)uri, (CFIndex)strlen(uri), kCFStringEncodingUTF8, nullptr));
			if(url != nullptr)
				CFArrayAppendValue(fileURLs, url);
			g_free(uri);
		}
		g_object_unref(file);
	}
	return fileURLs;
}

// --command-service <command id> <files>: the service runs, or the refusal is logged (the id cut short:
// it is the sender's)
void
RunServiceRequest(GApplicationCommandLine *inCommandLine, gchar **inArguments, gint inCount)
{
	CFObj<CFStringRef> commandID;
	if(inCount > 2)
		commandID.Adopt(CFStringCreateWithCString(kCFAllocatorDefault, inArguments[2], kCFStringEncodingUTF8));
	CFObj<CFMutableArrayRef> fileURLs(CreateFileURLsFromArguments(inCommandLine, inArguments, 3, inCount));
	CFBundleRef mainBundle = CFBundleGetMainBundle();
	CFDictionaryRef info = (mainBundle != nullptr) ? CFBundleGetInfoDictionary(mainBundle) : nullptr;
	const char *refusal = nullptr;
	(void)sHost->applet->RunService(commandID, fileURLs, info, &refusal);
	if(refusal != nullptr)
	{
		CFObj<CFStringRef> loggedID;
		if((commandID != nullptr) && (CFStringGetLength(commandID) > 128))
			loggedID.Adopt(CFStringCreateWithSubstring(kCFAllocatorDefault, commandID, CFRangeMake(0, 128)));
		else
			loggedID.Adopt(commandID.Get(), kCFObjRetain);
		OMCLogMessage("service refused for command id \"%s\": %s", OMCLogCString(loggedID).c_str(), refusal);
	}
}

// The applet's command line, its own or a second launch's handed over: no arguments is an
// activate; --command-service first is a service request (RunServiceRequest); otherwise a URL on a
// scheme other than file (the applet's own) goes to HandleURL exactly as given, and anything else
// is a file, relative to the launching shell's folder. GApplication's own open would pass every
// argument through GFile, which rewrites a URL ("app://host?q" becomes "app://host/?q"); open stays
// connected for file managers that open files over D-Bus.
int
OnCommandLine(GApplication *inApp, GApplicationCommandLine *inCommandLine, gpointer)
{
	if(!sHost->applet)
		return 1;
	sHost->idleChecks = 0; // an event restarts the idle count: files gathered now count (CheckIdle)
	gint argumentCount = 0;
	gchar **arguments = g_application_command_line_get_arguments(inCommandLine, &argumentCount);
	if(argumentCount <= 1)
	{
		g_strfreev(arguments);
		OnActivate(inApp, nullptr);
		return 0;
	}
	if(strcmp(arguments[1], kServiceOption) == 0)
	{
		RunServiceRequest(inCommandLine, arguments, argumentCount);
		g_strfreev(arguments);
		FinishLaunching();
		return 0;
	}
	CFObj<CFMutableArrayRef> fileURLs(CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks));
	for(gint i = 1; i < argumentCount; i++)
	{
		const char *scheme = g_uri_peek_scheme(arguments[i]); // interned, lowercase; not freed
		bool isURL = (scheme != nullptr) && (strcmp(scheme, "file") != 0);
		if(isURL)
		{
			CFObj<CFStringRef> urlString(CFStringCreateWithCString(kCFAllocatorDefault, arguments[i], kCFStringEncodingUTF8));
			if(urlString != nullptr)
				sHost->applet->HandleURL(urlString);
			continue;
		}
		GFile *file = g_application_command_line_create_file_for_arg(inCommandLine, arguments[i]);
		gchar *uri = g_file_get_uri(file);
		if(uri != nullptr)
		{
			CFObj<CFURLRef> url(CFURLCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)uri, (CFIndex)strlen(uri), kCFStringEncodingUTF8, nullptr));
			if(url != nullptr)
				CFArrayAppendValue(fileURLs, url);
			g_free(uri);
		}
		g_object_unref(file);
	}
	g_strfreev(arguments);
	if(CFArrayGetCount(fileURLs) > 0)
		sHost->applet->OpenURLs(fileURLs);
	FinishLaunching();
	return 0;
}

void
OnShutdown(GApplication *inApp, gpointer)
{
	(void)inApp;
	OMCHandleAppLifecycleEvent(OMCAppLifecycleEvent::WillTerminate);
	sHost->applet.reset();
}

// Idle: the launch has finished, no command is running or waiting to run (a task manager counts
// until its last task and any NEXT_COMMAND_ID it starts are done), and no window is open. Two
// checks in a row, a second apart, with no event in between (an event resets the count), so files
// gathered for 0.25 s and a chain of commands are not cut short.
gboolean
CheckIdle(gpointer inApp)
{
	GApplication *app = G_APPLICATION(inApp);
	// An integration test's launch (OMCTestHost.h) stays until the test ends it: the test drives
	// it over the bridge, and between two of its requests the applet looks idle
	bool idle = sHost->launchFinished && !OMCTestHostIsActive() && (OMCGetUnfinishedTaskManagerCount() == 0) &&
				(OMCOpenHostedWindowCount() == 0) && (AppWindowCount(app) == 0);
	sHost->idleChecks = idle ? (sHost->idleChecks + 1) : 0;
	if(sHost->idleChecks >= 2)
	{
		sHost->idleSource = 0;
		g_application_quit(app);
		return G_SOURCE_REMOVE;
	}
	return G_SOURCE_CONTINUE;
}

// SIGTERM or SIGINT: quit as Quit does (the default application: it may be replaced after the
// handlers are installed, when registering fails)
gboolean
OnQuitSignal(gpointer)
{
	// As OMCQuitThisApp: ends a blocking window's modal run too
	OMCQuitThisApp();
	return G_SOURCE_CONTINUE;
}

} // namespace

int
OMCAppletMain(int argc, char *argv[])
{
	AppletHost host;
	sHost = &host;

	// The application's id is the bundle's identifier when GLib accepts it (reverse DNS); without
	// one the applet is not unique
	std::string identifier;
	CFBundleRef bundle = CFBundleGetMainBundle();
	CFStringRef bundleIdentifier = (bundle != nullptr) ? CFBundleGetIdentifier(bundle) : nullptr;
	if(bundleIdentifier != nullptr)
		identifier = ACFStringToUTF8(bundleIdentifier);
	const char *applicationID = (!identifier.empty() && g_application_id_is_valid(identifier.c_str())) ? identifier.c_str() : nullptr;
	if(applicationID == nullptr)
		OMCLogMessage("the bundle identifier \"%s\" is not a valid application id: the applet is not unique", identifier.c_str());

	// The signals are connected before registering, which emits startup in the primary instance
	auto MakeApplication = [&](GApplicationFlags inFlags) {
		AdwApplication *made = adw_application_new(applicationID, inFlags);
		g_signal_connect(made, "startup", G_CALLBACK(OnStartup), nullptr);
		g_signal_connect(made, "activate", G_CALLBACK(OnActivate), nullptr);
		g_signal_connect(made, "open", G_CALLBACK(OnOpen), nullptr);
		g_signal_connect(made, "command-line", G_CALLBACK(OnCommandLine), nullptr);
		g_signal_connect(made, "shutdown", G_CALLBACK(OnShutdown), nullptr);
		return made;
	};
	const GApplicationFlags flags = (GApplicationFlags)(G_APPLICATION_HANDLES_OPEN | G_APPLICATION_HANDLES_COMMAND_LINE);
	AdwApplication *app = MakeApplication(flags);

	// Before registering, which runs app.will.launch: a SIGTERM during it quits cleanly once the
	// main loop runs, rather than ending the process at once
	guint termSource = g_unix_signal_add(SIGTERM, OnQuitSignal, nullptr);
	guint intSource = g_unix_signal_add(SIGINT, OnQuitSignal, nullptr);

	GError *error = nullptr;
	if(!g_application_register(G_APPLICATION(app), nullptr, &error))
	{
		// No session bus: run alone
		OMCLogMessage("the applet runs alone (no single instance): %s", (error != nullptr) ? error->message : "registration failed");
		g_clear_error(&error);
		g_object_unref(app);
		app = MakeApplication((GApplicationFlags)(flags | G_APPLICATION_NON_UNIQUE));
	}

	if(g_application_get_is_remote(G_APPLICATION(app)))
	{
		// A second launch: it hands its arguments over and exits; its main loop never runs, so the
		// handlers would only swallow Ctrl-C while it waits for the running applet
		g_source_remove(intSource);
		g_source_remove(termSource);
		intSource = 0;
		termSource = 0;
	}
	else
	{
		host.idleSource = g_timeout_add_seconds(1, CheckIdle, app);
	}

	int status = g_application_run(G_APPLICATION(app), argc, argv);

	if(host.idleSource != 0)
		g_source_remove(host.idleSource);
	if(intSource != 0)
		g_source_remove(intSource);
	if(termSource != 0)
		g_source_remove(termSource);
	g_object_unref(app);
	sHost = nullptr;
	return status;
}

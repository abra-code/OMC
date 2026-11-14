//
//  OMCApplet.h
//  Abracode
//
//  What an applet does when the app is asked to open files, a URL, a new or untitled document,
//  or to reopen: the applet's decisions, portable C++ on CF. The platform's app
//  delegate reports each request (on macOS, EntryPoints/Apple/OMCAppletController.mm) and supplies what only it
//  can do through OMCAppletActions: run the applet's main command or a URL, note a recent
//  document, and answer the system once gathered files are open. Main thread.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <memory>
#include "CFObj.h"

class OMCScheduledCall;

struct OMCAppletActions
{
	// Runs the applet's main command with inContext (NULL, a file URL, or a CFArray of them), the
	// open panel allowed for a command that needs files and got none, no key-window routing.
	// Returns its status.
	OSStatus (*runMainCommand)(void *inActionContext, CFTypeRef inContext);

	// Runs what a URL sent to the applet asks for (OMCRunCommandForURL's rules).
	void (*runURL)(void *inActionContext, CFStringRef inURL);

	// Adds a file to the app's recent documents.
	void (*noteRecentDocument)(void *inActionContext, CFURLRef inFileURL);

	// Gathered files were opened (OpenURLs): the system may be told the open succeeded.
	void (*didOpenGatheredFiles)(void *inActionContext);

	// Runs the command inCommandID with inFileURLs (a CFArray of file URLs) as its context, no open
	// panel, no key-window routing: a service request the applet allowed (RunService). Returns its
	// status. NULL where the platform makes no such request (macOS: Services call OMCService.m).
	OSStatus (*runService)(void *inActionContext, CFStringRef inCommandID, CFArrayRef inFileURLs) {nullptr};

	void *context;
};

// Why the applet's Info.plist (inInfo) does not offer inCommandID as a service for files, or NULL
// when it does: an NSServices item whose NSUserData is the command id and whose NSSendFileTypes is
// a non-empty array, or whose NSSendTypes names files the older way ("NSFilenamesPboardType", as
// AppletBuilder writes it, or "public.file-url"). Only a command an applet declares so is run for a
// service request, as macOS Services call only the commands an applet declares. The reason is a
// static string.
const char *OMCAppletFileServiceRefusal(CFDictionaryRef inInfo, CFStringRef inCommandID);

class OMCApplet
{
public:
	explicit			OMCApplet(const OMCAppletActions &inActions);
						~OMCApplet();

	// The modifier keys held when the app started (an OMCModifierKeys mask). Option held at
	// startup means: open nothing, neither the files the app was started with nor an untitled
	// document, until the launch has finished.
	void				SetStartupModifiers(uint32_t inModifiers) { mStartupModifiers = inModifiers; }

	// The launch has finished: the startup modifiers no longer count.
	void				DidFinishLaunching();

	// The app was started without files: runs the main command with no context, unless Option was
	// held at startup. True when it ran without error.
	bool				OpenUntitled();

	// New or Open in the File menu: runs the main command with no context.
	void				RunMainCommand();

	// One file to open (Open Recent, the open panel): notes it as recent, runs the main command with it.
	void				OpenFile(CFURLRef inFileURL);

	// Files to open at once: notes each as recent, runs the main command with all of them.
	void				OpenFiles(CFArrayRef inFileURLs);

	// URLs the system asks the app to open (Finder, a drop on the icon). Only file URLs are kept (a URL
	// on the applet's own scheme is HandleURL's, with its rules); they are gathered for 0.25 s, as
	// Finder sends a drop in several calls, then opened in one OpenFiles, and didOpenGatheredFiles
	// is called. Nothing when Option was held at startup and the launch has not finished.
	void				OpenURLs(CFArrayRef inURLs);

	// A URL sent to the applet: runs what it asks for.
	void				HandleURL(CFStringRef inURL);

	// A service request (on Linux, the file manager's Services menu: the applet started with
	// --command-service): runs inCommandID with the file URLs among inURLs (each with an absolute path),
	// when inInfo (the applet's Info.plist) offers it as a file service (OMCAppletFileServiceRefusal)
	// and there is a file. Otherwise nothing runs, *outRefusal says why (a static string) and
	// errAEEventNotPermitted is returned. No files are noted as recent: a service is not an open.
	OSStatus			RunService(CFStringRef inCommandID, CFArrayRef inURLs, CFDictionaryRef inInfo, const char **outRefusal);

	// The app was asked to reopen (a click on its Dock icon): true when the main command should run
	// again. Never while a command is starting; otherwise only when the system sees no visible
	// window and none of the framework's hosted windows nor any app window is open
	// (inAppWindowCount -1: not known, which counts as open).
	bool				ShouldHandleReopen(bool inHasVisibleWindows, int inHostedWindowCount, long inAppWindowCount) const;

private:
	static void			OpenGatheredFiles(void *inContext);
	bool				IsOpeningSuppressed() const;

	OMCAppletActions					mActions;
	bool								mStartingUp {true};
	uint32_t							mStartupModifiers {0};
	int									mRunningCommandCount {0}; // > 0 while a command call is in progress
	CFObj<CFMutableArrayRef>			mPendingFiles;
	std::unique_ptr<OMCScheduledCall>	mGatherCall; // the pending OpenGatheredFiles, canceled by a newer one
	bool								mOpeningGatheredFiles {false}; // an OpenGatheredFiles is running its command
	bool								mGatheredFilesWaiting {false}; // its gathering ended during that command
};

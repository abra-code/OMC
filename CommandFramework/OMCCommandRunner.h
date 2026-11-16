//
//  OMCCommandRunner.h
//  Abracode
//
//  Running a command of an applet's command file, and the rules for a command started by a URL:
//  the portable core of OMCCommandExecutor (C++ on CF). The platform layer supplies what only
//  it can do through OMCRunHooks (on macOS, OMCCommandExecutor.mm: the key window, Open Recent,
//  the delegate's observer) and parses URLs (NSURLComponents there).
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include "OMC.h"

struct OMCRunHooks
{
	// When the key window belongs to OMC, runs the command as that window's subcommand, so it
	// inherits the window's dialog context and control values, and returns true. May be NULL.
	bool (*dispatchToKeyWindow)(void *inHookContext, CFStringRef inCommandNameOrId, CFTypeRef inContext);

	// Notes files the user chose in the open panel as recently used. May be NULL.
	void (*noteRecentFiles)(void *inHookContext, CFArrayRef inFileURLs);

	// Called just before the command runs, only when everything else succeeded: returns an
	// observer to add to the run (+1, the runner releases it), or NULL. May be NULL.
	OMCObserverRef (*createObserver)(void *inHookContext);

	void *context;
};

// The command file a name stands for (+1, or NULL): an absolute or "~" path as it is, else a
// Command.json or Command.plist of that base name in the main bundle (JSON preferred). What the
// runner reads for a name other than an .omc bundle, and what the app's Commands menu shows (for
// the menu an absolute path to an .omc bundle is a command file too: OnMyCommand reads a bundle).
CFURLRef OMCCopyCommandFileURL(CFStringRef inFileName);

// Runs a command of a command file (a Command.json/.plist name or path, or an .omc bundle).
// inContext: text (CFString), a file (CFURL), files (CFArray of CFURL), or NULL.
// With inAllowNavDialog, a command that needs files and got none asks for them in the open panel.
// inTriggerURL: the URL that started the run (OMC_TRIGGER_URL), or NULL.
// inRequireURLInvocable: the command id came from the URL itself, so the command must allow it.
OSStatus OMCRunCommandFromFile(CFStringRef inCommandNameOrId, CFStringRef inCommandFile, CFTypeRef inContext,
								bool inAllowNavDialog, bool inAllowKeyWindowSubcommand,
								CFStringRef inTriggerURL, bool inRequireURLInvocable, const OMCRunHooks *inHooks);

// Runs what a URL sent to the applet asks for. The platform parses the URL; inIsValidURL false
// means its parser refused it. inHost: the URL's host, percent-decoded, or NULL. inQueryItems: the
// query's items in order, each a two-element CFArray of name and value (percent-decoded), where
// either may be kCFNull when it does not decode, and the value is kCFNull for an item without "=".
// An "exe" host runs the URL's commandID with its text or file context, if the command allows it;
// any other URL goes, as text, to the applet's omc.app.handle-url command.
OSStatus OMCRunCommandForURL(CFStringRef inURLString, bool inIsValidURL, CFStringRef inHost, CFArrayRef inQueryItems,
							CFStringRef inCommandFile, const OMCRunHooks *inHooks);

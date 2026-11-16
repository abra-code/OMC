//
//  OMCDesktopRegistration.h
//  Abracode
//
//  The Linux applet's place on the desktop (design: Private/linux-applet-install-design.md,
//  "Piece 3 plan"): whether this copy of the applet is on the desktop's app list, asked of its own
//  install script (Contents/Linux/install-applet.sh --status), and then:
//  - not on it: an alert offers to add it (the app list and the file managers' Services menu), with
//    Add, Not Now and Never (do not ask again);
//  - on it for a copy that is no longer there (the applet was moved): this copy is added without
//    asking;
//  - on it for this copy, for another copy that is there, or declined before: nothing.
//  The app menu's Add to Desktop / Remove from Desktop item (EntryPoints/Linux/OMCAppletMenu) follows
//  the state through the listener and changes it with OMCAddToDesktop and OMCRemoveFromDesktop.
//  The script does the work (--register, --unregister, --decline). Nothing in a test launch or
//  without the script; with COMMAND_ENGINE_NO_DESKTOP_PROMPT set in the environment (AppletBuilder's
//  Run sets it for the project it runs) the state is asked, for the menu, but the question is not
//  asked and a moved copy is not registered (a development build keeps off the user's entry). Linux only; main
//  thread only.
//

#pragma once

typedef enum
{
	kOMCDesktopStateUnknown,		// not asked yet, or the script could not tell
	kOMCDesktopStateNotOnDesktop,	// not on the app list, or on it for another copy
	kOMCDesktopStateOnDesktop		// this copy is on the app list
} OMCDesktopState;

typedef void (*OMCDesktopStateListener)(OMCDesktopState inState, void *inContext);

// Starts the check: returns at once; the script runs in the background and the alert, if any, comes
// once it answered. Called once the launch has finished.
void OMCOfferDesktopRegistration();

// Who hears each state the script reports: the launch's, and the one after every add or remove
// (one listener; NULL for none)
void OMCSetDesktopStateListener(OMCDesktopStateListener inListener, void *inContext);

// Adds this copy to the app list and the file managers' Services (--register), in the background;
// the listener hears the new state. Nothing before OMCOfferDesktopRegistration found the script,
// nor while an add or remove (or the launch's registration of a moved copy) still runs.
void OMCAddToDesktop();

// Takes it off (--unregister) and remembers not to ask at launch again (--decline), in the
// background; the listener hears the new state. Nothing when OMCAddToDesktop would do nothing.
void OMCRemoveFromDesktop();

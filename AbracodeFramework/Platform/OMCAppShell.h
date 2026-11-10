//
//  OMCAppShell.h
//  Abracode
//
//  The applet's app shell: what a platform supplies around the engine to make an applet an app.
//  The rules are portable; a platform's shell only reports events to them and draws what they
//  give it:
//  - lifecycle: report launch, activation, deactivation and quit to OMCHandleAppLifecycleEvent
//    (OMCAppLifecycle.h);
//  - opened and dropped files, New and Open, the untitled launch, URLs and reopen: report them to
//    an OMCDroplet and supply its OMCDropletActions (OMCDroplet.h);
//  - the Commands menu: draw OMCBuildCommandsMenuModel's model and run what
//    OMCCommandsMenuItemCommandToRun answers for a chosen item (OMCMenuModel.h);
//  - Open Recent: keep the documents OMCNoteRecentDocument adds, and open a chosen one as the droplet's
//    OpenFile;
//  - and the three calls below, which the engine makes of the shell.
//  The macOS shell is EntryPoints/Apple (OMCDropletController, OMCMainMenuController,
//  OMCCommandMenu, OMCMenuItem) with these calls in Platform/Apple/OMCAppShell.mm.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// This app as omc_dialog_control's omc_application targets it: makes it the active app (omc_select),
// or quits it as its Quit menu item would (omc_terminate_ok)
void OMCActivateThisApp(void);
void OMCQuitThisApp(void);

// Adds a file to this app's recent documents (Open Recent); nothing during a test launch or where
// unsupported
void OMCNoteRecentDocument(CFURLRef fileURL);

#ifdef __cplusplus
}
#endif

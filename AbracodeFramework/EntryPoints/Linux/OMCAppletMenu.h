//
//  OMCAppletMenu.h
//  Abracode
//
//  The Linux applet's menu: what macOS puts in the menu bar (EntryPoints/Apple/OMCMainMenuController,
//  OMCCommandMenu, the File menu's New and Open), in each window's primary menu in the header bar,
//  which ActionUI makes from menu bar JSON (actionUILoadMenuBarJSON). OMC writes that JSON:
//  - New (Ctrl+N) and Open... (Ctrl+O), which run the main command, as on macOS;
//  - the applet's MainMenu.json: its Buttons run the command their actionID names, a CommandMenu
//    with "autoPopulate" is the Commands menu (every command of the command file, in submenus by
//    SUBMENU_NAME, OMCMenuModel.h);
//  - Quit (Ctrl+Q).
//  A MainMenu.json CommandGroup "replacing" New, Open, their group (newItem), the File menu, or Quit
//  (quit, appTermination) takes OMC's item away, as it takes the standard item away on macOS.
//  Every item gets an action id of OMC's own ("omc.menu.<n>") with a handler for it: the ids the
//  JSON gives are command ids, and through ActionUI's default handler a chosen item would reach the
//  active command window as one of its subcommands. A chosen command runs as from the macOS menu:
//  as the key command window's subcommand when that window has it, with the open panel for a
//  command that needs files and got none. Linux only; main thread only.
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>

struct OMCAppletMenuActions
{
	void (*runMainCommand)(void *inContext);	// New and Open
	void (*quit)(void *inContext);
	void *context;
};

// The menu bar elements of the main bundle's MainMenu.json (+1), or NULL when there is none or it
// is not a JSON array (logged).
CFArrayRef OMCCopyAppletMainMenuElements();

// Loads the applet's menu into ActionUI's primary menu: OMC's items and inMainMenuElements (may be
// NULL), commands from inCommandFile (OMCRunCommandFromFile's name or path). Call once, when the
// application starts. False when ActionUI refused the JSON (logged).
bool OMCInstallAppletMenu(CFArrayRef inMainMenuElements, CFStringRef inCommandFile, const OMCAppletMenuActions &inActions);

//
//  OMCMenuModel.h
//  Abracode
//
//  Commands as a menu, for a host to build its own menu from. Two menus use it:
//  - the contextual menu: the commands a context check offers. The engine fills it
//    (OnMyCommand::PopulateItemsMenu); macOS builds the contextual menu plugin's Apple event list
//    from it (EntryPoints/Apple/OnMyCommandAE.cp);
//  - the app's Commands menu: every command of the applet's command file, with no context check
//    (OMCBuildCommandsMenuModel); macOS builds an NSMenu from it (EntryPoints/Apple/OMCCommandMenu.mm).
//  Portable.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <vector>
#include "CFObj.h"

struct OMCMenuItemEntry
{
	CFObj<CFStringRef>	submenuPath;	// "/" for the top level, else "/Group/Subgroup" (SUBMENU_NAME)
	CFObj<CFStringRef>	name;			// the command's name, localized; NULL in the Commands menu when
										// the command has none (its submenus are still made)
	CFObj<CFStringRef>	commandID;		// the Commands menu: the command's COMMAND_ID ("top!" for a
										// command without one of its own)
	SInt32				commandRef {0};	// the contextual menu: kCMCommandStart + the command's index,
										// what HandleSelection takes
};

struct OMCMenuModel
{
	std::vector<OMCMenuItemEntry>	items;	// in the command file's order
};

// The app's Commands menu for a command file (OMCCopyCommandFileURL): every command that is not a
// subcommand and not DISABLED, in the file's order. A name is the NAME's parts joined as written
// (dynamic parts are not resolved) and, for a command with a LOCALIZATION_TABLE_NAME, localized
// from that table. A SUBMENU_NAME ".." is the top level, and any other that does not start with
// "/" gets one. False, with no items, when the file does not load.
bool OMCBuildCommandsMenuModel(CFURLRef inCommandFileURL, OMCMenuModel &outMenu) noexcept;

// The submenus a submenu path walks down, from the top level: none for "/" or an empty path. The
// path is read as a folder path: "/A/B" is A, then B; a trailing "/" changes nothing. Two kept
// quirks of the CFURL walk this was: an empty component ends the walk ("/A//B" is B alone), and
// so does a "." or ".." component ("/A/../B" is B alone; the walk never ended before, and the
// app crashed).
std::vector<CFObj<CFStringRef>> OMCCopySubmenuNames(CFStringRef inSubmenuPath);

// The command a Commands menu item runs: its command id, or its name when the id is NULL, empty
// or "top!" (a command without an id of its own is found by its name). NULL when both are NULL.
// Not retained: one of the two arguments.
CFStringRef OMCCommandsMenuItemCommandToRun(CFStringRef inCommandID, CFStringRef inName) noexcept;

//
//  OMCMenuModel.h
//  Abracode
//
//  The commands a context check offers, as a menu: what the contextual menu shows. The engine fills
//  it (OnMyCommandCM::PopulateItemsMenu); a host builds its own menu from it (macOS: the contextual
//  menu plugin's Apple event list, EntryPoints/Apple/OnMyCommandAE.cp). Portable.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <vector>
#include "CFObj.h"

struct OMCMenuItemEntry
{
	CFObj<CFStringRef>	submenuPath;	// "/" for the top level, else "/Group/Subgroup" (SUBMENU_NAME)
	CFObj<CFStringRef>	name;			// the command's name, dynamic parts resolved and localized
	SInt32				commandRef {0};	// kCMCommandStart + the command's index: what HandleSelection takes
};

struct OMCMenuModel
{
	std::vector<OMCMenuItemEntry>	items;	// in the command file's order
};

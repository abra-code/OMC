//
//  OMCHostSelection.h
//  Abracode
//
//  What a contextual menu host handed over with a menu request, already converted to CoreFoundation
//  by its entry point (macOS: EntryPoints/Apple/OnMyCommandAE.cp, from the Apple event descriptor
//  Shortcuts.app passes to the contextual menu plugin). The engine's context check reads only this,
//  never the host's own types. Portable.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <functional>
#include "CFObj.h"

struct OMCHostSelection
{
	bool					isNull {true};	// no selection at all
	CFObj<CFArrayRef>		files;			// the selected items as CFURLs when the selection is a list; NULL otherwise
	CFObj<CFStringRef>		text;			// the selected text, raw: a command's TEXT_REPLACE_OPTION applies when it takes it

	// ShortcutObserver with Finder in front: whether the one selected folder is the open Finder window
	// itself (a click in the window's background), not an item in it. Valid only during the menu
	// request; empty when the host cannot tell.
	std::function<bool()>	isClickInOpenFinderWindow;
};

//
//  OMCWindowHost.h
//  Abracode
//
//  A window around one of the framework's built-in ActionUI documents (BuiltInDocuments/): the
//  progress window and the output window now, the input dialog next (Private/phase2-builtin-
//  actionui-windows-design.md). Each window's logic is portable C++ over ActionUI's C interface
//  (ActionUIC.h), addressing the document by its window UUID; the host only makes the platform's
//  window around it, places it, shows it and closes it. The command dialogs move onto the same
//  host in Phase 5.
//
//  macOS: an NSWindow (an NSPanel for the floating levels) around the ObjC adapter's hosting view
//  (Platform/Apple/OMCWindowHost.mm), as OMC's other ActionUI windows are made. Linux: ActionUIApp's
//  windows (later); levels and placement are hints there, which a Wayland desktop ignores.
//
//  Main thread only.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <functional>
#include <memory>

enum class OMCHostedWindowLevel
{
	normal,
	floating,	// above normal windows while the app is active, hidden while it is not (macOS: a utility panel)
	utility		// above every app's windows and shown while the app is not active (macOS: a utility panel at
				// the utility level), for a process that is not a regular app, whose floating windows never show
};

enum class OMCHostedWindowPlacement
{
	standard,		// the platform's place for a new window (macOS: centered, a little above the middle)
	alert,			// centered horizontally, with about a fifth of the screen above it
	screenCenter,	// the window's middle at the middle of the screen
	absolute,		// the top-left corner at absoluteLeft, absoluteTop, or the middle at fractionLeft, fractionTop
	cascade			// below and to the right of the previous cascaded window, from the screen's top-left corner
};

struct OMCHostedWindowSpec
{
	CFStringRef			documentName {nullptr};		// a JSON resource of the framework, without ".json"
	CFStringRef			title {nullptr};
	double				contentWidth {0};			// 0: the document's own size
	double				contentHeight {0};
	bool				closable {true};			// a close button in the title bar, and Command-W
	bool				resizable {true};
	OMCHostedWindowLevel level {OMCHostedWindowLevel::normal};
	OMCHostedWindowPlacement placement {OMCHostedWindowPlacement::standard};
	// absolute placement, in points from the top-left corner of the main screen's visible area
	double				absoluteLeft {0};
	double				absoluteTop {0};
	// absolute placement: the window's middle at this fraction (0 to 1) of the main screen's visible
	// area, from its top-left corner, instead of absoluteLeft or absoluteTop; negative: not used
	double				fractionLeft {-1};
	double				fractionTop {-1};
	CFStringRef			frameAutosaveName {nullptr};	// NULL: the position is not remembered; a saved one wins
};

class OMCHostedWindow
{
public:
	// Closes the window if it is still open, then forgets the document's model
	virtual					~OMCHostedWindow() = default;

	// The document's window UUID, for the ActionUI C calls
	virtual CFStringRef		GetWindowUUID() const = 0;

	virtual void			Show() = 0;

	// Closes the window; the closed-by-user callback does not run
	virtual void			Close() = 0;
};

// Loads the document and makes its window, not shown yet. inOnClosedByUser runs when the user
// closes the window (its close button or Command-W), not when Close() or the destructor closes it,
// and may be empty. Returns nullptr when the document cannot be loaded.
std::unique_ptr<OMCHostedWindow> OMCCreateHostedWindow(const OMCHostedWindowSpec &inSpec, std::function<void()> inOnClosedByUser);

// The next cascaded window starts again at the screen's top-left corner (each command run does this)
void OMCResetHostedWindowCascading();

// How many hosted windows are shown and not closed
int OMCOpenHostedWindowCount();

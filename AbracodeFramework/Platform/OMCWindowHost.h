//
//  OMCWindowHost.h
//  Abracode
//
//  A window around one of the framework's built-in ActionUI documents (BuiltInDocuments/): the
//  progress window, the output window and the input dialog (Private/phase2-builtin-actionui-
//  windows-design.md). Each window's logic is portable C++ over ActionUI's C interface
//  (ActionUIC.h), addressing the document by its window UUID; the host only makes the platform's
//  window around it, places it, shows it and closes it. The ActionUI command windows use it too
//  (Phase 5, OMCActionUIWindow.cpp): a document found by the command, a window UUID the
//  dialog already has, content under the titlebar, size limits from the document, and the frame
//  saved under the window's name.
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
	cascade,		// below and to the right of the previous cascaded window, from the screen's top-left corner
	restoredElseCentered	// the frame saved under frameAutosaveName, else the document's fitting size, centered;
							// a document of fixed size (sizeLimitsFromDocument) keeps its size over a saved frame
};

struct OMCHostedWindowSpec
{
	CFStringRef			documentName {nullptr};		// a JSON resource of the framework, without ".json"
	CFURLRef			documentURL {nullptr};		// instead of documentName: a document anywhere
	CFStringRef			windowUUID {nullptr};		// the document's window UUID; NULL: a new one
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
	bool				miniaturizable {true};		// a minimize button; the normal level only (panels do not minimize)
	// The content spans the titlebar (macOS: a full-size content view), and sizes the document gives
	// or is given are those of the area below the titlebar, as in a SwiftUI window
	bool				contentSpansTitlebar {false};
	// The window's minimum and maximum size are the document's, and a document whose minimum and
	// maximum are the same makes a window of fixed size, which the user cannot resize
	bool				sizeLimitsFromDocument {false};
	// false: the destructor leaves the document's model to the caller (the command windows remove it
	// when their last command ends, OMCActionUIModelLifetime.h)
	bool				removesModelWhenDestroyed {true};
};

class OMCHostedWindow
{
public:
	// Closes the window if it is still open, then forgets the document's model (unless the spec's
	// removesModelWhenDestroyed is false)
	virtual					~OMCHostedWindow() = default;

	// The document's window UUID, for the ActionUI C calls
	virtual CFStringRef		GetWindowUUID() const = 0;

	// Shows the window, and brings it to the front when it is already shown
	virtual void			Show() = 0;

	// Before Show: sizes the window to its document again, in each dimension the spec left at 0,
	// and places it again; for values that change the document's size (a long message)
	virtual void			SizeToContent() = 0;

	// Closes the window; the closed-by-user callback does not run
	virtual void			Close() = 0;

	// Makes the window's title the file's name and has the window represent the file (macOS: the
	// title bar's proxy icon)
	virtual void			SetRepresentedFile(CFURLRef inFileURL) = 0;

	virtual void			SetTitle(CFStringRef inTitle) = 0;

	// Whether the window gets the keyboard's input
	virtual bool			IsKey() const = 0;

	// Puts the window's top-left corner this many points from the top-left corner of the main
	// screen's visible area (absolute placement)
	virtual void			SetTopLeftPosition(double inLeft, double inTop) = 0;

	// Sizes the window so that the area its document lays out in has this size: with
	// contentSpansTitlebar, the area below the titlebar
	virtual void			SetLayoutSize(double inWidth, double inHeight) = 0;

	// Run when the window becomes the one that gets the keyboard's input, and when it stops being
	// that window; either may be empty
	virtual void			SetKeyChangeCallbacks(std::function<void()> inOnBecameKey, std::function<void()> inOnResignedKey) = 0;

	// The platform's window, not retained (macOS: the NSWindow), for what has no portable form: the
	// command windows' INVOKE, which sends Objective-C messages to the window
	virtual void *			GetNativeWindow() const = 0;

	// Shows the window and runs it modally: returns after EndModal(), Close(), or the user closing
	// the window. Its actions still arrive while it runs. The closed-by-user callback of a window
	// run this way must not delete it.
	virtual void			RunModal() = 0;

	// Makes RunModal return; nothing when it is not running
	virtual void			EndModal() = 0;
};

// Loads the document and makes its window, not shown yet. inOnClosedByUser runs when the user
// closes the window (its close button or Command-W), not when Close() or the destructor closes it,
// and may be empty; a close of the native window by other code (macOS: -[NSWindow close]) counts as
// the user's. Returns nullptr when the document cannot be loaded.
std::unique_ptr<OMCHostedWindow> OMCCreateHostedWindow(const OMCHostedWindowSpec &inSpec, std::function<void()> inOnClosedByUser);

// The next cascaded window starts again at the screen's top-left corner (each command run does this)
void OMCResetHostedWindowCascading();

// How many hosted windows are shown and not closed
int OMCOpenHostedWindowCount();

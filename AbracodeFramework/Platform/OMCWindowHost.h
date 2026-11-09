//
//  OMCWindowHost.h
//  Abracode
//
//  A window around one of the framework's built-in ActionUI documents (BuiltInDocuments/): the
//  progress window now, the output window and the input dialog next (Private/phase2-builtin-
//  actionui-windows-design.md). Each window's logic is portable C++ over ActionUI's C interface
//  (ActionUIC.h), addressing the document by its window UUID; the host only makes the platform's
//  window around it, shows it and closes it. The command dialogs move onto the same host in
//  Phase 5.
//
//  macOS: an NSWindow around the ObjC adapter's hosting view (Platform/Apple/OMCWindowHost.mm), as
//  OMC's other ActionUI windows are made. Linux: ActionUIApp's windows (later).
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
	floating	// above normal windows (macOS); a hint the desktop may ignore elsewhere
};

struct OMCHostedWindowSpec
{
	CFStringRef			documentName {nullptr};		// a JSON resource of the framework, without ".json"
	CFStringRef			title {nullptr};
	double				contentWidth {0};			// 0: the document's own size
	double				contentHeight {0};
	bool				closable {true};			// a close button in the title bar
	bool				resizable {true};
	OMCHostedWindowLevel level {OMCHostedWindowLevel::normal};
	CFStringRef			frameAutosaveName {nullptr};	// NULL: the position is not remembered
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
// closes the window with its close button, not when Close() or the destructor closes it, and may
// be empty. Returns nullptr when the document cannot be loaded.
std::unique_ptr<OMCHostedWindow> OMCCreateHostedWindow(const OMCHostedWindowSpec &inSpec, std::function<void()> inOnClosedByUser);

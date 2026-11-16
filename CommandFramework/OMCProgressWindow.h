//
//  OMCProgressWindow.h
//  Abracode
//
//  A command's PROGRESS window: its title, a progress bar (determinate or indeterminate), the last
//  status line and a Stop button. A built-in ActionUI document (BuiltInDocuments/omc_progress.json)
//  in a window of the window host (Platform/OMCWindowHost.h); this is its portable logic, over
//  ActionUI's C interface. OMCDeferredProgress decides when to show it and what to show.
//
//  Main thread only.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <memory>
#include <string>
#include <climits>
#include "CFObj.h"

class OMCHostedWindow;

class OMCProgressWindow
{
public:
	// The window, not shown yet; nullptr when the document cannot be loaded
	static std::unique_ptr<OMCProgressWindow> Create(CFStringRef inTitle);

							~OMCProgressWindow();

	void					Show();

	// inProgress from 0 to 100 shows a determinate bar that only moves forward, a negative value an
	// indeterminate one. inText replaces the status line; NULL keeps it (OMCDeferredProgress relies
	// on that).
	void					SetProgress(double inProgress, CFStringRef inText);

	// The user pressed Stop: the window is closed, and the command's processes are to be stopped
	bool					IsCanceled() const { return mCanceled; }

	// The action ID of the Stop button in the document
	static const char *const kStopActionID;

private:
							OMCProgressWindow() = default;
	void					Stop();
	static void				StopActionHandler(const char *inActionID, const char *inWindowUUID, int64_t inViewID, int64_t inViewPartID, const char *inContextJSON);

	std::unique_ptr<OMCHostedWindow> mWindow;
	std::string				mWindowUUID;
	CFObj<CFStringRef>		mLastText;
	bool					mCanceled {false};
	bool					mIsDeterminate {false};
	int						mLastValue {INT_MIN};	// INT_MIN: no value shown yet
};

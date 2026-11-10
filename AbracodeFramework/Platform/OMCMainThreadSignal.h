//
//  OMCMainThreadSignal.h
//  Abracode
//
//  A callback that runs on the main thread when any thread signals it. Signals that arrive before it
//  runs make one call. Platform code:
//  - macOS: a run loop source in the common modes, so the callback is a run loop callout, as the
//    CFSocket callbacks were. A nested run loop inside it (the drain before the next command, a
//    WAIT_FOR_TASK_COMPLETION wait) then also runs main-queue work, as in released versions.
//  - Linux: a GLib idle source on the default main context, so the callback is a GLib callout. A
//    nested GLib loop inside it (an alert, a file panel, a modal window) then also runs main-queue
//    work, which ActionUI's drawing and remote bridge use; from a main-queue callback it would not
//    (libdispatch does not run the main queue inside its own callout).
//

#pragma once

#include <memory>

// A call OMCMainThreadSignal::ScheduleAfter scheduled: destroying it before the callback starts cancels
// the call. Main thread. A top-level class so that headers can declare it without including this one.
class OMCScheduledCall
{
public:
	virtual					~OMCScheduledCall() = default;
};

class OMCMainThreadSignal
{
public:
	typedef void (*Callback)(void *inContext);
	typedef void (*ContextRelease)(void *inContext);

	// Main thread. The signal owns inContext and calls inRelease on it once inCallback can no longer
	// run, also when this returns nullptr.
	static std::unique_ptr<OMCMainThreadSignal> Create(Callback inCallback, void *inContext, ContextRelease inRelease);

	// Main thread, also from inside the callback. No call starts afterwards. The owner must not
	// destroy it while another thread is in Signal().
	virtual					~OMCMainThreadSignal() = default;

	// Any thread.
	virtual void			Signal() = 0;

	// Main thread: one pass of a nested wait. Returns after a signaled callback or other work ran, or
	// after inTimeoutSeconds. Returns false when the wait must end early (the run loop was stopped).
	static bool				WaitPass(double inTimeoutSeconds);

	// Main thread: runs the work that is ready now, without waiting. Used before a NEXT_COMMAND_ID
	// command starts, so other commands' output and events triggered meanwhile land first.
	static void				RunReadyWork();

	// Main thread: runs inCallback(inContext) once, on the main thread, after inDelaySeconds, also during a
	// nested wait (WaitPass) on both platforms. Returns
	// false when it cannot be scheduled; then nothing runs, and the caller still owns inContext.
	static bool				RunAfter(double inDelaySeconds, Callback inCallback, void *inContext);

	// Main thread: like RunAfter, but the call is canceled when the returned object is destroyed first,
	// and inContext stays the caller's (it must outlive the returned object). The callback may destroy
	// the returned object. nullptr when the call cannot be scheduled; then nothing runs.
	static std::unique_ptr<OMCScheduledCall> ScheduleAfter(double inDelaySeconds, Callback inCallback, void *inContext);
};

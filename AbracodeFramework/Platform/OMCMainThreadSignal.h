//
//  OMCMainThreadSignal.h
//  Abracode
//
//  A callback that runs on the main thread when any thread signals it. Signals that arrive before it
//  runs make one call. Platform code:
//  - macOS: a run loop source in the common modes, so the callback is a run loop callout, as the
//    CFSocket callbacks were. A nested run loop inside it (the drain before the next command, a
//    WAIT_FOR_TASK_COMPLETION wait) then also runs main-queue work, as in released versions.
//  - Linux: the main queue, which ActionUI drains from the GLib loop.
//

#pragma once

#include <memory>

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
};

//
//  OMCMainThreadSignal.cp
//  Abracode
//
//  macOS: a version 0 run loop source in the common modes of the main run loop.
//

#include "OMCMainThreadSignal.h"
#include <CoreFoundation/CoreFoundation.h>
#include "CFObj.h"
#include <unistd.h>

namespace
{

struct SignalContext
{
	OMCMainThreadSignal::Callback		callback;
	void *								context;
	OMCMainThreadSignal::ContextRelease	release;
};

void SignalPerform(void *inInfo)
{
	SignalContext *signalContext = static_cast<SignalContext *>(inInfo);
	signalContext->callback(signalContext->context);
}

// CF calls this when the source is deallocated, after any callout that was running
void SignalContextRelease(const void *inInfo)
{
	SignalContext *signalContext = const_cast<SignalContext *>(static_cast<const SignalContext *>(inInfo));
	if(signalContext->release != nullptr)
		signalContext->release(signalContext->context);
	delete signalContext;
}

class RunLoopSourceSignal : public OMCMainThreadSignal
{
public:
							RunLoopSourceSignal(CFObj<CFRunLoopSourceRef> &ioSource, CFRunLoopRef inRunLoop)
								: mRunLoop(inRunLoop, kCFObjRetain)
							{
								mSource.Swap(ioSource);
							}

							~RunLoopSourceSignal() override
							{
								::CFRunLoopSourceInvalidate(mSource);
							}

	void					Signal() override
							{
								::CFRunLoopSourceSignal(mSource);
								::CFRunLoopWakeUp(mRunLoop);
							}

private:
	CFObj<CFRunLoopSourceRef>	mSource;
	CFObj<CFRunLoopRef>			mRunLoop;
};

} // namespace

std::unique_ptr<OMCMainThreadSignal>
OMCMainThreadSignal::Create(Callback inCallback, void *inContext, ContextRelease inRelease)
{
	SignalContext *signalContext = new SignalContext { inCallback, inContext, inRelease };

	CFRunLoopSourceContext sourceContext = {};
	sourceContext.info = signalContext;
	sourceContext.release = SignalContextRelease;
	sourceContext.perform = SignalPerform;
	CFObj<CFRunLoopSourceRef> source( ::CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &sourceContext) );
	if(source == nullptr)
	{
		SignalContextRelease(signalContext); // no source owns it
		return nullptr;
	}

	CFRunLoopRef runLoop = ::CFRunLoopGetCurrent();
	::CFRunLoopAddSource(runLoop, source, kCFRunLoopCommonModes);
	return std::unique_ptr<OMCMainThreadSignal>( new RunLoopSourceSignal(source, runLoop) );
}

void
OMCMainThreadSignal::WaitPass(double inTimeoutSeconds)
{
	// The default mode, so bridge calls, timers, dialog messages and other commands' output keep running
	// during a wait, as in released versions (owner, 2026-11-06). Not a spin: it sleeps until a source fires.
	//
	// A stop does not end the wait. CFRunLoopStop stops the innermost run of the run loop, so one meant
	// for another level (a timer's, a host's, a test helper's) lands on a pass here instead; it is used
	// up by this pass whatever the wait does next, so ending the wait would not deliver it either. Ending
	// it finished the command with its output unread: the output was lost and the script's pipes closed
	// under it (released since v4.3, whose wait ended on a stop too).
	CFRunLoopRunResult runLoopResult = ::CFRunLoopRunInMode(kCFRunLoopDefaultMode, inTimeoutSeconds, true /*returnAfterSourceHandled*/);
	if(runLoopResult == kCFRunLoopRunFinished)
	{
		// The mode has no sources or timers, so the run returned at once: sleep out the pass rather than
		// spin. Not expected in a command's wait, whose output delivery source is in the common modes.
		(void)::usleep((useconds_t)(inTimeoutSeconds * 1000000.0));
	}
}

namespace
{

struct DelayedCall
{
	OMCMainThreadSignal::Callback	callback;
	void *							context;
};

void DelayedCallFired(CFRunLoopTimerRef, void *inInfo)
{
	DelayedCall *delayedCall = static_cast<DelayedCall *>(inInfo);
	delayedCall->callback(delayedCall->context);
}

void DelayedCallRelease(const void *inInfo)
{
	delete static_cast<const DelayedCall *>(inInfo);
}

} // namespace

bool
OMCMainThreadSignal::RunAfter(double inDelaySeconds, Callback inCallback, void *inContext)
{
	// A one-shot CFRunLoopTimer in the common modes, as released: the run loop holds it while it is
	// scheduled and invalidates it after it fires; CF then releases its info.
	CFRunLoopTimerContext timerContext = {};
	timerContext.info = new DelayedCall { inCallback, inContext };
	timerContext.release = DelayedCallRelease;
	CFObj<CFRunLoopTimerRef> timer( ::CFRunLoopTimerCreate(kCFAllocatorDefault, ::CFAbsoluteTimeGetCurrent() + inDelaySeconds,
															0 /*interval*/, 0 /*flags*/, 0 /*order*/, DelayedCallFired, &timerContext) );
	if(timer == nullptr)
	{
		DelayedCallRelease(timerContext.info);
		return false;
	}
	::CFRunLoopAddTimer(::CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes);
	return true;
}

namespace
{

// The callback and its context, owned by the scheduled call; the timer only points at it
struct ScheduledCallTarget
{
	OMCMainThreadSignal::Callback	callback;
	void *							context;
};

void ScheduledCallFired(CFRunLoopTimerRef, void *inInfo)
{
	// Copied before the call: the callback may destroy the scheduled call, and the target with it
	ScheduledCallTarget target = *static_cast<ScheduledCallTarget *>(inInfo);
	target.callback(target.context);
}

class TimerScheduledCall : public OMCScheduledCall
{
public:
							~TimerScheduledCall() override
							{
								if(mTimer != nullptr)
									::CFRunLoopTimerInvalidate(mTimer); // nothing happens if it already fired
							}

	ScheduledCallTarget		mTarget {};
	CFObj<CFRunLoopTimerRef> mTimer;
};

} // namespace

std::unique_ptr<OMCScheduledCall>
OMCMainThreadSignal::ScheduleAfter(double inDelaySeconds, Callback inCallback, void *inContext)
{
	// A one-shot CFRunLoopTimer in the common modes, like RunAfter's, with no release callback: the
	// target belongs to the scheduled call, so invalidating the timer early is the whole cancel
	std::unique_ptr<TimerScheduledCall> call( new TimerScheduledCall() );
	call->mTarget = { inCallback, inContext };
	CFRunLoopTimerContext timerContext = {};
	timerContext.info = &call->mTarget;
	call->mTimer.Adopt( ::CFRunLoopTimerCreate(kCFAllocatorDefault, ::CFAbsoluteTimeGetCurrent() + inDelaySeconds,
												0 /*interval*/, 0 /*flags*/, 0 /*order*/, ScheduledCallFired, &timerContext) );
	if(call->mTimer == nullptr)
		return nullptr;
	::CFRunLoopAddTimer(::CFRunLoopGetCurrent(), call->mTimer, kCFRunLoopCommonModes);
	return std::unique_ptr<OMCScheduledCall>(call.release());
}

void
OMCMainThreadSignal::RunReadyWork()
{
	// The default mode until a pass handles nothing, as released since v4.0.1. A pass that receives the
	// run loop's own wake-up or a timer message also ends it, so callers that need every queued dialog
	// message also call OMCDialog::ServicePendingMessages().
	CFRunLoopRunResult runLoopResult;
	do
	{
		runLoopResult = ::CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true /*returnAfterSourceHandled*/);
	}
	while(runLoopResult == kCFRunLoopRunHandledSource);
}

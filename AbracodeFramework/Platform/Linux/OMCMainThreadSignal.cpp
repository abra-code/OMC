//
//  OMCMainThreadSignal.cpp
//  Abracode
//
//  Linux: the main queue, which ActionUI drains from the GLib loop. Not built yet: the Linux port has
//  no build. A nested wait (WaitPass) blocks the main thread, so the main queue cannot run during it;
//  WaitPass runs the signaled callbacks itself, and a main-queue drain that comes later finds none.
//

#include "OMCMainThreadSignal.h"
#include <dispatch/dispatch.h>
#include <mutex>
#include <vector>
#include <algorithm>

namespace
{

struct SignalState
{
							~SignalState()
							{
								if(release != nullptr)
									release(context);
							}

	OMCMainThreadSignal::Callback		callback {nullptr};
	void *								context {nullptr};
	OMCMainThreadSignal::ContextRelease	release {nullptr};
	bool								signaled {false};	// guarded by sLock
	bool								valid {true};		// guarded by sLock
};

std::mutex sLock;
std::vector< std::shared_ptr<SignalState> > sPending; // guarded by sLock

dispatch_semaphore_t WakeSemaphore()
{
	static dispatch_semaphore_t sWake = dispatch_semaphore_create(0);
	return sWake;
}

// Main thread
void RunPendingCallbacks()
{
	std::vector< std::shared_ptr<SignalState> > pending;
	{
		std::lock_guard<std::mutex> guard(sLock);
		pending.swap(sPending);
		for(const std::shared_ptr<SignalState> &state : pending)
			state->signaled = false;
	}

	for(const std::shared_ptr<SignalState> &state : pending)
	{
		bool valid = false;
		{
			std::lock_guard<std::mutex> guard(sLock);
			valid = state->valid;
		}
		if(valid)
			state->callback(state->context); // may destroy its signal: this copy keeps the state alive
	}
}

void RunPendingCallbacksOnMainQueue(void *)
{
	RunPendingCallbacks();
}

// Any thread. Queues a signaled state for the main thread: the main queue runs it, or a nested wait does.
void EnqueueSignaled(const std::shared_ptr<SignalState> &inState)
{
	bool scheduleDrain = false;
	{
		std::lock_guard<std::mutex> guard(sLock);
		if(inState->valid && !inState->signaled)
		{
			inState->signaled = true;
			scheduleDrain = sPending.empty();
			sPending.push_back(inState);
		}
	}
	if(scheduleDrain)
		dispatch_async_f(dispatch_get_main_queue(), nullptr, RunPendingCallbacksOnMainQueue);
	dispatch_semaphore_signal(WakeSemaphore());
}

class MainQueueSignal : public OMCMainThreadSignal
{
public:
	explicit				MainQueueSignal(const std::shared_ptr<SignalState> &inState)
								: mState(inState)
							{
							}

							~MainQueueSignal() override
							{
								std::lock_guard<std::mutex> guard(sLock);
								mState->valid = false;
								sPending.erase(std::remove(sPending.begin(), sPending.end(), mState), sPending.end());
							}

	void					Signal() override
							{
								EnqueueSignaled(mState);
							}

private:
	std::shared_ptr<SignalState>	mState;
};

} // namespace

std::unique_ptr<OMCMainThreadSignal>
OMCMainThreadSignal::Create(Callback inCallback, void *inContext, ContextRelease inRelease)
{
	std::shared_ptr<SignalState> state = std::make_shared<SignalState>();
	state->callback = inCallback;
	state->context = inContext;
	state->release = inRelease;
	return std::unique_ptr<OMCMainThreadSignal>( new MainQueueSignal(state) );
}

bool
OMCMainThreadSignal::WaitPass(double inTimeoutSeconds)
{
	// Only the engine's own work (option A): the signaled callbacks. The caller services dialog messages.
	(void)dispatch_semaphore_wait(WakeSemaphore(), dispatch_time(DISPATCH_TIME_NOW, (int64_t)(inTimeoutSeconds * NSEC_PER_SEC)));
	RunPendingCallbacks();
	return true;
}

namespace
{

struct DelayedCall
{
	OMCMainThreadSignal::Callback	callback;
	void *							context;
};

void RunDelayedCall(void *inContext)
{
	DelayedCall *delayedCall = static_cast<DelayedCall *>(inContext);
	delayedCall->callback(delayedCall->context);
}

void DeleteDelayedCall(void *inContext)
{
	delete static_cast<DelayedCall *>(inContext);
}

// On a background queue when the delay has passed. The call joins the signaled callbacks rather than
// going to the main queue directly, so it also runs during a nested wait, as the macOS timer does.
void DelayedCallDue(void *inContext)
{
	std::shared_ptr<SignalState> state = std::make_shared<SignalState>();
	state->callback = RunDelayedCall;
	state->context = inContext;
	state->release = DeleteDelayedCall; // when the last copy of the state goes, after the call
	EnqueueSignaled(state);
}

} // namespace

bool
OMCMainThreadSignal::RunAfter(double inDelaySeconds, Callback inCallback, void *inContext)
{
	dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(inDelaySeconds * NSEC_PER_SEC)),
					dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0),
					new DelayedCall { inCallback, inContext }, DelayedCallDue);
	return true;
}

namespace
{

// The scheduled call is the state's owner: destroying it marks the state invalid, so a due call that
// was not yet run is dropped, like a signal destroyed before its callback ran
class QueueScheduledCall : public OMCScheduledCall
{
public:
	explicit				QueueScheduledCall(const std::shared_ptr<SignalState> &inState)
								: mState(inState)
							{
							}

							~QueueScheduledCall() override
							{
								std::lock_guard<std::mutex> guard(sLock);
								mState->valid = false;
								sPending.erase(std::remove(sPending.begin(), sPending.end(), mState), sPending.end());
							}

private:
	std::shared_ptr<SignalState>	mState;
};

// On a background queue when the delay has passed: joins the signaled callbacks, as RunAfter does
void ScheduledCallDue(void *inContext)
{
	std::shared_ptr<SignalState> *state = static_cast< std::shared_ptr<SignalState> * >(inContext);
	EnqueueSignaled(*state); // nothing when the scheduled call was destroyed meanwhile
	delete state;
}

} // namespace

std::unique_ptr<OMCScheduledCall>
OMCMainThreadSignal::ScheduleAfter(double inDelaySeconds, Callback inCallback, void *inContext)
{
	std::shared_ptr<SignalState> state = std::make_shared<SignalState>();
	state->callback = inCallback;
	state->context = inContext; // the caller's: no release
	dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(inDelaySeconds * NSEC_PER_SEC)),
					dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0),
					new std::shared_ptr<SignalState>(state), ScheduledCallDue);
	return std::unique_ptr<OMCScheduledCall>( new QueueScheduledCall(state) );
}

void
OMCMainThreadSignal::RunReadyWork()
{
	RunPendingCallbacks();
}

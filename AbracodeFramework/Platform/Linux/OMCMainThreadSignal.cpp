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
								bool scheduleDrain = false;
								{
									std::lock_guard<std::mutex> guard(sLock);
									if(mState->valid && !mState->signaled)
									{
										mState->signaled = true;
										scheduleDrain = sPending.empty();
										sPending.push_back(mState);
									}
								}
								if(scheduleDrain)
									dispatch_async_f(dispatch_get_main_queue(), nullptr, RunPendingCallbacksOnMainQueue);
								dispatch_semaphore_signal(WakeSemaphore());
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

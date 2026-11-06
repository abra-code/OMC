//
//  OMCMainThreadSignal.cp
//  Abracode
//
//  macOS: a version 0 run loop source in the common modes of the main run loop.
//

#include "OMCMainThreadSignal.h"
#include <CoreFoundation/CoreFoundation.h>
#include "CFObj.h"

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

bool
OMCMainThreadSignal::WaitPass(double inTimeoutSeconds)
{
	// The default mode, so bridge calls, timers, dialog messages and other commands' output keep running
	// during a wait, as in released versions (owner, 2026-11-06). Not a spin: it sleeps until a source fires.
	CFRunLoopRunResult runLoopResult = ::CFRunLoopRunInMode(kCFRunLoopDefaultMode, inTimeoutSeconds, true /*returnAfterSourceHandled*/);
	return (runLoopResult != kCFRunLoopRunStopped) && (runLoopResult != kCFRunLoopRunFinished);
}

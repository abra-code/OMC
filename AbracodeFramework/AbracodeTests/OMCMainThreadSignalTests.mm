//
//  OMCMainThreadSignalTests.mm
//  AbracodeTests
//
//  The platform layer the engine uses to reach the main thread (Platform/OMCMainThreadSignal.h):
//  a signal that runs a callback on the main thread, a delayed call, and the drain before the next
//  command. The macOS implementation is a run loop source and a run loop timer.
//
//  OMCMainThreadSignal is not exported from Abracode.framework, so its macOS source compiles into this
//  bundle, as the other tests of internal C++ do.
//

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#include "OMCMainThreadSignal.h"
#include "../Platform/Apple/OMCMainThreadSignal.cp"
#include <atomic>

namespace
{

struct CallLog
{
	std::atomic<int>	calls {0};
	std::atomic<bool>	ranOnMainThread {true};
	std::atomic<int>	releases {0};
};

void CountCall(void *inContext)
{
	CallLog *log = static_cast<CallLog *>(inContext);
	if(![NSThread isMainThread])
		log->ranOnMainThread = false;
	log->calls++;
}

void CountRelease(void *inContext)
{
	static_cast<CallLog *>(inContext)->releases++;
}

} // namespace

@interface OMCMainThreadSignalTests : XCTestCase
@end

@implementation OMCMainThreadSignalTests

- (void)spinFor:(NSTimeInterval)seconds
{
	NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
	while ([until timeIntervalSinceNow] > 0)
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

- (BOOL)spinUntil:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while (!condition() && [deadline timeIntervalSinceNow] > 0)
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
	return condition();
}

- (void)testSignalsBeforeTheCallbackRunsMakeOneCall
{
	CallLog log;
	std::unique_ptr<OMCMainThreadSignal> signal = OMCMainThreadSignal::Create(CountCall, &log, CountRelease);
	XCTAssertTrue(signal != nullptr);

	signal->Signal();
	signal->Signal();
	signal->Signal();
	XCTAssertEqual(log.calls.load(), 0, @"The callback runs from the run loop, not inside Signal()");

	[self spinFor:0.2];
	XCTAssertEqual(log.calls.load(), 1, @"Signals that arrive before the callback runs make one call");

	signal->Signal();
	[self spinFor:0.2];
	XCTAssertEqual(log.calls.load(), 2, @"A signal after the callback ran makes another call");
	XCTAssertTrue(log.ranOnMainThread.load());

	signal.reset();
	XCTAssertEqual(log.releases.load(), 1, @"Destroying the signal releases its context");
}

- (void)testSignalFromAnotherThreadRunsTheCallbackOnTheMainThread
{
	CallLog log;
	std::unique_ptr<OMCMainThreadSignal> signal = OMCMainThreadSignal::Create(CountCall, &log, CountRelease);
	OMCMainThreadSignal *rawSignal = signal.get();

	dispatch_semaphore_t signaled = dispatch_semaphore_create(0);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		rawSignal->Signal();
		dispatch_semaphore_signal(signaled);
	});
	XCTAssertEqual(dispatch_semaphore_wait(signaled, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0);

	CallLog *logPointer = &log; // blocks copy what they capture
	XCTAssertTrue([self spinUntil:^BOOL{ return logPointer->calls.load() == 1; } timeout:5.0]);
	XCTAssertTrue(log.ranOnMainThread.load(), @"The callback must run on the main thread");
	signal.reset();
}

- (void)testNoCallAfterTheSignalIsDestroyed
{
	CallLog log;
	std::unique_ptr<OMCMainThreadSignal> signal = OMCMainThreadSignal::Create(CountCall, &log, CountRelease);
	signal->Signal();
	signal.reset(); // before the run loop had a chance to run it

	[self spinFor:0.2];
	XCTAssertEqual(log.calls.load(), 0, @"A destroyed signal must not call back");
	XCTAssertEqual(log.releases.load(), 1);
}

- (void)testRunReadyWorkRunsASignaledCallbackAtOnce
{
	CallLog log;
	std::unique_ptr<OMCMainThreadSignal> signal = OMCMainThreadSignal::Create(CountCall, &log, CountRelease);
	signal->Signal();
	OMCMainThreadSignal::RunReadyWork();
	XCTAssertEqual(log.calls.load(), 1, @"RunReadyWork runs what is ready without waiting");
	signal.reset();
}

- (void)testRunAfterRunsOnceAfterTheDelay
{
	CallLog log;
	NSDate *start = [NSDate date];
	XCTAssertTrue(OMCMainThreadSignal::RunAfter(0.2, CountCall, &log));

	[self spinFor:0.1];
	XCTAssertEqual(log.calls.load(), 0, @"Not before the delay");

	CallLog *logPointer = &log; // blocks copy what they capture
	XCTAssertTrue([self spinUntil:^BOOL{ return logPointer->calls.load() > 0; } timeout:5.0]);
	XCTAssertGreaterThanOrEqual(-[start timeIntervalSinceNow], 0.19);
	[self spinFor:0.3];
	XCTAssertEqual(log.calls.load(), 1, @"Once");
	XCTAssertTrue(log.ranOnMainThread.load());
}

@end

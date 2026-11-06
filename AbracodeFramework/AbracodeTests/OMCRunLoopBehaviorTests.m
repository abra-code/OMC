//
//  OMCRunLoopBehaviorTests.m
//  AbracodeTests
//
//  Phase 3 (run-loop independence, Private/phase3-run-loop-design.md, step 1): tests that pin
//  today's behavior before the engine stops depending on CFRunLoop. They pass on the CFSocket and
//  nested-run-loop engine, and must keep passing when pipe I/O moves to libdispatch and
//  WAIT_FOR_TASK_COMPLETION gets its own wait.
//
//  - A WAIT_FOR_TASK_COMPLETION command returns only after its script ended, whether it is started
//    from a run loop callout or from a main-queue block (how ActionUI delivers value-change actions:
//    Picker, Toggle, Slider, TextField edits, row selection). The main-queue case is the one a naive
//    port deadlocks on: a nested run loop inside a main-queue block runs no other main-queue work.
//  - Output larger than a pipe buffer arrives whole and in order (standard input: OMCStandardInputTests).
//  - A PROGRESS window with DELAY appears only when the command outlasts the delay.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"
#import "OMCTestCase.h"

static const NSTimeInterval kRunLoopTestTimeout = 30.0;

@interface OMCRunLoopBehaviorTests : OMCTestCase
@property (nonatomic, strong) NSMutableArray<NSURL *> *bundlesToCleanup;
@property (nonatomic, strong) NSMutableArray<NSString *> *filesToCleanup;
@end

@implementation OMCRunLoopBehaviorTests

- (void)setUp
{
    [super setUp];
    self.bundlesToCleanup = [NSMutableArray array];
    self.filesToCleanup = [NSMutableArray array];
}

- (void)tearDown
{
    for (NSURL *bundleURL in self.bundlesToCleanup)
        [OMCBundleTestHelper removeTestBundle:bundleURL];
    for (NSString *path in self.filesToCleanup)
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    [super tearDown];
}

#pragma mark - Helpers

/// A unique marker path in /tmp, removed in tearDown.
- (NSString *)markerPath:(NSString *)label
{
    NSString *path = [NSString stringWithFormat:@"/tmp/OMC_test_runloop_%@_%@", label, [NSUUID UUID].UUIDString];
    [self.filesToCleanup addObject:path];
    return path;
}

/// A bundle with one exe_script_file command.
- (NSURL *)bundleNamed:(NSString *)name commandID:(NSString *)commandID script:(NSString *)script
                  wait:(BOOL)wait extraKeys:(NSDictionary *)extraKeys
{
    NSMutableDictionary *command = [@{
        @"NAME": name,
        @"COMMAND_ID": commandID,
        @"EXECUTION_MODE": @"exe_script_file",
        @"WAIT_FOR_TASK_COMPLETION": @(wait)
    } mutableCopy];
    if (extraKeys != nil)
        [command addEntriesFromDictionary:extraKeys];

    NSString *scriptName = [commandID stringByAppendingString:@".sh"];
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:name withCommands:@[command] scripts:@{scriptName: script}];
    XCTAssertNotNil(bundleURL, @"Should create the %@ test bundle", name);
    if (bundleURL != nil)
        [self.bundlesToCleanup addObject:bundleURL];
    return bundleURL;
}

- (OSStatus)runCommand:(NSString *)commandID inBundle:(NSURL *)bundleURL observer:(OMCTestExecutionObserver *)observer
{
    return [OMCCommandExecutor runCommand:commandID
                           forCommandFile:[bundleURL path]
                              withContext:nil
                             useNavDialog:NO
                 allowKeyWindowSubcommand:NO
                                 delegate:observer];
}

/// Spins the run loop in the default mode until the block returns YES or the timeout passes.
- (BOOL)spinUntil:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return condition();
}

/// A WAIT_FOR_TASK_COMPLETION script that sleeps, then writes the marker as its last act.
- (NSString *)waitScriptWritingMarker:(NSString *)markerPath
{
    return [NSString stringWithFormat:@"#!/bin/sh\nsleep 0.3\necho 'wait output'\necho done > '%@'\n", markerPath];
}

#pragma mark - The test process's own context

/// The other tests here assume the test method does not itself run inside a main-queue block
/// (a block they enqueue on the main queue has to run while they spin the run loop). Pin that.
- (void)testTestMethodsDoNotRunInsideAMainQueueBlock
{
    __block BOOL ran = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ ran = YES; });
    XCTAssertTrue([self spinUntil:^BOOL{ return ran; } timeout:2.0],
                  @"A main-queue block should run while a test spins the run loop");
}

#pragma mark - WAIT_FOR_TASK_COMPLETION returns after the script

- (void)testWaitCommandReturnsOnlyAfterTheScriptEnded
{
    NSString *marker = [self markerPath:@"wait_direct"];
    NSURL *bundleURL = [self bundleNamed:@"RunLoopWaitDirect" commandID:@"wait_direct"
                                  script:[self waitScriptWritingMarker:marker] wait:YES extraKeys:nil];

    OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
    OSStatus err = [self runCommand:@"wait_direct" inBundle:bundleURL observer:observer];
    BOOL markerAtReturn = [[NSFileManager defaultManager] fileExistsAtPath:marker];

    XCTAssertEqual(err, noErr);
    XCTAssertTrue(markerAtReturn, @"runCommand should return only after a WAIT_FOR_TASK_COMPLETION script ended");
    XCTAssertTrue([observer waitForCompletionWithTimeout:kRunLoopTestTimeout]);
    XCTAssertTrue([observer.capturedOutput containsString:@"wait output"], @"Got: %@", observer.capturedOutput);
}

/// ActionUI calls OMC's action handler from a main-queue block for value changes (its Picker, Toggle,
/// Slider, TextField and row-selection bindings defer with DispatchQueue.main.async), so a
/// WAIT_FOR_TASK_COMPLETION command started by one runs its wait inside that block. A nested run loop
/// there runs no other main-queue work, so the wait must not depend on the main queue.
- (void)testWaitCommandStartedFromAMainQueueBlock
{
    NSString *marker = [self markerPath:@"wait_mainqueue"];
    NSURL *bundleURL = [self bundleNamed:@"RunLoopWaitMainQueue" commandID:@"wait_mainqueue"
                                  script:[self waitScriptWritingMarker:marker] wait:YES extraKeys:nil];

    OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
    __block BOOL blockDone = NO;
    __block BOOL markerAtReturn = NO;
    __block OSStatus err = -1;
    dispatch_async(dispatch_get_main_queue(), ^{
        err = [self runCommand:@"wait_mainqueue" inBundle:bundleURL observer:observer];
        markerAtReturn = [[NSFileManager defaultManager] fileExistsAtPath:marker];
        blockDone = YES;
    });

    XCTAssertTrue([self spinUntil:^BOOL{ return blockDone; } timeout:kRunLoopTestTimeout],
                  @"A WAIT_FOR_TASK_COMPLETION command started from a main-queue block should finish");
    XCTAssertEqual(err, noErr);
    XCTAssertTrue(markerAtReturn, @"runCommand should return only after the script ended");
    XCTAssertTrue([observer waitForCompletionWithTimeout:kRunLoopTestTimeout]);
    XCTAssertTrue([observer.capturedOutput containsString:@"wait output"], @"Got: %@", observer.capturedOutput);
}

/// The ordinary case: started from a run loop callout (menus, timers, Apple events).
- (void)testWaitCommandStartedFromATimer
{
    NSString *marker = [self markerPath:@"wait_timer"];
    NSURL *bundleURL = [self bundleNamed:@"RunLoopWaitTimer" commandID:@"wait_timer"
                                  script:[self waitScriptWritingMarker:marker] wait:YES extraKeys:nil];

    OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
    __block BOOL timerDone = NO;
    __block BOOL markerAtReturn = NO;
    __block OSStatus err = -1;
    [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:NO block:^(NSTimer *timer) {
        err = [self runCommand:@"wait_timer" inBundle:bundleURL observer:observer];
        markerAtReturn = [[NSFileManager defaultManager] fileExistsAtPath:marker];
        timerDone = YES;
    }];

    XCTAssertTrue([self spinUntil:^BOOL{ return timerDone; } timeout:kRunLoopTestTimeout]);
    XCTAssertEqual(err, noErr);
    XCTAssertTrue(markerAtReturn, @"runCommand should return only after the script ended");
    XCTAssertTrue([observer waitForCompletionWithTimeout:kRunLoopTestTimeout]);
    XCTAssertTrue([observer.capturedOutput containsString:@"wait output"], @"Got: %@", observer.capturedOutput);
}

#pragma mark - Output larger than a pipe buffer

static NSString *ExpectedSequence(NSInteger count)
{
    NSMutableString *expected = [NSMutableString string];
    for (NSInteger i = 1; i <= count; i++)
        [expected appendFormat:@"%ld\n", (long)i];
    return expected;
}

- (void)checkLargeOutputWithWait:(BOOL)wait
{
    // 40000 lines are about 229 KB, several times a pipe buffer (16 to 64 KB)
    NSString *commandID = wait ? @"large_output_wait" : @"large_output_async";
    NSURL *bundleURL = [self bundleNamed:(wait ? @"RunLoopLargeOutputWait" : @"RunLoopLargeOutputAsync")
                               commandID:commandID script:@"#!/bin/sh\n/usr/bin/seq 1 40000\n" wait:wait extraKeys:nil];

    OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
    XCTAssertEqual([self runCommand:commandID inBundle:bundleURL observer:observer], noErr);
    XCTAssertTrue([observer waitForCompletionWithTimeout:kRunLoopTestTimeout]);

    NSString *expected = ExpectedSequence(40000);
    NSString *output = observer.capturedOutput;
    XCTAssertEqual(output.length, expected.length, @"All of the output should arrive (wait=%d)", wait);
    XCTAssertTrue([output isEqualToString:expected], @"The output should arrive in order (wait=%d)", wait);
}

- (void)testLargeOutputArrivesWholeAndInOrder
{
    [self checkLargeOutputWithWait:NO];
}

- (void)testLargeOutputArrivesWholeAndInOrderWithWait
{
    [self checkLargeOutputWithWait:YES];
}

#pragma mark - PROGRESS with DELAY

- (BOOL)progressWindowVisibleWithTitle:(NSString *)title
{
    NSString *autosaveName = [NSString stringWithFormat:@"omc_progress_window %@", title];
    for (NSWindow *window in [NSApp windows]) {
        if (window.isVisible && [window.frameAutosaveName isEqualToString:autosaveName])
            return YES;
    }
    return NO;
}

- (NSDictionary *)indeterminateProgressWithTitle:(NSString *)title delay:(double)delay
{
    return @{@"PROGRESS": @{@"TITLE": title, @"DELAY": @(delay)}};
}

/// A command that outlasts DELAY gets its progress window, from the defer timer.
- (void)testProgressWindowAppearsAfterTheDelay
{
    NSString *title = [NSString stringWithFormat:@"Delay Shown %@", [NSUUID UUID].UUIDString];
    NSURL *bundleURL = [self bundleNamed:@"RunLoopProgressShown" commandID:@"progress_shown"
                                  script:@"#!/bin/sh\necho working\nsleep 2\necho finished\n" wait:NO
                               extraKeys:[self indeterminateProgressWithTitle:title delay:0.3]];

    OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
    XCTAssertEqual([self runCommand:@"progress_shown" inBundle:bundleURL observer:observer], noErr);

    BOOL appeared = [self spinUntil:^BOOL{ return [self progressWindowVisibleWithTitle:title] || observer.allTasksFinished; }
                            timeout:kRunLoopTestTimeout] && [self progressWindowVisibleWithTitle:title];
    XCTAssertTrue(appeared, @"The progress window should appear once DELAY (0.3 s) has passed");
    XCTAssertTrue([observer waitForCompletionWithTimeout:kRunLoopTestTimeout]);
}

/// A command that ends before DELAY never shows its progress window.
- (void)testProgressWindowDoesNotAppearBeforeTheDelay
{
    NSString *title = [NSString stringWithFormat:@"Delay Hidden %@", [NSUUID UUID].UUIDString];
    NSURL *bundleURL = [self bundleNamed:@"RunLoopProgressHidden" commandID:@"progress_hidden"
                                  script:@"#!/bin/sh\necho quick\n" wait:NO
                               extraKeys:[self indeterminateProgressWithTitle:title delay:5.0]];

    OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
    XCTAssertEqual([self runCommand:@"progress_hidden" inBundle:bundleURL observer:observer], noErr);

    __block BOOL everVisible = NO;
    [self spinUntil:^BOOL{
        if ([self progressWindowVisibleWithTitle:title])
            everVisible = YES;
        return observer.allTasksFinished;
    } timeout:kRunLoopTestTimeout];
    XCTAssertTrue(observer.allTasksFinished);
    // keep looking a little past the end, in case a stale timer fires
    [self spinUntil:^BOOL{ if ([self progressWindowVisibleWithTitle:title]) everVisible = YES; return NO; } timeout:0.5];
    XCTAssertFalse(everVisible, @"A command that ends before DELAY should never show its progress window");
}

@end

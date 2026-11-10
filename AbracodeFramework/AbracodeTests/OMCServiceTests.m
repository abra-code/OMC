//
//  OMCServiceTests.m
//  AbracodeTests
//
//  The Services provider's wait for a command's text (OMCService.m). runOMCService: itself reads the
//  host app's NSServices and command file, so these tests drive a request (OMCServiceRequest) directly,
//  with the observer messages in the order a command sends them, or with real commands started the way
//  runOMCService: starts them.
//

#import <XCTest/XCTest.h>
#import "OMCService.h"
#import "OMCBundleTestHelper.h"

@interface OMCServiceTests : XCTestCase
@end

@implementation OMCServiceTests

static void SendText(OMCServiceRequest *inRequest, NSString *inText)
{
    [inRequest receiveObserverMessage:kOmcObserverTaskProgress forTaskId:0 withData:(__bridge CFTypeRef)inText];
}

static void SendAllTasksFinished(OMCServiceRequest *inRequest)
{
    [inRequest receiveObserverMessage:kOmcObserverAllTasksFinished forTaskId:0 withData:NULL];
}

/// A synchronous command (AppleScript, system) sends "all tasks finished" inside OMCExecuteCommand,
/// before the service starts waiting. The wait used to start only afterwards, for a message that had
/// come and gone, and never ended.
- (void)testTheWaitEndsWhenTheCommandFinishedBeforeIt
{
    OMCServiceRequest *request = [[OMCServiceRequest alloc] initReturningText:YES];
    SendText(request, @"done");
    SendAllTasksFinished(request);

    // A main-queue block, not a timer, ends a broken wait: the wait's runMode:beforeDate: returns after an
    // input source (the main queue's port is one), and a timer firing does not count
    __block BOOL timedOut = NO;
    __block BOOL done = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (done)
            return;
        timedOut = YES;
        SendAllTasksFinished(request); // let a broken wait end
    });
    NSDate *start = [NSDate date];
    [request waitForAllTasksFinished];
    done = YES;

    XCTAssertFalse(timedOut, @"The wait should end at once: the command already finished");
    XCTAssertLessThan([[NSDate date] timeIntervalSinceDate:start], 1.0);
    XCTAssertEqualObjects(request.resultString, @"done");
}

/// The asynchronous case, as before: the wait runs the run loop until the message arrives.
- (void)testTheWaitEndsWhenTheCommandFinishesDuringIt
{
    OMCServiceRequest *request = [[OMCServiceRequest alloc] initReturningText:YES];
    __block BOOL sent = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SendText(request, @"later");
        sent = YES;
        SendAllTasksFinished(request);
    });
    [request waitForAllTasksFinished];
    XCTAssertTrue(sent, @"The wait should last until the command finished");
    XCTAssertEqualObjects(request.resultString, @"later");
}

/// A second request that arrives while the first one waits (the wait runs the run loop) has its own text
/// and its own end: it used to share the first one's observer and text, and both returned the mixed text
/// when the first command ended.
- (void)testOverlappingRequestsKeepTheirOwnTextAndEnd
{
    OMCServiceRequest *first = [[OMCServiceRequest alloc] initReturningText:YES];
    OMCServiceRequest *second = [[OMCServiceRequest alloc] initReturningText:YES];
    __block BOOL secondEnded = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        // the second request's command runs and ends while the first one still waits
        SendText(second, @"second");
        SendText(first, @"first");
        secondEnded = YES;
        SendAllTasksFinished(second);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SendAllTasksFinished(first);
        });
    });
    [second waitForAllTasksFinished];
    XCTAssertTrue(secondEnded);
    XCTAssertEqualObjects(second.resultString, @"second", @"The second request returns its own command's text only");

    [first waitForAllTasksFinished];
    XCTAssertEqualObjects(first.resultString, @"first", @"The first request returns its own command's text only");
}

/// A request that returns no text keeps none.
- (void)testARequestWithoutTextKeepsNone
{
    OMCServiceRequest *request = [[OMCServiceRequest alloc] initReturningText:NO];
    SendText(request, @"ignored");
    SendAllTasksFinished(request);
    [request waitForAllTasksFinished];
    XCTAssertNil(request.resultString);
}

#pragma mark - Real commands

/// A bundle with one asynchronous script command per entry of inScripts (command ID to script).
- (NSURL *)bundleNamed:(NSString *)inName scripts:(NSDictionary<NSString *, NSString *> *)inScripts
{
    NSMutableArray *commands = [NSMutableArray array];
    NSMutableDictionary *scriptFiles = [NSMutableDictionary dictionary];
    for (NSString *commandID in inScripts)
    {
        [commands addObject:@{ @"NAME": inName, @"COMMAND_ID": commandID, @"ACTIVATION_MODE": @"act_always",
                               @"EXECUTION_MODE": @"exe_script_file" }];
        scriptFiles[[commandID stringByAppendingString:@".sh"]] = inScripts[commandID];
    }
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:inName withCommands:commands scripts:scriptFiles];
    XCTAssertNotNil(bundleURL);
    if (bundleURL != nil)
    {
        [self addTeardownBlock:^{
            [OMCBundleTestHelper removeTestBundle:bundleURL];
        }];
    }
    return bundleURL;
}

/// Starts a command the way runOMCService: does: a request observing the executor, then OMCExecuteCommand.
/// inWatcher, when given, also observes the same executor.
static OMCServiceRequest *StartRequest(NSURL *inBundleURL, NSString *inCommandID, BOOL inReturnsText,
                                       OMCServiceRequest *inWatcher)
{
    NSURL *bundleDirURL = [NSURL fileURLWithPath:[inBundleURL path] isDirectory:YES];
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFURLRef)bundleDirURL);
    if (executor == NULL)
        return nil;
    OMCServiceRequest *request = nil;
    OMCCommandRef commandRef = OMCFindCommand(executor, (__bridge CFStringRef)inCommandID);
    if (OMCIsValidCommandRef(commandRef) &&
        (OMCExamineContext(executor, commandRef, NULL, kOMCExamineContextDefault) == noErr))
    {
        request = [[OMCServiceRequest alloc] initReturningText:inReturnsText];
        [request observeExecutor:executor];
        [inWatcher observeExecutor:executor];
        if (OMCExecuteCommand(executor, commandRef) != noErr)
            request = nil;
    }
    OMCReleaseExecutor(executor);
    return request;
}

/// The overlap with real commands: a second request arrives (from a main-queue block) while the first
/// one waits, runs its own command and waits for it inside the first one's wait. Each executor reports
/// to its own request: the second gets its own text and end, the first still gets its own afterwards.
- (void)testOverlappingRealRequestsKeepTheirOwnTextAndEnd
{
    NSURL *bundleURL = [self bundleNamed:@"OMCServiceOverlap" scripts:@{
        @"service.slow": @"#!/bin/sh\nsleep 0.5\necho first\n",
        @"service.fast": @"#!/bin/sh\necho second\n" }];
    if (bundleURL == nil)
        return;

    OMCServiceRequest *first = StartRequest(bundleURL, @"service.slow", YES, nil);
    XCTAssertNotNil(first);
    __block NSString *secondText = nil;
    __block NSString *firstTextWhenSecondEnded = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        OMCServiceRequest *second = StartRequest(bundleURL, @"service.fast", YES, nil);
        [second waitForAllTasksFinished];
        secondText = [second.resultString copy];
        firstTextWhenSecondEnded = [first.resultString copy];
    });
    [first waitForAllTasksFinished];

    XCTAssertEqualObjects(secondText, @"second\n", @"The second request returns its own command's text only");
    XCTAssertEqualObjects(firstTextWhenSecondEnded, @"", @"The second request ended while the first one still waited");
    XCTAssertEqualObjects(first.resultString, @"first\n", @"The first request returns its own command's text only");
}

/// A request without text is released when runOMCService: returns, while its command still runs: it must
/// stop listening then, so the command's later messages do not reach the freed request.
- (void)testARequestReleasedWhileItsCommandRunsHearsNothingLater
{
    NSURL *bundleURL = [self bundleNamed:@"OMCServiceReleased" scripts:@{
        @"service.later": @"#!/bin/sh\nsleep 0.3\necho later\n" }];
    if (bundleURL == nil)
        return;

    OMCServiceRequest *watcher = [[OMCServiceRequest alloc] initReturningText:YES];
    __weak OMCServiceRequest *weakRequest = nil;
    @autoreleasepool
    {
        OMCServiceRequest *request = StartRequest(bundleURL, @"service.later", NO, watcher);
        XCTAssertNotNil(request);
        weakRequest = request;
    }
    XCTAssertNil(weakRequest, @"The request should be gone while its command still runs");

    [watcher waitForAllTasksFinished]; // the command's output and end arrive after the request went
    XCTAssertEqualObjects(watcher.resultString, @"later\n");
}

@end

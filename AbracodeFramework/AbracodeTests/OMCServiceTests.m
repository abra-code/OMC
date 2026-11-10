//
//  OMCServiceTests.m
//  AbracodeTests
//
//  The Services provider's wait for a command's text (OMCService.m). runOMCService: itself reads the
//  host app's NSServices and command file, so these tests drive the wait directly, with the observer
//  messages in the order a command sends them.
//

#import <XCTest/XCTest.h>
#import "OMCService.h"

@interface OMCServiceTests : XCTestCase
@end

@implementation OMCServiceTests

/// A synchronous command (AppleScript, system) sends "all tasks finished" inside OMCExecuteCommand,
/// before the service starts waiting. The wait used to start only afterwards, for a message that had
/// come and gone, and never ended.
- (void)testTheWaitEndsWhenTheCommandFinishedBeforeIt
{
    OMCService *service = [[OMCService alloc] init];
    [service receiveObserverMessage:kOmcObserverAllTasksFinished forTaskId:0 withData:NULL];

    // A main-queue block, not a timer, ends a broken wait: the wait's runMode:beforeDate: returns after an
    // input source (the main queue's port is one), and a timer firing does not count
    __block BOOL timedOut = NO;
    __block BOOL done = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (done)
            return;
        timedOut = YES;
        [service receiveObserverMessage:kOmcObserverAllTasksFinished forTaskId:0 withData:NULL]; // let a broken wait end
    });
    NSDate *start = [NSDate date];
    [service waitForAllTasksFinished];
    done = YES;

    XCTAssertFalse(timedOut, @"The wait should end at once: the command already finished");
    XCTAssertLessThan([[NSDate date] timeIntervalSinceDate:start], 1.0);
}

/// The asynchronous case, as before: the wait runs the run loop until the message arrives.
- (void)testTheWaitEndsWhenTheCommandFinishesDuringIt
{
    OMCService *service = [[OMCService alloc] init];
    __block BOOL sent = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sent = YES;
        [service receiveObserverMessage:kOmcObserverAllTasksFinished forTaskId:0 withData:NULL];
    });
    [service waitForAllTasksFinished];
    XCTAssertTrue(sent, @"The wait should last until the command finished");
}

@end

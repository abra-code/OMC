//
//  OMCProgressWindowTests.m
//  AbracodeTests
//
//  The PROGRESS window as a built-in ActionUI document (OMC 5.6, Phase 2; BuiltInDocuments/
//  omc_progress.json, OMCProgressWindow.cpp): what it shows while a command runs, and that Stop
//  ends the command. The window is found by its frame autosave name, as in OMCRunLoopBehaviorTests;
//  its identifier is the document's window UUID, through which the tests read the document's
//  values. Stop is clicked with mouse events sent to the window.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"
#import "OMCTestCase.h"

static const NSTimeInterval kProgressWindowTestTimeout = 15.0;

// The document's element ids (BuiltInDocuments/omc_progress.json)
static const NSInteger kStatusTextID = 2;
static const NSInteger kProgressBarID = 3;
static const NSInteger kStopButtonID = 4;

// The adapter is linked into Abracode.framework, not into this bundle: look the class up
static id ActionUIObjCClass(void)
{
    return NSClassFromString(@"_TtC19ActionUIObjCAdapter12ActionUIObjC");
}

@interface NSObject (OMCProgressWindowTestsActionUI)
+ (nullable id)getElementStateWithWindowUUID:(NSString *)windowUUID viewID:(NSInteger)viewID key:(NSString *)key;
+ (nullable id)getElementPropertyWithWindowUUID:(NSString *)windowUUID viewID:(NSInteger)viewID propertyName:(NSString *)propertyName;
+ (nullable NSString *)getElementValueAsStringWithWindowUUID:(NSString *)windowUUID viewID:(NSInteger)viewID viewPartID:(NSInteger)viewPartID contentType:(nullable NSString *)contentType;
@end

@interface OMCProgressWindowTests : OMCTestCase
@property (nonatomic, strong) NSMutableArray<NSURL *> *bundlesToCleanup;
@end

@implementation OMCProgressWindowTests

- (void)setUp
{
    [super setUp];
    self.bundlesToCleanup = [NSMutableArray array];
}

- (void)tearDown
{
    for (NSURL *bundleURL in self.bundlesToCleanup)
        [OMCBundleTestHelper removeTestBundle:bundleURL];
    [super tearDown];
}

#pragma mark - Probe

- (NSWindow *)progressWindowWithTitle:(NSString *)title
{
    NSString *autosaveName = [NSString stringWithFormat:@"omc_progress_window %@", title];
    for (NSWindow *window in [NSApp windows]) {
        if (window.isVisible && [window.frameAutosaveName isEqualToString:autosaveName])
            return window;
    }
    return nil;
}

/// The bar's value, or nil while it is indeterminate (no progress set, or a negative one).
- (NSNumber *)progressOfWindow:(NSWindow *)window
{
    id value = [ActionUIObjCClass() getElementStateWithWindowUUID:window.identifier viewID:kProgressBarID key:@"progress"];
    return ([value isKindOfClass:[NSNumber class]] && ([value doubleValue] >= 0.0)) ? value : nil;
}

- (NSString *)statusOfWindow:(NSWindow *)window
{
    return [ActionUIObjCClass() getElementValueAsStringWithWindowUUID:window.identifier viewID:kStatusTextID viewPartID:0 contentType:nil];
}

/// Clicks the Stop button: a mouse down and up at the trailing end of the document's top row
/// (VStack padding 14; HStack of the bar and the button). SwiftUI builds no accessibility tree in
/// a process that no accessibility client is attached to, so the button cannot be found that way.
static void ClickStop(NSWindow *window)
{
    NSRect content = window.contentLayoutRect;
    NSPoint point = NSMakePoint(NSMaxX(content) - 14 - 8, NSMaxY(content) - 14 - 8);
    NSEventType types[2] = { NSEventTypeLeftMouseDown, NSEventTypeLeftMouseUp };
    for (int i = 0; i < 2; i++) {
        NSEvent *event = [NSEvent mouseEventWithType:types[i] location:point modifierFlags:0 timestamp:[NSProcessInfo processInfo].systemUptime
                                        windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:(i == 0) ? 1.0 : 0.0];
        [window sendEvent:event];
    }
}

#pragma mark - Helpers

- (BOOL)spinUntil:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return condition();
}

- (OMCTestExecutionObserver *)runScript:(NSString *)script label:(NSString *)label progress:(NSDictionary *)progress
{
    NSString *commandID = [NSString stringWithFormat:@"progress_window_%@", label];
    NSString *bundleName = [NSString stringWithFormat:@"ProgressWindow_%@", label];
    NSDictionary *command = @{
        @"NAME": bundleName,
        @"COMMAND_ID": commandID,
        @"EXECUTION_MODE": @"exe_script_file",
        @"PROGRESS": progress,
    };
    NSString *scriptName = [commandID stringByAppendingString:@".sh"];
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:bundleName withCommands:@[command] scripts:@{scriptName: script}];
    XCTAssertNotNil(bundleURL);
    if (bundleURL == nil)
        return nil;
    [self.bundlesToCleanup addObject:bundleURL];

    OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
    OSStatus status = [OMCCommandExecutor runCommand:commandID forCommandFile:[bundleURL path] withContext:nil
                                        useNavDialog:NO allowKeyWindowSubcommand:NO delegate:observer];
    XCTAssertEqual(status, noErr);
    return observer;
}

- (NSString *)uniqueTitle:(NSString *)label
{
    return [NSString stringWithFormat:@"Progress %@ %@", label, [NSUUID UUID].UUIDString];
}

#pragma mark - What the window shows

/// DETERMINATE_STEPS: the bar moves to each matched step's VALUE and the status line shows its STATUS.
- (void)testStepsMoveTheBarAndShowTheirStatus
{
    NSString *title = [self uniqueTitle:@"steps"];
    NSDictionary *progress = @{
        @"TITLE": title,
        @"DETERMINATE_STEPS": @{
            @"MATCH_METHOD": @"match_exact",
            @"STEPS": @[
                @{ @"STRING": @"PHASE_1", @"VALUE": @33, @"STATUS": @"Phase one" },
                @{ @"STRING": @"PHASE_2", @"VALUE": @66, @"STATUS": @"Phase two" },
            ],
        },
    };
    NSString *script = @"#!/bin/sh\necho PHASE_1\n/bin/sleep 0.6\necho PHASE_2\n/bin/sleep 0.6\n";
    OMCTestExecutionObserver *observer = [self runScript:script label:@"steps" progress:progress];

    __block NSWindow *window = nil;
    BOOL first = [self spinUntil:^BOOL{
        window = [self progressWindowWithTitle:title];
        return (window != nil) && ([[self progressOfWindow:window] integerValue] == 33);
    } timeout:kProgressWindowTestTimeout];
    XCTAssertTrue(first, @"The bar should reach the first step's value");
    XCTAssertEqualObjects([self statusOfWindow:window], @"Phase one");

    BOOL second = [self spinUntil:^BOOL{ return [[self progressOfWindow:window] integerValue] == 66; } timeout:kProgressWindowTestTimeout];
    XCTAssertTrue(second, @"The bar should reach the second step's value");
    XCTAssertEqualObjects([self statusOfWindow:window], @"Phase two");

    XCTAssertTrue([observer waitForCompletionWithTimeout:kProgressWindowTestTimeout]);
    BOOL closed = [self spinUntil:^BOOL{ return [self progressWindowWithTitle:title] == nil; } timeout:kProgressWindowTestTimeout];
    XCTAssertTrue(closed, @"The window should close when the command ends");
}

/// A step with a negative VALUE takes the bar back to indeterminate (its progress state is set to -1,
/// which an ActionUI ProgressView shows as indeterminate), and the next step's value shows again.
- (void)testANegativeStepMakesTheBarIndeterminateAgain
{
    NSString *title = [self uniqueTitle:@"negative"];
    NSDictionary *progress = @{
        @"TITLE": title,
        @"DETERMINATE_STEPS": @{
            @"MATCH_METHOD": @"match_exact",
            @"STEPS": @[
                @{ @"STRING": @"KNOWN", @"VALUE": @33 },
                @{ @"STRING": @"UNKNOWN", @"VALUE": @-1 },
                @{ @"STRING": @"KNOWN_AGAIN", @"VALUE": @66 },
            ],
        },
    };
    NSString *script = @"#!/bin/sh\necho KNOWN\n/bin/sleep 0.6\necho UNKNOWN\n/bin/sleep 0.6\necho KNOWN_AGAIN\n/bin/sleep 0.6\n";
    OMCTestExecutionObserver *observer = [self runScript:script label:@"negative" progress:progress];

    __block NSWindow *window = nil;
    XCTAssertTrue([self spinUntil:^BOOL{
        window = [self progressWindowWithTitle:title];
        return (window != nil) && ([[self progressOfWindow:window] integerValue] == 33);
    } timeout:kProgressWindowTestTimeout], @"The bar should reach the first step's value");
    XCTAssertTrue([self spinUntil:^BOOL{ return [self progressOfWindow:window] == nil; } timeout:kProgressWindowTestTimeout],
                  @"A negative step should make the bar indeterminate");
    XCTAssertTrue([self spinUntil:^BOOL{ return [[self progressOfWindow:window] integerValue] == 66; } timeout:kProgressWindowTestTimeout],
                  @"The next step's value should show again");
    XCTAssertTrue([observer waitForCompletionWithTimeout:kProgressWindowTestTimeout]);
}

/// Without determinate settings the bar is indeterminate and the status line is the last output line.
- (void)testIndeterminateBarShowsTheLastLine
{
    NSString *title = [self uniqueTitle:@"indeterminate"];
    NSString *script = @"#!/bin/sh\necho first line\necho working on it\n/bin/sleep 1\n";
    OMCTestExecutionObserver *observer = [self runScript:script label:@"indeterminate" progress:@{@"TITLE": title}];

    __block NSWindow *window = nil;
    BOOL shown = [self spinUntil:^BOOL{
        window = [self progressWindowWithTitle:title];
        return (window != nil) && [[self statusOfWindow:window] isEqualToString:@"working on it"];
    } timeout:kProgressWindowTestTimeout];
    XCTAssertTrue(shown, @"The status line should show the last line of output (it shows: %@)", window ? [self statusOfWindow:window] : @"no window");
    XCTAssertNil([self progressOfWindow:window], @"The bar should be indeterminate");
    XCTAssertEqualObjects(window.title, title);
    // the document has no text of its own: the label comes from Private.strings (English here)
    XCTAssertEqualObjects([ActionUIObjCClass() getElementPropertyWithWindowUUID:window.identifier viewID:kStopButtonID propertyName:@"accessibilityLabel"], @"Stop");
    XCTAssertEqualObjects([ActionUIObjCClass() getElementPropertyWithWindowUUID:window.identifier viewID:kStopButtonID propertyName:@"help"], @"Stop");
    XCTAssertTrue([observer waitForCompletionWithTimeout:kProgressWindowTestTimeout]);
}

/// Stop closes the window and stops the command's process, at its next output.
- (void)testStopEndsTheCommand
{
    NSString *title = [self uniqueTitle:@"stop"];
    NSString *script = @"#!/bin/sh\ni=0\nwhile [ $i -lt 150 ]; do echo tick $i; i=$((i+1)); /bin/sleep 0.2; done\n";
    OMCTestExecutionObserver *observer = [self runScript:script label:@"stop" progress:@{@"TITLE": title}];

    __block NSWindow *window = nil;
    XCTAssertTrue([self spinUntil:^BOOL{ window = [self progressWindowWithTitle:title]; return window != nil; } timeout:kProgressWindowTestTimeout]);

    // the document is laid out and a few ticks have arrived
    [self spinUntil:^BOOL{ return [[self statusOfWindow:window] hasPrefix:@"tick 2"]; } timeout:kProgressWindowTestTimeout];
    ClickStop(window);

    BOOL closed = [self spinUntil:^BOOL{ return [self progressWindowWithTitle:title] == nil; } timeout:5.0];
    XCTAssertTrue(closed, @"Stop should close the window");
    NSDate *start = [NSDate date];
    XCTAssertTrue([observer waitForCompletionWithTimeout:10.0], @"Stop should end the command");
    XCTAssertLessThan([[NSDate date] timeIntervalSinceDate:start], 10.0, @"The script would have run for 30 s");
}

@end

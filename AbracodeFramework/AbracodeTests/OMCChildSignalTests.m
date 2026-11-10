//
//  OMCChildSignalTests.m
//  AbracodeTests
//
//  A command's script starts with SIGPIPE at its default, whatever the engine did before. The
//  engine ignores SIGPIPE for the whole process the first time a command writes to a child's
//  standard input (so a script that stops reading does not end the applet), and an ignored signal
//  is inherited by every process started afterwards. Scripts then behaved differently depending
//  on what ran before them: in "producer | head -n 1" the producer got write errors ("yes:
//  stdout: Broken pipe", status 1) instead of ending quietly (status 141).
//

#import <XCTest/XCTest.h>
#import <signal.h>
#import "OMCTestCase.h"
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"

static const NSTimeInterval kChildSignalTestTimeout = 30.0;

@interface OMCChildSignalTests : OMCTestCase
@property (nonatomic, strong) NSMutableArray<NSURL *> *bundlesToCleanup;
@end

@implementation OMCChildSignalTests
{
    struct sigaction _savedPipeAction;
    BOOL _hasSavedPipeAction;
}

- (void)setUp
{
    [super setUp];
    self.bundlesToCleanup = [NSMutableArray array];
    _hasSavedPipeAction = (sigaction(SIGPIPE, NULL, &_savedPipeAction) == 0);
}

- (void)tearDown
{
    for (NSURL *bundleURL in self.bundlesToCleanup)
        [OMCBundleTestHelper removeTestBundle:bundleURL];
    // The engine leaves SIGPIPE ignored; the test process gets back what it had
    if (_hasSavedPipeAction)
        sigaction(SIGPIPE, &_savedPipeAction, NULL);
    [super tearDown];
}

/// Runs a one-command bundle and returns the command's output, or nil when it did not finish.
- (NSString *)runCommand:(NSDictionary *)command script:(NSString *)script
{
    NSString *commandID = command[@"COMMAND_ID"];
    NSString *scriptName = [commandID stringByAppendingString:@".sh"];
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:[NSString stringWithFormat:@"ChildSignal_%@", commandID]
                                                withCommands:@[command]
                                                     scripts:@{scriptName: script}];
    XCTAssertNotNil(bundleURL);
    if (bundleURL == nil)
        return nil;
    [self.bundlesToCleanup addObject:bundleURL];

    OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
    OSStatus err = [OMCCommandExecutor runCommand:commandID
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:observer];
    XCTAssertEqual(err, noErr, @"%@ should start", commandID);
    BOOL finished = [observer waitForCompletionWithTimeout:kChildSignalTestTimeout];
    XCTAssertTrue(finished, @"%@ should finish", commandID);
    return finished ? observer.capturedOutput : nil;
}

/// A script started after a command that wrote standard input sees SIGPIPE at its default, and
/// "yes | head -n 1" ends the producer by the signal.
- (void)testScriptAfterStandardInputCommandHasDefaultSIGPIPE
{
    // 1. A command whose standard input the engine writes: the engine ignores SIGPIPE from here on
    NSDictionary *feeding = @{
        @"NAME": @"Feeding",
        @"COMMAND_ID": @"child_signal_feeding",
        @"EXECUTION_MODE": @"exe_script_file",
        @"STANDARD_INPUT_PIPE": @[@"one line\n"]
    };
    NSString *fed = [self runCommand:feeding script:@"#!/bin/sh\n/bin/cat\n"];
    XCTAssertEqualObjects(fed, @"one line\n");

    // The precondition that makes this test mean something
    struct sigaction current;
    XCTAssertEqual(sigaction(SIGPIPE, NULL, &current), 0);
    XCTAssertTrue(current.sa_handler == SIG_IGN, @"the engine should be ignoring SIGPIPE after writing a child's standard input");

    // 2. The next script reports what it got. perl shows a signal ignored at its start as IGNORE
    // (Python cannot tell: it ignores SIGPIPE itself at start)
    NSDictionary *reporting = @{
        @"NAME": @"Reporting",
        @"COMMAND_ID": @"child_signal_reporting",
        @"EXECUTION_MODE": @"exe_script_file"
    };
    NSString *script =
        @"#!/bin/sh\n"
        @"/usr/bin/perl -e 'print defined $SIG{PIPE} ? $SIG{PIPE} : \"DEFAULT\", \"\\n\"'\n"
        @"{ ( /usr/bin/yes 2>/dev/null; echo \"yes $?\" >&3 ) | /usr/bin/head -n 1 >/dev/null; } 3>&1\n";
    NSString *reported = [self runCommand:reporting script:script];
    XCTAssertEqualObjects(reported, @"DEFAULT\nyes 141\n", @"a script should start with SIGPIPE at its default (141 = 128 + SIGPIPE)");
}

@end

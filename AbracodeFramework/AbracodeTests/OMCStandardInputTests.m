//
//  OMCStandardInputTests.m
//  AbracodeTests
//
//  STANDARD_INPUT_PIPE larger than a pipe buffer, fed to a script that writes output while it reads
//  (cat). The engine writes standard input and reads output on the main thread. With a blocking
//  write of the whole input, the write waited for the child to read, the child waited for the
//  engine to read its output, and the applet hung. Both directions must make progress.
//

#import <XCTest/XCTest.h>
#import "OMCTestCase.h"
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"

static const NSTimeInterval kStandardInputTestTimeout = 30.0;

@interface OMCStandardInputTests : OMCTestCase
@property (nonatomic, strong) NSMutableArray<NSURL *> *bundlesToCleanup;
@end

@implementation OMCStandardInputTests

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

static NSString *NumberedLines(NSInteger count)
{
    NSMutableString *lines = [NSMutableString string];
    for (NSInteger i = 1; i <= count; i++)
        [lines appendFormat:@"%ld\n", (long)i];
    return lines;
}

/// Runs /bin/cat with the input as STANDARD_INPUT_PIPE and checks the output is the input, whole and in order.
- (void)checkInput:(NSString *)input wait:(BOOL)wait label:(NSString *)label
{
    NSString *commandID = [NSString stringWithFormat:@"stdin_%@_%@", label, wait ? @"wait" : @"async"];
    NSDictionary *command = @{
        @"NAME": @"Standard Input",
        @"COMMAND_ID": commandID,
        @"EXECUTION_MODE": @"exe_script_file",
        @"WAIT_FOR_TASK_COMPLETION": @(wait),
        @"STANDARD_INPUT_PIPE": @[input]
    };
    NSString *scriptName = [commandID stringByAppendingString:@".sh"];
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:[NSString stringWithFormat:@"StandardInput_%@", commandID]
                                                withCommands:@[command]
                                                     scripts:@{scriptName: @"#!/bin/sh\n/bin/cat\n"}];
    XCTAssertNotNil(bundleURL);
    if (bundleURL == nil)
        return;
    [self.bundlesToCleanup addObject:bundleURL];

    OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
    OSStatus err = [OMCCommandExecutor runCommand:commandID
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:observer];
    XCTAssertEqual(err, noErr);
    XCTAssertTrue([observer waitForCompletionWithTimeout:kStandardInputTestTimeout], @"%@ should finish", commandID);

    NSString *output = observer.capturedOutput;
    XCTAssertEqual(output.length, input.length, @"All of standard input should come back (%@)", commandID);
    XCTAssertTrue([output isEqualToString:input], @"Standard input should come back in order (%@)", commandID);
}

- (void)testSmallStandardInput
{
    [self checkInput:@"one line\n" wait:NO label:@"small"];
}

/// About 169 KB, several times a pipe buffer (16 to 64 KB).
- (void)testLargeStandardInputToAnEchoingScript
{
    [self checkInput:NumberedLines(30000) wait:NO label:@"large"];
}

- (void)testLargeStandardInputToAnEchoingScriptWithWait
{
    [self checkInput:NumberedLines(30000) wait:YES label:@"large"];
}

@end

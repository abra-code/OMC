//
//  OMCProgressTests.m
//  AbracodeTests
//
//  End-to-end integration tests for OMC progress dialog modes:
//  indeterminate, determinate counter, and determinate steps
//

#import <XCTest/XCTest.h>
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"

#if __has_feature(address_sanitizer)
    #define kProgressTestTimeout 10.0
#else
    #define kProgressTestTimeout 5.0
#endif

#pragma mark - Static Bundle Integration Tests

@interface OMCProgressBundleTests : XCTestCase
@end

@implementation OMCProgressBundleTests

- (NSString *)progressBundlePath
{
	NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ProgressTest"];
	return [bundleURL path];
}

- (void)testIndeterminateProgressBundle
{
	NSString *bundlePath = [self progressBundlePath];
	if (bundlePath == nil) {
		NSLog(@"Skipping - ProgressTest.omc not found in test resources");
		return;
	}

	OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
	OSStatus err = [OMCCommandExecutor runCommand:@"indeterminate_progress"
	                                forCommandFile:bundlePath
	                                   withContext:nil
	                                  useNavDialog:NO
	                                      allowKeyWindowSubcommand:NO
	                                      delegate:observer];

	XCTAssertEqual(err, noErr, @"Indeterminate progress command should start");

	BOOL completed = [observer waitForCompletionWithTimeout:kProgressTestTimeout];
	XCTAssertTrue(completed, @"Should complete within timeout");

	NSString *output = observer.capturedOutput;
	XCTAssertTrue([output containsString:@"Done!"],
	              @"Output should contain final message. Got: %@", output);
}

- (void)testCounterProgressBundle
{
	NSString *bundlePath = [self progressBundlePath];
	if (bundlePath == nil) {
		NSLog(@"Skipping - ProgressTest.omc not found in test resources");
		return;
	}

	OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
	OSStatus err = [OMCCommandExecutor runCommand:@"counter_progress"
	                                forCommandFile:bundlePath
	                                   withContext:nil
	                                  useNavDialog:NO
	                                      allowKeyWindowSubcommand:NO
	                                      delegate:observer];

	XCTAssertEqual(err, noErr, @"Counter progress command should start");

	BOOL completed = [observer waitForCompletionWithTimeout:kProgressTestTimeout];
	XCTAssertTrue(completed, @"Should complete within timeout");

	NSString *output = observer.capturedOutput;
	XCTAssertTrue([output containsString:@"# 100%"],
	              @"Output should contain 100%% line. Got: %@", output);
	XCTAssertTrue([output containsString:@"Download complete"],
	              @"Output should contain completion message. Got: %@", output);
}

- (void)testStepsProgressBundle
{
	NSString *bundlePath = [self progressBundlePath];
	if (bundlePath == nil) {
		NSLog(@"Skipping - ProgressTest.omc not found in test resources");
		return;
	}

	OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
	OSStatus err = [OMCCommandExecutor runCommand:@"steps_progress"
	                                forCommandFile:bundlePath
	                                   withContext:nil
	                                  useNavDialog:NO
	                                      allowKeyWindowSubcommand:NO
	                                      delegate:observer];

	XCTAssertEqual(err, noErr, @"Steps progress command should start");

	BOOL completed = [observer waitForCompletionWithTimeout:kProgressTestTimeout];
	XCTAssertTrue(completed, @"Should complete within timeout");

	NSString *output = observer.capturedOutput;
	XCTAssertTrue([output containsString:@"Compiling sources"],
	              @"Output should contain step text. Got: %@", output);
	XCTAssertTrue([output containsString:@"Build complete"],
	              @"Output should contain final step. Got: %@", output);
}

- (void)testMultiGroupCounterBundle
{
	NSString *bundlePath = [self progressBundlePath];
	if (bundlePath == nil) {
		NSLog(@"Skipping - ProgressTest.omc not found in test resources");
		return;
	}

	OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
	OSStatus err = [OMCCommandExecutor runCommand:@"multi_group_counter"
	                                forCommandFile:bundlePath
	                                   withContext:nil
	                                  useNavDialog:NO
	                                      allowKeyWindowSubcommand:NO
	                                      delegate:observer];

	XCTAssertEqual(err, noErr, @"Multi group counter command should start");

	BOOL completed = [observer waitForCompletionWithTimeout:kProgressTestTimeout];
	XCTAssertTrue(completed, @"Should complete within timeout");

	NSString *output = observer.capturedOutput;
	XCTAssertTrue([output containsString:@"file 5 of 5"],
	              @"Output should contain final progress line. Got: %@", output);
}

- (void)testStepsRegexProgressBundle
{
	NSString *bundlePath = [self progressBundlePath];
	if (bundlePath == nil) {
		NSLog(@"Skipping - ProgressTest.omc not found in test resources");
		return;
	}

	OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
	OSStatus err = [OMCCommandExecutor runCommand:@"steps_regex_progress"
	                                forCommandFile:bundlePath
	                                   withContext:nil
	                                  useNavDialog:NO
	                                      allowKeyWindowSubcommand:NO
	                                      delegate:observer];

	XCTAssertEqual(err, noErr, @"Steps regex progress command should start");

	BOOL completed = [observer waitForCompletionWithTimeout:kProgressTestTimeout];
	XCTAssertTrue(completed, @"Should complete within timeout");

	NSString *output = observer.capturedOutput;
	XCTAssertTrue([output containsString:@"Build complete"],
	              @"Output should contain completion. Got: %@", output);
}

- (void)testCounterSuppressBundle
{
	NSString *bundlePath = [self progressBundlePath];
	if (bundlePath == nil) {
		NSLog(@"Skipping - ProgressTest.omc not found in test resources");
		return;
	}

	OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
	OSStatus err = [OMCCommandExecutor runCommand:@"counter_suppress"
	                                forCommandFile:bundlePath
	                                   withContext:nil
	                                  useNavDialog:NO
	                                      allowKeyWindowSubcommand:NO
	                                      delegate:observer];

	XCTAssertEqual(err, noErr, @"Counter suppress command should start");

	BOOL completed = [observer waitForCompletionWithTimeout:kProgressTestTimeout];
	XCTAssertTrue(completed, @"Should complete within timeout");
}

@end


#pragma mark - Dynamic Bundle Integration Tests

@interface OMCProgressDynamicBundleTests : XCTestCase
@property (nonatomic, strong) NSMutableArray<NSURL *> *bundlesToCleanup;
@end

@implementation OMCProgressDynamicBundleTests

- (void)setUp
{
	[super setUp];
	self.bundlesToCleanup = [NSMutableArray array];
}

- (void)tearDown
{
	for (NSURL *bundleURL in self.bundlesToCleanup) {
		[OMCBundleTestHelper removeTestBundle:bundleURL];
	}
	[self.bundlesToCleanup removeAllObjects];
	[super tearDown];
}

- (void)testDynamicCounterProgress
{
	NSDictionary *command = @{
		@"NAME": @"Dynamic Counter",
		@"COMMAND_ID": @"dynamic_counter",
		@"EXECUTION_MODE": @"exe_script_file",
		@"WAIT_FOR_TASK_COMPLETION": @YES,
		@"PROGRESS": @{
			@"TITLE": @"Dynamic Counter Test",
			@"DETERMINATE_COUNTER": @{
				@"REGULAR_EXPRESSION_MATCH": @"([0-9]+)/([0-9]+)",
				@"STATUS": @"$1 of $2",
				@"SUBSTRING_INDEX_FOR_COUNTER": @1,
				@"SUBSTRING_INDEX_FOR_RANGE_END": @2,
				@"RANGE_START": @0.0
			}
		}
	};

	NSString *script = @"#!/bin/bash\n"
		"echo '1/10'\n"
		"echo '5/10'\n"
		"echo '10/10'\n"
		"echo 'All done'\n";

	NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"DynamicCounter"
	                                              withCommands:@[command]
	                                                   scripts:@{@"dynamic_counter.sh": script}];
	XCTAssertNotNil(bundleURL, @"Should create dynamic test bundle");
	[self.bundlesToCleanup addObject:bundleURL];

	OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
	OSStatus err = [OMCCommandExecutor runCommand:@"dynamic_counter"
	                                forCommandFile:[bundleURL path]
	                                   withContext:nil
	                                  useNavDialog:NO
	                                      allowKeyWindowSubcommand:NO
	                                      delegate:observer];

	XCTAssertEqual(err, noErr, @"Dynamic counter command should start");

	BOOL completed = [observer waitForCompletionWithTimeout:kProgressTestTimeout];
	XCTAssertTrue(completed, @"Should complete within timeout");

	NSString *output = observer.capturedOutput;
	XCTAssertTrue([output containsString:@"All done"],
	              @"Output should contain completion message. Got: %@", output);
}

- (void)testDynamicStepsProgress
{
	NSDictionary *command = @{
		@"NAME": @"Dynamic Steps",
		@"COMMAND_ID": @"dynamic_steps",
		@"EXECUTION_MODE": @"exe_script_file",
		@"WAIT_FOR_TASK_COMPLETION": @YES,
		@"PROGRESS": @{
			@"TITLE": @"Dynamic Steps Test",
			@"DETERMINATE_STEPS": @{
				@"MATCH_METHOD": @"match_exact",
				@"STEPS": @[
					@{ @"STRING": @"PHASE_1", @"VALUE": @33 },
					@{ @"STRING": @"PHASE_2", @"VALUE": @66 },
					@{ @"STRING": @"PHASE_3", @"VALUE": @100 }
				]
			}
		}
	};

	NSString *script = @"#!/bin/bash\n"
		"echo 'PHASE_1'\n"
		"echo 'PHASE_2'\n"
		"echo 'PHASE_3'\n";

	NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"DynamicSteps"
	                                              withCommands:@[command]
	                                                   scripts:@{@"dynamic_steps.sh": script}];
	XCTAssertNotNil(bundleURL, @"Should create dynamic test bundle");
	[self.bundlesToCleanup addObject:bundleURL];

	OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
	OSStatus err = [OMCCommandExecutor runCommand:@"dynamic_steps"
	                                forCommandFile:[bundleURL path]
	                                   withContext:nil
	                                  useNavDialog:NO
	                                      allowKeyWindowSubcommand:NO
	                                      delegate:observer];

	XCTAssertEqual(err, noErr, @"Dynamic steps command should start");

	BOOL completed = [observer waitForCompletionWithTimeout:kProgressTestTimeout];
	XCTAssertTrue(completed, @"Should complete within timeout");

	NSString *output = observer.capturedOutput;
	XCTAssertTrue([output containsString:@"PHASE_3"],
	              @"Output should contain final phase. Got: %@", output);
}

- (void)testDynamicIndeterminateProgress
{
	NSDictionary *command = @{
		@"NAME": @"Dynamic Indeterminate",
		@"COMMAND_ID": @"dynamic_indeterminate",
		@"EXECUTION_MODE": @"exe_script_file",
		@"WAIT_FOR_TASK_COMPLETION": @YES,
		@"PROGRESS": @{
			@"TITLE": @"Indeterminate Test"
		}
	};

	NSString *script = @"#!/bin/bash\n"
		"echo 'Working...'\n"
		"echo 'Still working...'\n"
		"echo 'Finished'\n";

	NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"DynamicIndeterminate"
	                                              withCommands:@[command]
	                                                   scripts:@{@"dynamic_indeterminate.sh": script}];
	XCTAssertNotNil(bundleURL, @"Should create dynamic test bundle");
	[self.bundlesToCleanup addObject:bundleURL];

	OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
	OSStatus err = [OMCCommandExecutor runCommand:@"dynamic_indeterminate"
	                                forCommandFile:[bundleURL path]
	                                   withContext:nil
	                                  useNavDialog:NO
	                                      allowKeyWindowSubcommand:NO
	                                      delegate:observer];

	XCTAssertEqual(err, noErr, @"Dynamic indeterminate command should start");

	BOOL completed = [observer waitForCompletionWithTimeout:kProgressTestTimeout];
	XCTAssertTrue(completed, @"Should complete within timeout");

	NSString *output = observer.capturedOutput;
	XCTAssertTrue([output containsString:@"Finished"],
	              @"Output should contain completion message. Got: %@", output);
}

- (void)testDynamicCounterWithStatusTemplate
{
	NSDictionary *command = @{
		@"NAME": @"Counter Status",
		@"COMMAND_ID": @"counter_status",
		@"EXECUTION_MODE": @"exe_script_file",
		@"WAIT_FOR_TASK_COMPLETION": @YES,
		@"PROGRESS": @{
			@"TITLE": @"Status Template Test",
			@"DETERMINATE_COUNTER": @{
				@"REGULAR_EXPRESSION_MATCH": @"#+ *(.+)%",
				@"STATUS": @"Downloading: $1%",
				@"SUBSTRING_INDEX_FOR_COUNTER": @1,
				@"RANGE_END": @100.0,
				@"SUPPRESS_NON_MATCHING_TEXT": @YES
			}
		}
	};

	NSString *script = @"#!/bin/bash\n"
		"echo 'Starting download...'\n"
		"echo '# 25%'\n"
		"echo '## 50%'\n"
		"echo '### 75%'\n"
		"echo '#### 100%'\n"
		"echo 'Complete'\n";

	NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"CounterStatus"
	                                              withCommands:@[command]
	                                                   scripts:@{@"counter_status.sh": script}];
	XCTAssertNotNil(bundleURL);
	[self.bundlesToCleanup addObject:bundleURL];

	OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
	OSStatus err = [OMCCommandExecutor runCommand:@"counter_status"
	                                forCommandFile:[bundleURL path]
	                                   withContext:nil
	                                  useNavDialog:NO
	                                      allowKeyWindowSubcommand:NO
	                                      delegate:observer];

	XCTAssertEqual(err, noErr);

	BOOL completed = [observer waitForCompletionWithTimeout:kProgressTestTimeout];
	XCTAssertTrue(completed, @"Should complete within timeout");
}

- (void)testDynamicStepsCaseInsensitive
{
	NSDictionary *command = @{
		@"NAME": @"Steps CI",
		@"COMMAND_ID": @"steps_ci",
		@"EXECUTION_MODE": @"exe_script_file",
		@"WAIT_FOR_TASK_COMPLETION": @YES,
		@"PROGRESS": @{
			@"TITLE": @"Case Insensitive Steps",
			@"DETERMINATE_STEPS": @{
				@"MATCH_METHOD": @"match_contains",
				@"COMPARE_CASE_INSENSITIVE": @YES,
				@"STEPS": @[
					@{ @"STRING": @"start", @"VALUE": @0, @"STATUS": @"Starting..." },
					@{ @"STRING": @"middle", @"VALUE": @50, @"STATUS": @"Halfway..." },
					@{ @"STRING": @"end", @"VALUE": @100, @"STATUS": @"Done!" }
				]
			}
		}
	};

	NSString *script = @"#!/bin/bash\n"
		"echo 'START phase'\n"
		"echo 'MIDDLE phase'\n"
		"echo 'END phase'\n";

	NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"StepsCI"
	                                              withCommands:@[command]
	                                                   scripts:@{@"steps_ci.sh": script}];
	XCTAssertNotNil(bundleURL);
	[self.bundlesToCleanup addObject:bundleURL];

	OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
	OSStatus err = [OMCCommandExecutor runCommand:@"steps_ci"
	                                forCommandFile:[bundleURL path]
	                                   withContext:nil
	                                  useNavDialog:NO
	                                      allowKeyWindowSubcommand:NO
	                                      delegate:observer];

	XCTAssertEqual(err, noErr);

	BOOL completed = [observer waitForCompletionWithTimeout:kProgressTestTimeout];
	XCTAssertTrue(completed, @"Should complete within timeout");

	NSString *output = observer.capturedOutput;
	XCTAssertTrue([output containsString:@"END phase"],
	              @"Output should contain final phase. Got: %@", output);
}

@end

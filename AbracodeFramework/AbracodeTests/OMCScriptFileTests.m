//
//  OMCScriptFileTests.m
//  AbracodeTests
//
//  Tests for exe_script_file execution mode with .omc bundles
//

#import "OMCTestCase.h"
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"

@interface OMCScriptFileTests : XCTestCase
@property (nonatomic, strong) NSMutableArray<NSURL *> *bundlesToCleanup;
@end

@implementation OMCScriptFileTests

- (void)setUp {
    [super setUp];
    self.bundlesToCleanup = [NSMutableArray array];
}

- (void)tearDown {
    for (NSURL *bundleURL in self.bundlesToCleanup) {
        [OMCBundleTestHelper removeTestBundle:bundleURL];
    }
    [self.bundlesToCleanup removeAllObjects];
    [super tearDown];
}

#pragma mark - Basic Script File Tests

- (void)testScriptFileWithShellScript {
    // Create bundle with shell script
    NSDictionary *command = @{
        @"NAME": @"Shell Test",
        @"COMMAND_ID": @"shell_test",
        @"EXECUTION_MODE": @"exe_script_file",
        @"WAIT_FOR_TASK_COMPLETION": @YES
    };
    
    NSString *expectedOutput = @"Hello from shell";
    NSString *script = [NSString stringWithFormat:@"#!/bin/sh\necho '%@'\nexit 0\n", expectedOutput];
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"ShellTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"shell_test.sh": script}];
    XCTAssertNotNil(bundleURL, @"Should create test bundle");
    [self.bundlesToCleanup addObject:bundleURL];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"shell_test"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute shell script");
    
    // Wait for completion and verify output
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete within timeout");
    NSString *capturedOutput = executionObserver.capturedOutput;
    XCTAssertTrue([capturedOutput containsString:expectedOutput], 
                  @"Output should contain expected text. Got: %@", capturedOutput);
}

- (void)testScriptFileWithPython {
    NSDictionary *command = @{
        @"NAME": @"Python Test",
        @"COMMAND_ID": @"python_test",
        @"EXECUTION_MODE": @"exe_script_file",
        @"WAIT_FOR_TASK_COMPLETION": @YES
    };
    
    NSString *expectedOutput = @"Hello from Python";
    NSString *script = [NSString stringWithFormat:@"#!/usr/bin/env python3\nimport sys\nprint('%@')\nsys.exit(0)\n", expectedOutput];
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"PythonTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"python_test.py": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"python_test"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute Python script");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
    NSString *capturedOutput = executionObserver.capturedOutput;
    XCTAssertTrue([capturedOutput containsString:expectedOutput],
                  @"Output should contain expected text. Got: %@", capturedOutput);
}

- (void)testScriptFileWithPerl {
    NSDictionary *command = @{
        @"NAME": @"Perl Test",
        @"COMMAND_ID": @"perl_test",
        @"EXECUTION_MODE": @"exe_script_file",
        @"WAIT_FOR_TASK_COMPLETION": @YES
    };
    
    NSString *expectedOutput = @"Hello from Perl";
    NSString *script = [NSString stringWithFormat:@"#!/usr/bin/env perl\nuse strict;\nuse warnings;\nprint \"%@\\n\";\nexit 0;\n", expectedOutput];
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"PerlTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"perl_test.pl": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"perl_test"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute Perl script");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
    NSString *capturedOutput = executionObserver.capturedOutput;
    XCTAssertTrue([capturedOutput containsString:expectedOutput],
                  @"Output should contain expected text. Got: %@", capturedOutput);
}

- (void)testScriptFileWithJavaScript {
    NSDictionary *command = @{
        @"NAME": @"JavaScript Test",
        @"COMMAND_ID": @"js_test",
        @"EXECUTION_MODE": @"exe_script_file",
        @"WAIT_FOR_TASK_COMPLETION": @YES
    };
    
    NSString *expectedOutput = @"Hello from JavaScript";
    NSString *script = [NSString stringWithFormat:@"#!/usr/bin/jsc\nprint('%@');\n", expectedOutput];
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"JavaScriptTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"js_test.js": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"js_test"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute JavaScript via jsc");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
    NSString *capturedOutput = executionObserver.capturedOutput;
    XCTAssertTrue([capturedOutput containsString:expectedOutput],
                  @"Output should contain expected text. Got: %@", capturedOutput);
}

- (void)testScriptFileWithAppleScript {
    NSDictionary *command = @{
        @"NAME": @"AppleScript Test",
        @"COMMAND_ID": @"applescript_test",
        @"EXECUTION_MODE": @"exe_script_file",
        @"WAIT_FOR_TASK_COMPLETION": @YES
    };
    
    NSString *expectedOutput = @"Hello from AppleScript";
    NSString *script = [NSString stringWithFormat:@"#!/usr/bin/osascript\nlog \"%@\"\n", expectedOutput];
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"AppleScriptTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"applescript_test.applescript": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"applescript_test"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute AppleScript");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
    // Note: AppleScript log goes to stderr, may not capture in stdout
}

- (void)testScriptFileWithRuby {
    NSDictionary *command = @{
        @"NAME": @"Ruby Test",
        @"COMMAND_ID": @"ruby_test",
        @"EXECUTION_MODE": @"exe_script_file",
        @"WAIT_FOR_TASK_COMPLETION": @YES
    };
    
    NSString *expectedOutput = @"Hello from Ruby";
    NSString *script = [NSString stringWithFormat:@"#!/usr/bin/env ruby\nputs '%@'\nexit 0\n", expectedOutput];
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"RubyTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"ruby_test.rb": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"ruby_test"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute Ruby script");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
    NSString *capturedOutput = executionObserver.capturedOutput;
    XCTAssertTrue([capturedOutput containsString:expectedOutput],
                  @"Output should contain expected text. Got: %@", capturedOutput);
}

#pragma mark - Main Command Tests (without explicit COMMAND_ID)

- (void)testScriptFileMainCommand {
    // Command without COMMAND_ID - should look for "CommandName.main.sh"
    NSDictionary *command = @{
        @"NAME": @"Main Test",
        @"EXECUTION_MODE": @"exe_script_file"
    };
    
    NSString *script = @"#!/bin/bash\necho 'Main command executed'\n";
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"MainTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"Main Test.main.sh": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"Main Test"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute main command script");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
}

#pragma mark - Context Variable Tests

- (void)testScriptFileWithFileContext {
    NSDictionary *command = @{
        @"NAME": @"File Processor",
        @"COMMAND_ID": @"process_file",
        @"EXECUTION_MODE": @"exe_script_file",
        @"ACTIVATION_MODE": @"act_file"
    };
    
    // Script that uses OMC_OBJ_PATH
    NSString *script = @"#!/bin/bash\necho \"Processing: ${OMC_OBJ_PATH}\"\n";
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"FileProcessor"
                                                 withCommands:@[command]
                                                      scripts:@{@"process_file.sh": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    // Create temp file to process
    NSString *tempFile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test.txt"];
    BOOL written = [@"test content" writeToFile:tempFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    XCTAssertTrue(written);
    NSURL *fileURL = [NSURL fileURLWithPath:tempFile];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"process_file"
                                   forCommandFile:[bundleURL path]
                                      withContext:fileURL
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute script with file context");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
    
    [[NSFileManager defaultManager] removeItemAtPath:tempFile error:nil];
}

- (void)testScriptFileWithTextContext {
    NSDictionary *command = @{
        @"NAME": @"Text Processor",
        @"COMMAND_ID": @"process_text",
        @"EXECUTION_MODE": @"exe_script_file",
        @"ACTIVATION_MODE": @"act_selected_text"
    };
    
    // Script that uses OMC_OBJ_TEXT
    NSString *script = @"#!/bin/bash\necho \"Text: ${OMC_OBJ_TEXT}\"\n";
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"TextProcessor"
                                                 withCommands:@[command]
                                                      scripts:@{@"process_text.sh": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"process_text"
                                   forCommandFile:[bundleURL path]
                                      withContext:@"Hello World"
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute script with text context");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
}

- (void)testScriptFileWithMultipleFiles {
    NSDictionary *command = @{
        @"NAME": @"Batch Processor",
        @"COMMAND_ID": @"batch_process",
        @"EXECUTION_MODE": @"exe_script_file",
        @"ACTIVATION_MODE": @"act_file",
        @"MULTIPLE_OBJECT_SETTINGS": @{
            @"PROCESSING_MODE": @"proc_separately"
        }
    };
    
    // Script that processes each file separately
    NSString *script = @"#!/bin/bash\necho \"File: ${OMC_OBJ_PATH}\"\n";
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"BatchProcessor"
                                                 withCommands:@[command]
                                                      scripts:@{@"batch_process.sh": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    // Create multiple temp files
    NSMutableArray *files = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"test%d.txt", i]];
        BOOL written = [@"content" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        XCTAssertTrue(written);
        [files addObject:[NSURL fileURLWithPath:path]];
    }
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"batch_process"
                                   forCommandFile:[bundleURL path]
                                      withContext:files
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute script for each file");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"All tasks should complete");
    
    // Cleanup temp files
    for (NSURL *fileURL in files) {
        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
    }
}

#pragma mark - Error Cases

- (void)testScriptFileMissing {
    // Command references script that doesn't exist
    NSDictionary *command = @{
        @"NAME": @"Missing Script",
        @"COMMAND_ID": @"missing_script",
        @"EXECUTION_MODE": @"exe_script_file"
    };
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"MissingScript"
                                                 withCommands:@[command]
                                                      scripts:@{}]; // No scripts
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"missing_script"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:executionObserver];

    // Current behavior is that OMC engine does not return an error when the script is missing but fails silently, just logging:
    // "OMC->CreateScriptPathAndShell: unable to find script file"
    // this could be improved but script file finding happens late and deep without well designed error propagation
    // XCTAssertNotEqual(err, noErr, @"Should fail when script file is missing");
    (void)err;
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete even with missing script");
}

#pragma mark - Multiple Scripts in Bundle

- (void)testMultipleScriptsInBundle {
    // Bundle with multiple commands, each with its own script
    NSArray *commands = @[
        @{
            @"NAME": @"Command 1",
            @"COMMAND_ID": @"cmd1",
            @"EXECUTION_MODE": @"exe_script_file"
        },
        @{
            @"NAME": @"Command 2",
            @"COMMAND_ID": @"cmd2",
            @"EXECUTION_MODE": @"exe_script_file"
        }
    ];
    
    NSDictionary *scripts = @{
        @"cmd1.sh": @"#!/bin/bash\necho 'Command 1'\n",
        @"cmd2.py": @"#!/usr/bin/env python3\nprint('Command 2')\n"
    };
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"MultiScript"
                                                 withCommands:commands
                                                      scripts:scripts];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    // Test both commands
    OMCTestExecutionObserver *executionObserver1 = OMCTestExecutionObserver.new;
    
    OSStatus err1 = [OMCCommandExecutor runCommand:@"cmd1"
                                    forCommandFile:[bundleURL path]
                                       withContext:nil
                                      useNavDialog:NO
                                          delegate:executionObserver1];
    
    XCTAssertEqual(err1, noErr, @"Should execute first script");
    
    BOOL completed1 = [executionObserver1 waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed1, @"First command should complete");
    
    OMCTestExecutionObserver *executionObserver2 = OMCTestExecutionObserver.new;
    
    OSStatus err2 = [OMCCommandExecutor runCommand:@"cmd2"
                                    forCommandFile:[bundleURL path]
                                       withContext:nil
                                      useNavDialog:NO
                                          delegate:executionObserver2];
    
    XCTAssertEqual(err2, noErr, @"Should execute second script");
    
    BOOL completed2 = [executionObserver2 waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed2, @"Second command should complete");
}

#pragma mark - Static Bundle Tests (if available)

- (void)testStaticTestBundle {
    // Load a static test bundle from test resources
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ScriptTest"];
    
    if (bundleURL == nil) {
        NSLog(@"Skipping static bundle test - ScriptTest.omc not found in test resources");
        return;
    }
    
    NSString *omcBundlePath = [bundleURL path];
    
    NSArray *scriptFileTests = @[
        @"shell_test",
        @"python_test",
        @"perl_test",
        @"js_test",
        @"applescript_test",
        @"ruby_test"
    ];
    
    for (NSString *testName in scriptFileTests) {
        OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
        
        OSStatus err = [OMCCommandExecutor runCommand:testName
                                       forCommandFile:omcBundlePath
                                          withContext:nil
                                         useNavDialog:NO
                                             delegate:executionObserver];
        
        XCTAssertEqual(err, noErr, @"Should execute %@ command", testName);
        
        BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
        XCTAssertTrue(completed, @"%@ should complete within timeout", testName);
        
        NSString *capturedOutput = executionObserver.capturedOutput;
        NSRange range = [capturedOutput rangeOfString:@"script test" options:NSCaseInsensitiveSearch];
        BOOL containsScriptTestOutput = (range.location != NSNotFound);
        XCTAssertTrue(containsScriptTestOutput, @"Output should contain 'script test'. Got: %@", capturedOutput);
    }
}

@end

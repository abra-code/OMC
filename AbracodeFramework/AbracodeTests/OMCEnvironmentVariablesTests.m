//
//  OMCEnvironmentVariablesTests.m
//  AbracodeTests
//
//  Tests for ENVIRONMENT_VARIABLES dictionary in command descriptions
//

#import "OMCTestCase.h"
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"

@interface OMCEnvironmentVariablesTests : XCTestCase
@property (nonatomic, strong) NSMutableArray<NSURL *> *bundlesToCleanup;
@end

@implementation OMCEnvironmentVariablesTests

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

#pragma mark - Always Exported Variables (from sSpecialWordAndIDList with alwaysExport=true)

- (void)testAlwaysExportedVariables {
    // These are always exported according to CommandDescription.cp:
    // OMC_OBJ_TEXT, OMC_OBJ_PATH, OMC_OMC_RESOURCES_PATH, OMC_OMC_SUPPORT_PATH,
    // OMC_APP_BUNDLE_PATH, OMC_NIB_DLG_GUID, OMC_CURRENT_COMMAND_GUID
    
    NSDictionary *command = @{
        @"NAME": @"Always Exported Test",
        @"COMMAND_ID": @"always_exported_test",
        @"EXECUTION_MODE": @"exe_script_file"
    };
    
    // Script checks for always-exported non-dialog variables
    NSString *script = @"#!/bin/bash\n"
                       @"env | sort | grep '^OMC_' | grep -E '(APP_BUNDLE_PATH|CURRENT_COMMAND_GUID)'\n";
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"AlwaysExportedTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"always_exported_test.sh": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"always_exported_test"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute script");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
    
    NSString *output = executionObserver.capturedOutput;
    XCTAssertTrue([output containsString:@"OMC_APP_BUNDLE_PATH"],
                  @"Should export OMC_APP_BUNDLE_PATH. Output: %@", output);
    XCTAssertTrue([output containsString:@"OMC_CURRENT_COMMAND_GUID"],
                  @"Should export OMC_CURRENT_COMMAND_GUID. Output: %@", output);
}

#pragma mark - Explicit Environment Variables

- (void)testExplicitEnvironmentVariable {
    // Explicitly request OMC_OBJ_NAME (not always exported, but will be with file context)
    NSDictionary *command = @{
        @"NAME": @"Explicit Env Var Test",
        @"COMMAND_ID": @"explicit_env_test",
        @"EXECUTION_MODE": @"exe_script_file",
        @"ACTIVATION_MODE": @"act_file",
        @"ENVIRONMENT_VARIABLES": @{
            @"OMC_OBJ_NAME": @"",
            @"OMC_OBJ_PARENT_PATH": @""
        }
    };
    
    NSString *script = @"#!/bin/bash\n"
                       @"env | sort | grep '^OMC_OBJ_'\n";
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"ExplicitEnvTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"explicit_env_test.sh": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    // Create temp file for context
    NSString *tempFile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_env.txt"];
    [@"content" writeToFile:tempFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSURL *fileURL = [NSURL fileURLWithPath:tempFile];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"explicit_env_test"
                                   forCommandFile:[bundleURL path]
                                      withContext:fileURL
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute script");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
    
    NSString *output = executionObserver.capturedOutput;
    XCTAssertTrue([output containsString:@"OMC_OBJ_NAME=test_env.txt"],
                  @"Should export OMC_OBJ_NAME. Output: %@", output);
    XCTAssertTrue([output containsString:@"OMC_OBJ_PARENT_PATH="],
                  @"Should export OMC_OBJ_PARENT_PATH. Output: %@", output);
    
    [[NSFileManager defaultManager] removeItemAtPath:tempFile error:nil];
}

- (void)testEnvironmentVariableWithCustomValue {
    // Test custom environment variable with actual value
    NSDictionary *command = @{
        @"NAME": @"Custom Env Value Test",
        @"COMMAND_ID": @"custom_env_value_test",
        @"EXECUTION_MODE": @"exe_script_file",
        @"ENVIRONMENT_VARIABLES": @{
            @"CUSTOM_VAR": @"custom_value_123",
            @"ANOTHER_VAR": @"another_value"
        }
    };
    
    NSString *script = @"#!/bin/bash\n"
                       @"env | sort\n";
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"CustomEnvValueTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"custom_env_value_test.sh": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"custom_env_value_test"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute script");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
    
    NSString *output = executionObserver.capturedOutput;
    XCTAssertTrue([output containsString:@"CUSTOM_VAR=custom_value_123"],
                  @"Should export custom variable. Output: %@", output);
    XCTAssertTrue([output containsString:@"ANOTHER_VAR=another_value"],
                  @"Should export another variable. Output: %@", output);
}

#pragma mark - File Context Variables

- (void)testFileContextVariables {
    // Test all file-related context variables
    NSDictionary *command = @{
        @"NAME": @"File Context Vars",
        @"COMMAND_ID": @"file_context_vars",
        @"EXECUTION_MODE": @"exe_script_file",
        @"ACTIVATION_MODE": @"act_file",
        @"ENVIRONMENT_VARIABLES": @{
            @"OMC_OBJ_PATH": @"",
            @"OMC_OBJ_PARENT_PATH": @"",
            @"OMC_OBJ_NAME": @"",
            @"OMC_OBJ_NAME_NO_EXTENSION": @"",
            @"OMC_OBJ_EXTENSION_ONLY": @""
        }
    };
    
    NSString *script = @"#!/bin/bash\n"
                       @"echo \"OMC_OBJ_PATH=${OMC_OBJ_PATH}\"\n"
                       @"echo \"OMC_OBJ_PARENT_PATH=${OMC_OBJ_PARENT_PATH}\"\n"
                       @"echo \"OMC_OBJ_NAME=${OMC_OBJ_NAME}\"\n"
                       @"echo \"OMC_OBJ_NAME_NO_EXTENSION=${OMC_OBJ_NAME_NO_EXTENSION}\"\n"
                       @"echo \"OMC_OBJ_EXTENSION_ONLY=${OMC_OBJ_EXTENSION_ONLY}\"\n";
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"FileContextVarsTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"file_context_vars.sh": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    NSString *tempFile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"testfile.txt"];
    [@"content" writeToFile:tempFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSURL *fileURL = [NSURL fileURLWithPath:tempFile];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"file_context_vars"
                                   forCommandFile:[bundleURL path]
                                      withContext:fileURL
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute script");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
    
    NSString *output = executionObserver.capturedOutput;
    XCTAssertTrue([output containsString:@"OMC_OBJ_PATH="],
                  @"Should export OMC_OBJ_PATH. Output: %@", output);
    XCTAssertTrue([output containsString:@"OMC_OBJ_NAME=testfile.txt"],
                  @"Should export OMC_OBJ_NAME. Output: %@", output);
    XCTAssertTrue([output containsString:@"OMC_OBJ_NAME_NO_EXTENSION=testfile"],
                  @"Should export OMC_OBJ_NAME_NO_EXTENSION. Output: %@", output);
    XCTAssertTrue([output containsString:@"OMC_OBJ_EXTENSION_ONLY=txt"],
                  @"Should export OMC_OBJ_EXTENSION_ONLY. Output: %@", output);
    
    [[NSFileManager defaultManager] removeItemAtPath:tempFile error:nil];
}

#pragma mark - Text Context Variables

- (void)testTextContextVariable {
    NSDictionary *command = @{
        @"NAME": @"Text Context Test",
        @"COMMAND_ID": @"text_context_test",
        @"EXECUTION_MODE": @"exe_script_file",
        @"ACTIVATION_MODE": @"act_selected_text",
        @"ENVIRONMENT_VARIABLES": @{
            @"OMC_OBJ_TEXT": @""
        }
    };
    
    NSString *script = @"#!/bin/bash\n"
                       @"echo \"Text: ${OMC_OBJ_TEXT}\"\n";
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"TextContextTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"text_context_test.sh": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"text_context_test"
                                   forCommandFile:[bundleURL path]
                                      withContext:@"Hello World"
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute script");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
    
    NSString *output = executionObserver.capturedOutput;
    XCTAssertTrue([output containsString:@"Text: Hello World"],
                  @"Should export OMC_OBJ_TEXT. Output: %@", output);
}

#pragma mark - Multiple Variables

- (void)testMultipleEnvironmentVariables {
    NSDictionary *command = @{
        @"NAME": @"Multiple Env Vars",
        @"COMMAND_ID": @"multi_env_vars",
        @"EXECUTION_MODE": @"exe_script_file",
        @"ACTIVATION_MODE": @"act_file",
        @"ENVIRONMENT_VARIABLES": @{
            @"OMC_OBJ_NAME": @"",
            @"OMC_OBJ_EXTENSION_ONLY": @"",
            @"CUSTOM_VAR1": @"value1",
            @"CUSTOM_VAR2": @"value2",
            @"CUSTOM_VAR3": @"value3"
        }
    };
    
    NSString *script = @"#!/bin/bash\n"
                       @"env | sort\n";
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"MultiEnvVarsTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"multi_env_vars.sh": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    NSString *tempFile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"multi.dat"];
    [@"data" writeToFile:tempFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSURL *fileURL = [NSURL fileURLWithPath:tempFile];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"multi_env_vars"
                                   forCommandFile:[bundleURL path]
                                      withContext:fileURL
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute script");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
    
    NSString *output = executionObserver.capturedOutput;
    XCTAssertTrue([output containsString:@"OMC_OBJ_NAME=multi.dat"],
                  @"Should have OMC_OBJ_NAME. Output: %@", output);
    XCTAssertTrue([output containsString:@"OMC_OBJ_EXTENSION_ONLY=dat"],
                  @"Should have OMC_OBJ_EXTENSION_ONLY. Output: %@", output);
    XCTAssertTrue([output containsString:@"CUSTOM_VAR1=value1"],
                  @"Should have CUSTOM_VAR1. Output: %@", output);
    XCTAssertTrue([output containsString:@"CUSTOM_VAR2=value2"],
                  @"Should have CUSTOM_VAR2. Output: %@", output);
    XCTAssertTrue([output containsString:@"CUSTOM_VAR3=value3"],
                  @"Should have CUSTOM_VAR3. Output: %@", output);
    
    [[NSFileManager defaultManager] removeItemAtPath:tempFile error:nil];
}

#pragma mark - No ENVIRONMENT_VARIABLES Dictionary

- (void)testNoExplicitEnvironmentVariables {
    // Command without ENVIRONMENT_VARIABLES should still get always-exported vars
    NSDictionary *command = @{
        @"NAME": @"No Explicit Env Test",
        @"COMMAND_ID": @"no_explicit_env",
        @"EXECUTION_MODE": @"exe_script_file"
    };
    
    NSString *script = @"#!/bin/bash\n"
                       @"env | sort | grep '^OMC_APP_BUNDLE_PATH'\n";
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"NoExplicitEnvTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"no_explicit_env.sh": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"no_explicit_env"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute script");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
    
    NSString *output = executionObserver.capturedOutput;
    XCTAssertTrue([output containsString:@"OMC_APP_BUNDLE_PATH"],
                  @"Should still export always-exported vars. Output: %@", output);
}

- (void)testMissingNibDialogEnvironmentVariables {
    // Command without a nib dialog will not be able to populate OMC_NIB_ variables
    NSDictionary *command = @{
        @"NAME": @"Missing Dialog Env Test",
        @"COMMAND_ID": @"missing_dialog_env",
        @"EXECUTION_MODE": @"exe_script_file",
        @"ENVIRONMENT_VARIABLES": @{
            @"OMC_NIB_DLG_GUID": @"",
            @"OMC_NIB_DIALOG_CONTROL_2_VALUE": @"",
            @"OMC_NIB_TABLE_1_COLUMN_1_VALUE": @"",
            @"OMC_NIB_TABLE_1_COLUMN_0_VALUE": @"",
            @"OMC_NIB_TABLE_1_COLUMN_1_ALL_ROWS": @"",
            @"OMC_NIB_TABLE_1_COLUMN_0_ALL_ROWS": @"",
            @"OMC_NIB_WEBVIEW_3_ELEMENT_1_VALUE": @""
        }
    };
    
    NSString *script = @"#!/bin/bash\n"
                       @"env | sort | grep '^OMC_NIB'\n";
    
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"MissingDialogEnvTest"
                                                 withCommands:@[command]
                                                      scripts:@{@"missing_dialog_env.sh": script}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];
    
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;
    
    OSStatus err = [OMCCommandExecutor runCommand:@"missing_dialog_env"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:executionObserver];
    
    XCTAssertEqual(err, noErr, @"Should execute script");
    
    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Task should complete");
    
    NSString *output = executionObserver.capturedOutput;
    XCTAssertFalse([output containsString:@"OMC_NIB"],
                  @"No OMC_NIB_XXX env vars should be exported without an active nib dialog. Output: %@", output);
}

@end

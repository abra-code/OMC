//
//  OMCExecutorTests.m
//  AbracodeTests
//
//  Tests for low-level OMCExecutorRef API
//

#import "OMCTestCase.h"
#import "OMC.h"

@interface OMCExecutorTests : OMCTestCase
@end

@implementation OMCExecutorTests

- (NSString *)testName {
    return @"OMCExecutorTests";
}

- (NSDictionary *)testCommandDescription {
    return @{
        @"VERSION": @2,
        @"COMMAND_LIST": @[
            // Simple always-active command
            @{
                @"NAME": @"Echo Test",
                @"COMMAND_ID": @"echo_test",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"ACTIVATION_MODE": @"act_always",
                @"COMMAND": @[@"echo 'Hello from OMC'"]
            },
            // File context command
            @{
                @"NAME": @"Process File",
                @"COMMAND_ID": @"process_file",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"ACTIVATION_MODE": @"act_file",
                @"COMMAND": @[@"echo \"Processing: ${OMC_OBJ_PATH}\""]
            },
            // Text context command
            @{
                @"NAME": @"Process Text",
                @"COMMAND_ID": @"process_text",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"ACTIVATION_MODE": @"act_selected_text",
                @"COMMAND": @[@"echo \"Text: ${OMC_OBJ_TEXT}\""]
            },
            // Multi-object command with processing together
            @{
                @"NAME": @"Batch Process",
                @"COMMAND_ID": @"batch_process",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"ACTIVATION_MODE": @"act_file_or_folder",
                @"MULTIPLE_OBJECT_SETTINGS": @{
                    @"PROCESSING_MODE": @"proc_together",
                    @"PREFIX": @"\"",
                    @"SUFFIX": @"\"",
                    @"SEPARATOR": @" ",
                    @"SORT_METHOD": @"sort_by_name"
                },
                @"COMMAND": @[@"echo 'Processing multiple files'"]
            },
            // Command with extension filtering
            @{
                @"NAME": @"Text Files Only",
                @"COMMAND_ID": @"text_only",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"ACTIVATION_MODE": @"act_file",
                @"ACTIVATION_EXTENSIONS": @[@"txt", @"md"],
                @"COMMAND": @[@"cat \"${OMC_OBJ_PATH}\""]
            },
            // Folder-only command
            @{
                @"NAME": @"Process Folder",
                @"COMMAND_ID": @"process_folder",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"ACTIVATION_MODE": @"act_folder",
                @"COMMAND": @[@"ls \"${OMC_OBJ_PATH}\""]
            }
        ]
    };
}

#pragma mark - Executor Creation Tests

- (void)testCreateExecutorWithURL {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFURLRef)self.testPlistURL);
    XCTAssertNotEqual(executor, NULL, @"Executor should be created from URL");
    OMCReleaseExecutor(executor);
}

- (void)testCreateExecutorWithDict {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    XCTAssertNotEqual(executor, NULL, @"Executor should be created from dictionary");
    OMCReleaseExecutor(executor);
}

- (void)testCreateExecutorWithNULL {
    // NULL param tells OMC engine to load "com.abracode.OnMyCommandCMPrefs.plist" from ~/Library/Preferences
    // it may or may not be present but OMCCreateExecutor should be created and valid
    OMCExecutorRef executor = OMCCreateExecutor(NULL);
    XCTAssertNotEqual(executor, NULL, @"Executor should be created with NULL command description");
    __unused OMCCommandRef cmdRef = OMCFindCommand(executor, NULL);
    // it may return valid or invalid command depending on if you have the commands plist in Preferences or not
    OMCReleaseExecutor(executor);
}

#pragma mark - Command Lookup Tests

- (void)testFindCommandByName {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    XCTAssertNotEqual(executor, NULL);
    
    OMCCommandRef cmdRef = OMCFindCommand(executor, CFSTR("Echo Test"));
    XCTAssertTrue(OMCIsValidCommandRef(cmdRef), @"Should find command by name");
    
    OMCReleaseExecutor(executor);
}

- (void)testFindCommandById {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    XCTAssertNotEqual(executor, NULL);
    
    OMCCommandRef cmdRef = OMCFindCommand(executor, CFSTR("echo_test"));
    XCTAssertTrue(OMCIsValidCommandRef(cmdRef), @"Should find command by ID");
    
    OMCReleaseExecutor(executor);
}

- (void)testFindNonexistentCommand {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    XCTAssertNotEqual(executor, NULL);
    
    OMCCommandRef cmdRef = OMCFindCommand(executor, CFSTR("nonexistent"));
    XCTAssertFalse(OMCIsValidCommandRef(cmdRef), @"Should not find nonexistent command");
    
    OMCReleaseExecutor(executor);
}

- (void)testFindMultipleCommands {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    XCTAssertNotEqual(executor, NULL);
    
    OMCCommandRef cmd1 = OMCFindCommand(executor, CFSTR("echo_test"));
    OMCCommandRef cmd2 = OMCFindCommand(executor, CFSTR("process_file"));
    OMCCommandRef cmd3 = OMCFindCommand(executor, CFSTR("process_text"));
    
    XCTAssertTrue(OMCIsValidCommandRef(cmd1));
    XCTAssertTrue(OMCIsValidCommandRef(cmd2));
    XCTAssertTrue(OMCIsValidCommandRef(cmd3));
    XCTAssertNotEqual(cmd1, cmd2, @"Different commands should have different refs");
    
    OMCReleaseExecutor(executor);
}

#pragma mark - Command Info Tests

- (void)testGetCommandInfoObjects {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    OMCCommandRef cmdRef = OMCFindCommand(executor, CFSTR("process_file"));
    
    UInt32 objectsInfo = 0;
    OSStatus err = OMCGetCommandInfo(executor, cmdRef, kOmcInfo_CommandObjects, &objectsInfo);
    
    XCTAssertEqual(err, noErr, @"Should get command info");
    XCTAssertTrue((objectsInfo & kOmcCommandContainsFileObject) != 0, @"Should detect file object");
    
    OMCReleaseExecutor(executor);
}

- (void)testGetCommandInfoActivationType {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    OMCCommandRef cmdRef = OMCFindCommand(executor, CFSTR("process_text"));
    
    UInt32 activationType = 0;
    OSStatus err = OMCGetCommandInfo(executor, cmdRef, kOmcInfo_ActivationType, &activationType);
    
    XCTAssertEqual(err, noErr);
    XCTAssertEqual(activationType, kActiveSelectedText, @"Should return correct activation type");
    
    OMCReleaseExecutor(executor);
}

- (void)testGetCommandInfoExecutionOptions {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    OMCCommandRef cmdRef = OMCFindCommand(executor, CFSTR("echo_test"));
    
    UInt32 executionOptions = 0;
    OSStatus err = OMCGetCommandInfo(executor, cmdRef, kOmcInfo_ExecutionOptions, &executionOptions);
    
    XCTAssertEqual(err, noErr, @"Should get execution options");
    
    OMCReleaseExecutor(executor);
}

- (void)testGetCommandInfoForInvalidCommand {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    OMCCommandRef cmdRef = kOmcUnspecifiedCommand;
    
    UInt32 objectsInfo = 0;
    OSStatus err = OMCGetCommandInfo(executor, cmdRef, kOmcInfo_CommandObjects, &objectsInfo);
    
    XCTAssertNotEqual(err, noErr, @"Should fail for invalid command");
    
    OMCReleaseExecutor(executor);
}

#pragma mark - Context Examination Tests

- (void)testExamineContextWithFile {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    OMCCommandRef cmdRef = OMCFindCommand(executor, CFSTR("process_file"));
    
    NSURL *testFile = [self createTempFileWithName:@"test.txt" content:@"test content"];
    
    OSStatus err = OMCExamineContext(executor, cmdRef, (__bridge CFURLRef)testFile);
    XCTAssertEqual(err, noErr, @"Should examine file context successfully");
    
    OMCReleaseExecutor(executor);
}

- (void)testExamineContextWithMultipleFiles {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    OMCCommandRef cmdRef = OMCFindCommand(executor, CFSTR("batch_process"));
    
    NSMutableArray *files = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        NSURL *file = [self createTempFileWithName:[NSString stringWithFormat:@"test%d.txt", i] 
                                           content:@"test"];
        [files addObject:file];
    }
    
    OSStatus err = OMCExamineContext(executor, cmdRef, (__bridge CFArrayRef)files);
    XCTAssertEqual(err, noErr, @"Should examine multiple files");
    
    OMCReleaseExecutor(executor);
}

- (void)testExamineContextWithText {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    OMCCommandRef cmdRef = OMCFindCommand(executor, CFSTR("process_text"));
    
    OSStatus err = OMCExamineContext(executor, cmdRef, CFSTR("Test text content"));
    XCTAssertEqual(err, noErr, @"Should examine text context");
    
    OMCReleaseExecutor(executor);
}

- (void)testExamineContextWithNilContext {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    OMCCommandRef cmdRef = OMCFindCommand(executor, CFSTR("echo_test"));
    
    // act_always commands should work with nil context
    OSStatus err = OMCExamineContext(executor, cmdRef, NULL);
    XCTAssertEqual(err, noErr, @"Should handle nil context for always-active command");
    
    OMCReleaseExecutor(executor);
}

- (void)testExamineContextWithWrongContextType {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    OMCCommandRef cmdRef = OMCFindCommand(executor, CFSTR("process_file"));
    
    // Passing text to a file-only command
    OSStatus err = OMCExamineContext(executor, cmdRef, CFSTR("text instead of file"));
    XCTAssertNotEqual(err, noErr, @"Should fail with wrong context type");
    
    OMCReleaseExecutor(executor);
}

- (void)testExamineContextWithFolder {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    OMCCommandRef cmdRef = OMCFindCommand(executor, CFSTR("process_folder"));
    
    // Use NSTemporaryDirectory as a test folder
    NSURL *folderURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    
    OSStatus err = OMCExamineContext(executor, cmdRef, (__bridge CFURLRef)folderURL);
    XCTAssertEqual(err, noErr, @"Should examine folder context");
    
    OMCReleaseExecutor(executor);
}

#pragma mark - Retain/Release Tests

- (void)testRetainReleaseExecutor {
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)self.testPlistDict);
    XCTAssertNotEqual(executor, NULL);
    
    OMCRetainExecutor(executor);
    OMCReleaseExecutor(executor); // First release (balanced retain)
    OMCReleaseExecutor(executor); // Second release (original create) - should not crash
}

- (void)testReleaseNullExecutor {
    // Should not crash
    OMCReleaseExecutor(NULL);
}

- (void)testRetainNullExecutor {
    // Should not crash
    OMCRetainExecutor(NULL);
}

@end

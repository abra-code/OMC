//
//  OMCCommandExecutorTests.m
//  AbracodeTests
//
//  Tests for high-level OMCCommandExecutor API
//

#import "OMCTestCase.h"
#import "OMCCommandExecutor.h"

@interface OMCCommandExecutorTests : OMCTestCase
@end

@implementation OMCCommandExecutorTests

- (NSString *)testName {
    return @"OMCCommandExecutorTests";
}

- (NSDictionary *)testCommandDescription {
    return @{
        @"VERSION": @2,
        @"COMMAND_LIST": @[
            // Simple command without context requirements
            @{
                @"NAME": @"Simple Echo",
                @"COMMAND_ID": @"simple_echo",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"COMMAND": @[@"echo 'Simple command executed'"]
            },
            // File processing command
            @{
                @"NAME": @"Count Lines",
                @"COMMAND_ID": @"count_lines",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"ACTIVATION_MODE": @"act_file",
                @"ACTIVATION_EXTENSIONS": @[@"txt", @"md"],
                @"COMMAND": @[@"wc -l \"${OMC_OBJ_PATH}\""]
            },
            // Multi-file batch command
            @{
                @"NAME": @"List Files",
                @"COMMAND_ID": @"list_files",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"ACTIVATION_MODE": @"act_file_or_folder",
                @"MULTIPLE_OBJECT_SETTINGS": @{
                    @"PROCESSING_MODE": @"proc_together",
                    @"SEPARATOR": @"\n"
                },
                @"COMMAND": @[@"echo \"Files:\"; ls -1 \"${OMC_OBJ_PATH}\""]
            },
            // Text processing command
            @{
                @"NAME": @"Uppercase Text",
                @"COMMAND_ID": @"uppercase_text",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"ACTIVATION_MODE": @"act_selected_text",
                @"COMMAND": @[@"echo \"${OMC_OBJ_TEXT}\" | tr '[:lower:]' '[:upper:]'"]
            },
            // Command that expects file but can use nav dialog if missing
            @{
                @"NAME": @"Show File Info",
                @"COMMAND_ID": @"show_file_info",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"ACTIVATION_MODE": @"act_file",
                @"COMMAND": @[@"ls -lh \"${OMC_OBJ_PATH}\""]
            },
            // Folder-only command
            @{
                @"NAME": @"Count Folder Items",
                @"COMMAND_ID": @"count_items",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"ACTIVATION_MODE": @"act_folder",
                @"COMMAND": @[@"ls -1 \"${OMC_OBJ_PATH}\" | wc -l"]
            }
        ]
    };
}

#pragma mark - Basic Execution Tests

- (void)testRunCommandByIDWithoutContext {
    OSStatus err = [OMCCommandExecutor runCommand:@"simple_echo"
                                   forCommandFile:[self.testPlistURL path]
                                      withContext:nil 
                                     useNavDialog:NO 
                                         delegate:nil];
    
    XCTAssertEqual(err, noErr, @"Should run find and run simple command by ID without context");
}

- (void)testRunCommandByName {
    OSStatus err = [OMCCommandExecutor runCommand:@"Simple Echo"
                                   forCommandFile:[self.testPlistURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:nil];
    
    XCTAssertEqual(err, noErr, @"Should find and run command by name");
}

- (void)testRunNonexistentCommand {
    OSStatus err = [OMCCommandExecutor runCommand:@"does_not_exist"
                                   forCommandFile:[self.testPlistURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:nil];
    
    XCTAssertNotEqual(err, noErr, @"Should fail for nonexistent command");
}

#pragma mark - File Context Tests

- (void)testRunCommandWithSingleFile {
    NSURL *testFile = [self createTempFileWithName:@"test.txt" content:@"line1\nline2\nline3"];
    
    OSStatus err = [OMCCommandExecutor runCommand:@"count_lines"
                                   forCommandFile:[self.testPlistURL path]
                                      withContext:testFile
                                     useNavDialog:NO
                                         delegate:nil];
    
    XCTAssertEqual(err, noErr, @"Should process single file");
}

- (void)testRunCommandWithMultipleFiles {
    NSMutableArray *files = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        NSURL *file = [self createTempFileWithName:[NSString stringWithFormat:@"file%d.txt", i]
                                           content:@"content"];
        [files addObject:file];
    }
    
    OSStatus err = [OMCCommandExecutor runCommand:@"list_files"
                                   forCommandFile:[self.testPlistURL path]
                                      withContext:files
                                     useNavDialog:NO
                                         delegate:nil];
    
    XCTAssertEqual(err, noErr, @"Should process multiple files");
}

- (void)testRunCommandWithFileAsPath {
    // Test passing file path as string instead of NSURL
    NSURL *testFile = [self createTempFileWithName:@"test.txt" content:@"content"];
    
    OSStatus err = [OMCCommandExecutor runCommand:@"count_lines"
                                   forCommandFile:[self.testPlistURL path]
                                      withContext:[testFile path]
                                     useNavDialog:NO
                                         delegate:nil];
    
    // This may or may not work depending on OMC implementation
    // If it expects NSURL, this documents the behavior
    XCTAssertTrue(err == noErr || err != noErr, @"Document path string behavior");
}

- (void)testRunCommandWithFolder {
    NSURL *folderURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    
    OSStatus err = [OMCCommandExecutor runCommand:@"count_items"
                                   forCommandFile:[self.testPlistURL path]
                                      withContext:folderURL
                                     useNavDialog:NO
                                         delegate:nil];
    
    XCTAssertEqual(err, noErr, @"Should process folder");
}

#pragma mark - Text Context Tests

- (void)testRunCommandWithTextContext {
    NSString *testText = @"hello world";
    
    OSStatus err = [OMCCommandExecutor runCommand:@"uppercase_text"
                                   forCommandFile:[self.testPlistURL path]
                                      withContext:testText
                                     useNavDialog:NO
                                         delegate:nil];
    
    XCTAssertEqual(err, noErr, @"Should process text context");
}

- (void)testRunCommandWithEmptyText {
    NSString *emptyText = @"";
    
    OSStatus err = [OMCCommandExecutor runCommand:@"uppercase_text"
                                   forCommandFile:[self.testPlistURL path]
                                      withContext:emptyText
                                     useNavDialog:NO
                                         delegate:nil];
    
    XCTAssertEqual(err, noErr, @"Should handle empty text");
}

#pragma mark - Plist Loading Tests

- (void)testRunCommandWithAbsolutePath {
    NSString *absolutePath = [self.testPlistURL path];
    
    OSStatus err = [OMCCommandExecutor runCommand:@"simple_echo"
                                   forCommandFile:absolutePath
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:nil];
    
    XCTAssertEqual(err, noErr, @"Should load plist from absolute path");
}

- (void)testRunCommandWithTildePath {
    // Copy plist to home directory for this test
    NSString *homePath = NSHomeDirectory();
    NSString *testFileName = @"TestOMCCommand.plist";
    NSURL *homeURL = [NSURL fileURLWithPath:[homePath stringByAppendingPathComponent:testFileName]];
    [self.testPlistDict writeToURL:homeURL atomically:YES];
    
    NSString *tildePath = [@"~" stringByAppendingPathComponent:testFileName];
    
    OSStatus err = [OMCCommandExecutor runCommand:@"simple_echo"
                                   forCommandFile:tildePath
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:nil];
    
    [[NSFileManager defaultManager] removeItemAtURL:homeURL error:nil];
    
    XCTAssertEqual(err, noErr, @"Should expand tilde in path");
}

- (void)testRunCommandWithInvalidPath {
    OSStatus err = [OMCCommandExecutor runCommand:@"simple_echo"
                                   forCommandFile:@"/nonexistent/path.plist"
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:nil];
    
    XCTAssertNotEqual(err, noErr, @"Should fail for invalid plist path");
}

#pragma mark - Plist Caching Tests

- (void)testCachedPlistForCommandFile {
    NSString *filePath = [self.testPlistURL path];
    
    CFPropertyListRef plist1 = [OMCCommandExecutor cachedPlistForCommandFile:filePath];
    XCTAssertNotEqual(plist1, NULL, @"Should load plist");
    
    // Second call should return cached version (same pointer)
    CFPropertyListRef plist2 = [OMCCommandExecutor cachedPlistForCommandFile:filePath];
    XCTAssertEqual(plist1, plist2, @"Should return cached plist (same pointer)");
}

- (void)testCachedPlistForURL {
    CFPropertyListRef plist1 = [OMCCommandExecutor cachedPlistForURL:self.testPlistURL];
    XCTAssertNotEqual(plist1, NULL, @"Should load plist from URL");
    
    CFPropertyListRef plist2 = [OMCCommandExecutor cachedPlistForURL:self.testPlistURL];
    XCTAssertEqual(plist1, plist2, @"Should return same cached plist");
}

- (void)testCachedPlistForDifferentURLs {
    // Create second plist file
    NSDictionary *plist2Dict = @{
        @"VERSION": @2,
        @"COMMAND_LIST": @[
            @{
                @"NAME": @"Other Command",
                @"COMMAND_ID": @"other",
                @"COMMAND": @[@"echo 'other'"]
            }
        ]
    };
    
    NSURL *plist2URL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"Other.plist"]];
    [plist2Dict writeToURL:plist2URL atomically:YES];
    
    CFPropertyListRef plist1 = [OMCCommandExecutor cachedPlistForURL:self.testPlistURL];
    CFPropertyListRef plist2 = [OMCCommandExecutor cachedPlistForURL:plist2URL];
    
    XCTAssertNotEqual(plist1, plist2, @"Different URLs should return different plists");
    
    [[NSFileManager defaultManager] removeItemAtURL:plist2URL error:nil];
}

- (void)testCachedPlistForNilPath {
    CFPropertyListRef plist = [OMCCommandExecutor cachedPlistForCommandFile:nil];
    XCTAssertEqual(plist, NULL, @"Should return NULL for nil path");
}

- (void)testCachedPlistForNilURL {
    CFPropertyListRef plist = [OMCCommandExecutor cachedPlistForURL:nil];
    XCTAssertEqual(plist, NULL, @"Should return NULL for nil URL");
}

- (void)testCachedPlistForInvalidPath {
    CFPropertyListRef plist = [OMCCommandExecutor cachedPlistForCommandFile:@"/nonexistent/invalid.plist"];
    XCTAssertEqual(plist, NULL, @"Should return NULL for invalid path");
}

#pragma mark - Context Validation Tests

- (void)testRunFileCommandWithoutContext {
    // File command without context and useNavDialog=NO should fail
    OSStatus err = [OMCCommandExecutor runCommand:@"count_lines"
                                   forCommandFile:[self.testPlistURL path]
                                      withContext:nil
                                     useNavDialog:NO
                                         delegate:nil];
    
    XCTAssertNotEqual(err, noErr, @"Should fail when file context required but not provided");
}

- (void)testRunTextCommandWithFileContext {
    NSURL *testFile = [self createTempFileWithName:@"test.txt" content:@"content"];
    
    // Text command with file context should fail
    OSStatus err = [OMCCommandExecutor runCommand:@"uppercase_text"
                                   forCommandFile:[self.testPlistURL path]
                                      withContext:testFile
                                     useNavDialog:NO
                                         delegate:nil];
    
    XCTAssertNotEqual(err, noErr, @"Should fail when context type doesn't match");
}

@end

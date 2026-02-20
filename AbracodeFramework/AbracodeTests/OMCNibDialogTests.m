//
//  OMCNibDialogTests.m
//  AbracodeTests
//
//  Integration tests for nib dialog controller (setControlValues: code paths)
//

#import "OMCTestCase.h"
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"

@interface OMCNibDialogTests : XCTestCase
@end

@implementation OMCNibDialogTests

#pragma mark - Helpers

- (BOOL)pollForFileAtPath:(NSString *)path timeout:(NSTimeInterval)timeout {
    NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:timeout];
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    NSFileManager *fm = [NSFileManager defaultManager];

    while ([timeoutDate timeIntervalSinceNow] > 0) {
        if ([fm fileExistsAtPath:path]) {
            return YES;
        }
        BOOL ranLoop = [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        if (!ranLoop) {
            [NSThread sleepForTimeInterval:0.1];
        }
    }
    return [fm fileExistsAtPath:path];
}

- (NSDictionary<NSString *, NSString *> *)readDiagnosticFile:(NSString *)path {
    NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (contents == nil) return @{};

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSString *line in [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location != NSNotFound) {
            NSString *key = [line substringToIndex:eq.location];
            NSString *value = [line substringFromIndex:eq.location + 1];
            dict[key] = value;
        }
    }
    return [dict copy];
}

- (void)cleanupDiagnosticFilesForUUID:(NSString *)uuid prefix:(NSString *)prefix {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *suffix in @[@"init", @"term"]) {
        NSString *path = [NSString stringWithFormat:@"/tmp/OMC_test_%@_%@_%@", prefix, suffix, uuid];
        [fm removeItemAtPath:path error:nil];
        [fm removeItemAtPath:[path stringByAppendingString:@".tmp"] error:nil];
    }
}

/// Opens the Browser dialog, waits for observer completion, returns captured UUID
- (NSString *)openNibDialogWithBundlePath:(NSString *)omcBundlePath {
    NSURL *homeURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"Browser"
                                   forCommandFile:omcBundlePath
                                      withContext:homeURL
                                     useNavDialog:NO
                                         delegate:executionObserver];

    XCTAssertEqual(err, noErr, @"Should execute Browser command");

    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Browser should complete within timeout");

    NSString *uuid = [executionObserver.capturedOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    XCTAssertTrue(uuid.length > 0, @"Should capture dialog UUID");
    return uuid;
}

/// Closes the nib dialog by sending browser.close.window with the UUID as text context
- (void)closeNibDialogWithUUID:(NSString *)uuid bundlePath:(NSString *)omcBundlePath {
    OMCTestExecutionObserver *closeObserver = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"browser.close.window"
                                   forCommandFile:omcBundlePath
                                      withContext:uuid
                                     useNavDialog:NO
                                         delegate:closeObserver];

    XCTAssertEqual(err, noErr, @"Should execute browser.close.window command");

    BOOL completed = [closeObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"browser.close.window should complete within timeout");
}

#pragma mark - Tests

- (void)testNibDialogInitialization {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"Browser"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - Browser.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openNibDialogWithBundlePath:omcBundlePath];

    // Poll for the diagnostic file written by the init script
    NSString *initPath = [NSString stringWithFormat:@"/tmp/OMC_test_nib_init_%@", uuid];
    BOOL found = [self pollForFileAtPath:initPath timeout:5.0];
    XCTAssertTrue(found, @"Init diagnostic file should be created");

    NSDictionary *diag = [self readDiagnosticFile:initPath];
    XCTAssertEqualObjects(diag[@"INIT_COMPLETE"], @"YES", @"Init script should complete");
    XCTAssertEqualObjects(diag[@"OMC_NIB_DLG_GUID"], uuid, @"UUID should match");
    XCTAssertTrue([diag[@"OMC_OBJ_PATH"] length] > 0, @"OMC_OBJ_PATH should be non-empty");
    XCTAssertTrue([diag[@"OMC_OMC_SUPPORT_PATH"] containsString:@"Support"],
                  @"OMC_OMC_SUPPORT_PATH should contain 'Support'");

    [self closeNibDialogWithUUID:uuid bundlePath:omcBundlePath];
    [self cleanupDiagnosticFilesForUUID:uuid prefix:@"nib"];
}

- (void)testNibDialogTermination {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"Browser"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - Browser.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openNibDialogWithBundlePath:omcBundlePath];

    // Wait for init to complete first
    NSString *initPath = [NSString stringWithFormat:@"/tmp/OMC_test_nib_init_%@", uuid];
    BOOL initFound = [self pollForFileAtPath:initPath timeout:5.0];
    XCTAssertTrue(initFound, @"Init diagnostic file should be created");

    // Close the dialog (triggers terminate cancel subcommand)
    [self closeNibDialogWithUUID:uuid bundlePath:omcBundlePath];

    // Poll for the termination diagnostic file
    NSString *termPath = [NSString stringWithFormat:@"/tmp/OMC_test_nib_term_%@", uuid];
    BOOL termFound = [self pollForFileAtPath:termPath timeout:5.0];
    XCTAssertTrue(termFound, @"Termination diagnostic file should be created");

    NSDictionary *diag = [self readDiagnosticFile:termPath];
    XCTAssertEqualObjects(diag[@"TERM_COMPLETE"], @"YES", @"Termination script should complete");
    XCTAssertEqualObjects(diag[@"OMC_NIB_DLG_GUID"], uuid, @"UUID should match");

    // Verify control values round-trip: init set control 8 to pwd of OMC_OBJ_PATH
    NSString *control8Value = diag[@"CONTROL_8_VALUE"];
    XCTAssertTrue([control8Value length] > 0,
                  @"Control 8 (path field) should have a value set during init");

    // Verify table data round-trip: init populated table 1 with ls output
    NSString *tableAllRows = diag[@"TABLE_1_COL_1_ALL_ROWS"];
    XCTAssertTrue([tableAllRows length] > 0,
                  @"Table 1 column 1 should have rows populated during init");

    [self cleanupDiagnosticFilesForUUID:uuid prefix:@"nib"];
}

- (void)testNibDialogControlOperationsViaInit {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"Browser"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - Browser.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openNibDialogWithBundlePath:omcBundlePath];

    // The init script exercises omc_dialog_control calls:
    // table columns, widths, rows, value, enable, show, select
    // If any call crashes, the diagnostic file won't be written
    NSString *initPath = [NSString stringWithFormat:@"/tmp/OMC_test_nib_init_%@", uuid];
    BOOL found = [self pollForFileAtPath:initPath timeout:5.0];
    XCTAssertTrue(found, @"Init diagnostic file should be created - proves all omc_dialog_control calls succeeded");

    NSDictionary *diag = [self readDiagnosticFile:initPath];
    XCTAssertEqualObjects(diag[@"INIT_COMPLETE"], @"YES",
                          @"All omc_dialog_control calls completed without errors");

    [self closeNibDialogWithUUID:uuid bundlePath:omcBundlePath];
    [self cleanupDiagnosticFilesForUUID:uuid prefix:@"nib"];
}

- (void)testNibDialogInvokeCloseOnWindow {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"Browser"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - Browser.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openNibDialogWithBundlePath:omcBundlePath];

    // Wait for init to complete first
    NSString *initPath = [NSString stringWithFormat:@"/tmp/OMC_test_nib_init_%@", uuid];
    BOOL initFound = [self pollForFileAtPath:initPath timeout:5.0];
    XCTAssertTrue(initFound, @"Init diagnostic file should be created");

    // Close the window via INVOKE (omc_invoke close) instead of omc_terminate_cancel
    // This exercises the INVOKE code path with omc_window target in setControlValues:
    OMCTestExecutionObserver *invokeObserver = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"browser.invoke.close"
                                   forCommandFile:omcBundlePath
                                      withContext:uuid
                                     useNavDialog:NO
                                         delegate:invokeObserver];

    XCTAssertEqual(err, noErr, @"Should execute browser.invoke.close command");

    BOOL completed = [invokeObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"browser.invoke.close should complete within timeout");

    // The INVOKE close triggers windowWillClose: → terminate → END_CANCEL_SUBCOMMAND_ID
    // which writes the termination diagnostic file
    NSString *termPath = [NSString stringWithFormat:@"/tmp/OMC_test_nib_term_%@", uuid];
    BOOL termFound = [self pollForFileAtPath:termPath timeout:5.0];
    XCTAssertTrue(termFound, @"INVOKE close should trigger terminate cancel subcommand");

    NSDictionary *diag = [self readDiagnosticFile:termPath];
    XCTAssertEqualObjects(diag[@"TERM_COMPLETE"], @"YES",
                          @"Terminate script should complete after INVOKE close");

    [self cleanupDiagnosticFilesForUUID:uuid prefix:@"nib"];
}

@end

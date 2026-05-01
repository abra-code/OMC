//
//  OMCActionUIInsertTests.m
//  AbracodeTests
//
//  Integration tests for ActionUI runtime structural mutation APIs:
//    omc_insert_element   — insert a new element into a flat container
//    omc_insert_element_row — insert a new row into a Grid rows container
//    omc_remove_element   — remove an element from its parent container
//
//  All operations are exercised in the init subcommand of the ActionUI-Insert.omc
//  test bundle. The subcommand captures per-operation success via shell exit codes
//  and writes a diagnostic file to /tmp/OMC_test_insert_init_<UUID>.
//
//  The diagnostic format is KEY=VALUE, one per line. Test assertions read
//  specific keys to verify each operation completed without crash.
//

#import "OMCTestCase.h"
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"

// enable only in OMC version 5.0 or later
#if CURRENT_OMC_VERSION >= 50000

@interface OMCActionUIInsertTests : XCTestCase
@end

@implementation OMCActionUIInsertTests

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

- (void)cleanupDiagnosticFilesForUUID:(NSString *)uuid {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *suffix in @[@"init", @"term"]) {
        NSString *path = [NSString stringWithFormat:@"/tmp/OMC_test_insert_%@_%@", suffix, uuid];
        [fm removeItemAtPath:path error:nil];
        [fm removeItemAtPath:[path stringByAppendingString:@".tmp"] error:nil];
    }
}

/// Opens the ActionUI Insert window, waits for the executor to complete, returns the captured UUID.
- (NSString *)openInsertWindowWithBundlePath:(NSString *)omcBundlePath {
    NSURL *homeURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"Insert"
                                   forCommandFile:omcBundlePath
                                      withContext:homeURL
                                     useNavDialog:NO
                                 allowKeyWindowSubcommand:NO
                                         delegate:observer];

    XCTAssertEqual(err, noErr, @"Should execute Insert command without error");

    BOOL completed = [observer waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Insert command should complete within timeout");

    NSString *uuid = [observer.capturedOutput
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    XCTAssertTrue(uuid.length > 0, @"Should capture window UUID from Insert command stdout");
    return uuid;
}

/// Closes the Insert window by sending insert.close.window with the UUID as text context.
- (void)closeInsertWindowWithUUID:(NSString *)uuid bundlePath:(NSString *)omcBundlePath {
    OMCTestExecutionObserver *closeObserver = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"insert.close.window"
                                   forCommandFile:omcBundlePath
                                      withContext:uuid
                                     useNavDialog:NO
                                 allowKeyWindowSubcommand:NO
                                         delegate:closeObserver];

    XCTAssertEqual(err, noErr, @"Should execute insert.close.window command");

    BOOL completed = [closeObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"insert.close.window should complete within timeout");
}

/// Opens the window and polls until the init diagnostic file is written, then returns its contents.
- (NSDictionary<NSString *, NSString *> *)openWindowAndWaitForInitDiagnosticWithBundlePath:(NSString *)omcBundlePath
                                                                                      uuid:(NSString **)outUUID {
    NSString *uuid = [self openInsertWindowWithBundlePath:omcBundlePath];
    if (outUUID) *outUUID = uuid;

    NSString *initPath = [NSString stringWithFormat:@"/tmp/OMC_test_insert_init_%@", uuid];
    BOOL found = [self pollForFileAtPath:initPath timeout:8.0];
    XCTAssertTrue(found, @"Init diagnostic file should be written after all insert/remove operations complete");

    return [self readDiagnosticFile:initPath];
}

#pragma mark - Tests

- (void)testActionUIInsertWindowOpens {
    // Verifies basic lifecycle: open -> UUID captured -> close -> terminate script ran.
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Insert"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Insert.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openInsertWindowWithBundlePath:omcBundlePath];

    [self closeInsertWindowWithUUID:uuid bundlePath:omcBundlePath];

    NSString *termPath = [NSString stringWithFormat:@"/tmp/OMC_test_insert_term_%@", uuid];
    BOOL found = [self pollForFileAtPath:termPath timeout:5.0];
    XCTAssertTrue(found, @"Termination diagnostic file should be created on close");

    NSDictionary *diag = [self readDiagnosticFile:termPath];
    XCTAssertEqualObjects(diag[@"TERM_COMPLETE"], @"YES", @"Termination script should complete");
    XCTAssertEqualObjects(diag[@"OMC_ACTIONUI_WINDOW_UUID"], uuid, @"UUID in term file should match");

    [self cleanupDiagnosticFilesForUUID:uuid];
}

- (void)testActionUIInsertElementAppend {
    // Verifies omc_insert_element with default position (append) succeeds.
    // The init subcommand appends a Text element (id=30) to VStack id=10 and
    // records INSERT_ELEMENT_OK=YES on success.
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Insert"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Insert.omc not found in test resources");
        return;
    }

    NSString *uuid = nil;
    NSDictionary *diag = [self openWindowAndWaitForInitDiagnosticWithBundlePath:[bundleURL path] uuid:&uuid];

    XCTAssertEqualObjects(diag[@"INIT_COMPLETE"], @"YES", @"Init subcommand should complete");
    XCTAssertEqualObjects(diag[@"INSERT_ELEMENT_OK"], @"YES",
                          @"omc_insert_element (append) into VStack id=10 should succeed");

    [self closeInsertWindowWithUUID:uuid bundlePath:[bundleURL path]];
    [self cleanupDiagnosticFilesForUUID:uuid];
}

- (void)testActionUIInsertElementWithPositions {
    // Verifies omc_insert_element with prepend and after:<siblingID> positions.
    // The init subcommand:
    //   - Prepends a Text element (id=31) into VStack id=10 → INSERT_ELEMENT_PREPEND_OK=YES
    //   - Inserts a Text element (id=32) after sibling id=12 → INSERT_ELEMENT_AFTER_OK=YES
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Insert"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Insert.omc not found in test resources");
        return;
    }

    NSString *uuid = nil;
    NSDictionary *diag = [self openWindowAndWaitForInitDiagnosticWithBundlePath:[bundleURL path] uuid:&uuid];

    XCTAssertEqualObjects(diag[@"INIT_COMPLETE"], @"YES", @"Init subcommand should complete");
    XCTAssertEqualObjects(diag[@"INSERT_ELEMENT_PREPEND_OK"], @"YES",
                          @"omc_insert_element (prepend) into VStack id=10 should succeed");
    XCTAssertEqualObjects(diag[@"INSERT_ELEMENT_AFTER_OK"], @"YES",
                          @"omc_insert_element (after:12) into VStack id=10 should succeed");

    [self closeInsertWindowWithUUID:uuid bundlePath:[bundleURL path]];
    [self cleanupDiagnosticFilesForUUID:uuid];
}

- (void)testActionUIInsertElementRow {
    // Verifies omc_insert_element_row inserts a row into a Grid container.
    // The init subcommand appends a two-cell row (id=40, id=41) to Grid id=5
    // and records INSERT_ELEMENT_ROW_OK=YES on success.
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Insert"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Insert.omc not found in test resources");
        return;
    }

    NSString *uuid = nil;
    NSDictionary *diag = [self openWindowAndWaitForInitDiagnosticWithBundlePath:[bundleURL path] uuid:&uuid];

    XCTAssertEqualObjects(diag[@"INIT_COMPLETE"], @"YES", @"Init subcommand should complete");
    XCTAssertEqualObjects(diag[@"INSERT_ELEMENT_ROW_OK"], @"YES",
                          @"omc_insert_element_row (append) into Grid id=5 should succeed");

    [self closeInsertWindowWithUUID:uuid bundlePath:[bundleURL path]];
    [self cleanupDiagnosticFilesForUUID:uuid];
}

- (void)testActionUIRemoveElement {
    // Verifies omc_remove_element removes an element by its viewID.
    // The init subcommand removes Text element id=11 from VStack id=10
    // and records REMOVE_ELEMENT_OK=YES on success.
    //
    // Note: removal happens after the insert steps, so id=11 (Item A) may have
    // already had sibling elements inserted around it. This exercises the
    // locateParent search path used by removeElement.
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Insert"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Insert.omc not found in test resources");
        return;
    }

    NSString *uuid = nil;
    NSDictionary *diag = [self openWindowAndWaitForInitDiagnosticWithBundlePath:[bundleURL path] uuid:&uuid];

    XCTAssertEqualObjects(diag[@"INIT_COMPLETE"], @"YES", @"Init subcommand should complete");
    XCTAssertEqualObjects(diag[@"REMOVE_ELEMENT_OK"], @"YES",
                          @"omc_remove_element on id=11 should succeed");

    [self closeInsertWindowWithUUID:uuid bundlePath:[bundleURL path]];
    [self cleanupDiagnosticFilesForUUID:uuid];
}

@end

#endif // CURRENT_OMC_VERSION >= 50000

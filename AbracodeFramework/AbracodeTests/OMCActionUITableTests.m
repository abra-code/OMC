//
//  OMCActionUITableTests.m
//  AbracodeTests
//
//  Integration tests for ActionUI table dialog.
//  Exercises OMC_ACTIONUI_TABLE_N_COLUMN_M_VALUE and OMC_ACTIONUI_TABLE_N_COLUMN_M_ALL_ROWS
//  special words / environment variables using the ActionUI-Table.omc test bundle.
//
//  The bundle's Table command opens a non-modal window (IS_BLOCKING=false) and prints
//  the window UUID to stdout.  The INIT_SUBCOMMAND_ID (table.dialog.init) populates
//  the table with three rows (John/Enable, Jack/Disable, Jill/Hide).
//  The END_CANCEL_SUBCOMMAND_ID (table.dialog.terminate.cancel) writes a diagnostic
//  file to /tmp/OMC_test_actionui_term_<UUID> capturing all the table env vars.
//

#import "OMCTestCase.h"
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"

@interface OMCActionUITableTests : XCTestCase
@end

@implementation OMCActionUITableTests

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

- (void)cleanupTermDiagnosticForUUID:(NSString *)uuid {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_term_%@", uuid];
    [fm removeItemAtPath:path error:nil];
    [fm removeItemAtPath:[path stringByAppendingString:@".tmp"] error:nil];
}

/// Opens the ActionUI Table dialog, waits for observer completion, returns captured UUID.
- (NSString *)openActionUITableDialogWithBundlePath:(NSString *)omcBundlePath {
    NSURL *homeURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"Table"
                                   forCommandFile:omcBundlePath
                                      withContext:homeURL
                                     useNavDialog:NO
                                         delegate:executionObserver];

    XCTAssertEqual(err, noErr, @"Should execute Table command");

    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Table command should complete within timeout");

    NSString *uuid = [executionObserver.capturedOutput
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    XCTAssertTrue(uuid.length > 0, @"Should capture window UUID from Table command stdout");
    return uuid;
}

/// Closes the ActionUI table dialog by sending table.close.window with the UUID as text context.
- (void)closeActionUITableDialogWithUUID:(NSString *)uuid bundlePath:(NSString *)omcBundlePath {
    OMCTestExecutionObserver *closeObserver = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"table.close.window"
                                   forCommandFile:omcBundlePath
                                      withContext:uuid
                                     useNavDialog:NO
                                         delegate:closeObserver];

    XCTAssertEqual(err, noErr, @"Should execute table.close.window command");

    BOOL completed = [closeObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"table.close.window should complete within timeout");
}

#pragma mark - Tests

- (void)testActionUITableDialogOpensAndClosesCleanly {
    // Verifies the basic lifecycle: open → UUID captured → close → terminate script ran.
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Table"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Table.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openActionUITableDialogWithBundlePath:omcBundlePath];

    [self closeActionUITableDialogWithUUID:uuid bundlePath:omcBundlePath];

    NSString *termPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_term_%@", uuid];
    BOOL termFound = [self pollForFileAtPath:termPath timeout:5.0];
    XCTAssertTrue(termFound, @"Termination diagnostic file should be created on close");

    NSDictionary *diag = [self readDiagnosticFile:termPath];
    XCTAssertEqualObjects(diag[@"TERM_COMPLETE"], @"YES", @"Termination script should complete");
    XCTAssertEqualObjects(diag[@"OMC_ACTIONUI_WINDOW_UUID"], uuid, @"UUID in term file should match");

    [self cleanupTermDiagnosticForUUID:uuid];
}

- (void)testActionUITableInitControlOperations {
    // The init subcommand exercises:
    //   omc_table_set_columns "First Name" "Action"
    //   omc_table_set_column_widths 100 100
    //   omc_table_remove_all_rows
    //   omc_table_add_rows_from_stdin  (John/Enable, Jack/Disable, Jill/Hide)
    // If any of those operations crash, the window won't close cleanly
    // and the termination diagnostic file won't be written.
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Table"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Table.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openActionUITableDialogWithBundlePath:omcBundlePath];

    // Allow the init subcommand time to finish (it runs asynchronously after window opens)
    [NSThread sleepForTimeInterval:2.0];

    [self closeActionUITableDialogWithUUID:uuid bundlePath:omcBundlePath];

    NSString *termPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_term_%@", uuid];
    BOOL termFound = [self pollForFileAtPath:termPath timeout:5.0];
    XCTAssertTrue(termFound, @"Termination diagnostic file should be created");

    NSDictionary *diag = [self readDiagnosticFile:termPath];
    XCTAssertEqualObjects(diag[@"TERM_COMPLETE"], @"YES",
                          @"Termination script ran - all omc_table_* init operations did not crash");

    [self cleanupTermDiagnosticForUUID:uuid];
}

- (void)testActionUITableColumnValues {
    // Column indexing is 1-based:
    //   OMC_ACTIONUI_TABLE_1_COLUMN_0_VALUE  → whole selected row, tab-separated (empty if no selection)
    //   OMC_ACTIONUI_TABLE_1_COLUMN_1_VALUE  → first data column "First Name" (empty if no selection)
    //   OMC_ACTIONUI_TABLE_1_COLUMN_2_VALUE  → second data column "Action" (empty if no selection)
    //   OMC_ACTIONUI_TABLE_1_COLUMN_3_VALUE  → absent/empty (no third data column)
    //
    // The init script does not explicitly select a row, so all column values are empty strings.
    // This test verifies that TABLE env vars for all defined columns ARE exported (keys present in
    // the diagnostic file) and that column 3 (beyond the defined column count) is not exported.
    // Once omc_table_select_row support is added, the assertions can be tightened to check
    // for specific row values.
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Table"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Table.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openActionUITableDialogWithBundlePath:omcBundlePath];

    // Wait for init subcommand to finish populating rows
    [NSThread sleepForTimeInterval:2.0];

    [self closeActionUITableDialogWithUUID:uuid bundlePath:omcBundlePath];

    NSString *termPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_term_%@", uuid];
    BOOL termFound = [self pollForFileAtPath:termPath timeout:5.0];
    XCTAssertTrue(termFound, @"Termination diagnostic file should be created");

    NSDictionary *diag = [self readDiagnosticFile:termPath];

    // Column 0 (tab-joined whole row) env var must be present; value empty if no row selected
    XCTAssertNotNil(diag[@"TABLE_1_COLUMN_0_VALUE"],
                    @"OMC_ACTIONUI_TABLE_1_COLUMN_0_VALUE must be exported as an env var");

    // Column 1 (first data column, "First Name") env var must be present
    XCTAssertNotNil(diag[@"TABLE_1_COLUMN_1_VALUE"],
                    @"OMC_ACTIONUI_TABLE_1_COLUMN_1_VALUE must be exported as an env var");

    // Column 2 (second data column, "Action") env var must be present
    XCTAssertNotNil(diag[@"TABLE_1_COLUMN_2_VALUE"],
                    @"OMC_ACTIONUI_TABLE_1_COLUMN_2_VALUE must be exported as an env var");

    // If a row is selected, values must come from the rows inserted by init.
    // Column 1 holds "First Name"; column 2 holds "Action".
    NSString *col1 = diag[@"TABLE_1_COLUMN_1_VALUE"];
    NSString *col2 = diag[@"TABLE_1_COLUMN_2_VALUE"];
    if (col1.length > 0) {
        NSArray *expectedNames = @[@"John", @"Jack", @"Jill"];
        XCTAssertTrue([expectedNames containsObject:col1],
                      @"Column 1 (First Name) should be from populated rows, got: '%@'", col1);
    }
    if (col2.length > 0) {
        NSArray *expectedActions = @[@"Enable", @"Disable", @"Hide"];
        XCTAssertTrue([expectedActions containsObject:col2],
                      @"Column 2 (Action) should be from populated rows, got: '%@'", col2);
    }

    // Column 3 does not exist (only 2 data columns) — must be absent or empty
    NSString *col3 = diag[@"TABLE_1_COLUMN_3_VALUE"];
    XCTAssertTrue(col3.length == 0,
                  @"OMC_ACTIONUI_TABLE_1_COLUMN_3_VALUE must be empty (no third data column), got: '%@'", col3);

    [self cleanupTermDiagnosticForUUID:uuid];
}

- (void)testActionUITableAllRows {
    // OMC_ACTIONUI_TABLE_1_COLUMN_0_ALL_ROWS  → newline-joined tab-separated rows (whole rows)
    // OMC_ACTIONUI_TABLE_1_COLUMN_1_ALL_ROWS  → newline-joined values for the "First Name" column
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Table"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Table.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openActionUITableDialogWithBundlePath:omcBundlePath];

    [NSThread sleepForTimeInterval:2.0];

    [self closeActionUITableDialogWithUUID:uuid bundlePath:omcBundlePath];

    NSString *termPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_term_%@", uuid];
    BOOL termFound = [self pollForFileAtPath:termPath timeout:5.0];
    XCTAssertTrue(termFound, @"Termination diagnostic file should be created");

    NSDictionary *diag = [self readDiagnosticFile:termPath];

    // All rows for column 1 ("First Name") — should contain all three names
    NSString *allRows0 = diag[@"TABLE_1_COLUMN_1_ALL_ROWS"];
    XCTAssertTrue(allRows0.length > 0,
                  @"OMC_ACTIONUI_TABLE_1_COLUMN_1_ALL_ROWS should be non-empty (not yet implemented)");
    XCTAssertTrue([allRows0 containsString:@"John"],
                  @"All-rows column 0 should contain 'John'");
    XCTAssertTrue([allRows0 containsString:@"Jack"],
                  @"All-rows column 0 should contain 'Jack'");
    XCTAssertTrue([allRows0 containsString:@"Jill"],
                  @"All-rows column 0 should contain 'Jill'");

    // All rows for column 2 ("Action") — should contain all three actions
    NSString *allRows1 = diag[@"TABLE_1_COLUMN_2_ALL_ROWS"];
    XCTAssertTrue(allRows1.length > 0,
                  @"OMC_ACTIONUI_TABLE_1_COLUMN_2_ALL_ROWS should be non-empty (not yet implemented)");
    XCTAssertTrue([allRows1 containsString:@"Enable"],
                  @"All-rows column 1 should contain 'Enable'");
    XCTAssertTrue([allRows1 containsString:@"Disable"],
                  @"All-rows column 1 should contain 'Disable'");
    XCTAssertTrue([allRows1 containsString:@"Hide"],
                  @"All-rows column 1 should contain 'Hide'");

    [self cleanupTermDiagnosticForUUID:uuid];
}

@end

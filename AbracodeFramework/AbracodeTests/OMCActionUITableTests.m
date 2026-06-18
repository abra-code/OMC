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

// enable only in OMC version 5.0 or later
#if CURRENT_OMC_VERSION >= 50000

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
    NSString *readyPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_ready_%@", uuid];
    [fm removeItemAtPath:readyPath error:nil];
    [fm removeItemAtPath:[readyPath stringByAppendingString:@".tmp"] error:nil];
}

/// Opens the ActionUI Table dialog, waits for observer completion, returns captured UUID.
- (NSString *)openActionUITableDialogWithBundlePath:(NSString *)omcBundlePath {
    NSURL *homeURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"Table"
                                   forCommandFile:omcBundlePath
                                      withContext:homeURL
                                     useNavDialog:NO
                                         allowKeyWindowSubcommand:NO
                                         delegate:executionObserver];

    XCTAssertEqual(err, noErr, @"Should execute Table command");

    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Table command should complete within timeout");

    NSString *uuid = [executionObserver.capturedOutput
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    XCTAssertTrue(uuid.length > 0, @"Should capture window UUID from Table command stdout");
    return uuid;
}

/// Opens the dialog and waits for the init subcommand to finish populating rows. init writes a
/// readiness marker as its last step (after all its omc_dialog_control sends), so polling for it
/// — rather than sleeping a fixed interval — is robust to a window whose init is delayed because a
/// previous dialog is still tearing down. Returns the captured window UUID.
- (NSString *)openPopulatedTableDialogWithBundlePath:(NSString *)omcBundlePath {
    NSString *uuid = [self openActionUITableDialogWithBundlePath:omcBundlePath];
    NSString *readyPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_ready_%@", uuid];
    BOOL ready = [self pollForFileAtPath:readyPath timeout:10.0];
    XCTAssertTrue(ready, @"init subcommand should populate rows and signal readiness");
    return uuid;
}

/// Closes the ActionUI table dialog by sending table.close.window with the UUID as text context.
- (void)closeActionUITableDialogWithUUID:(NSString *)uuid bundlePath:(NSString *)omcBundlePath {
    OMCTestExecutionObserver *closeObserver = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"table.close.window"
                                   forCommandFile:omcBundlePath
                                      withContext:uuid
                                     useNavDialog:NO
                                         allowKeyWindowSubcommand:NO
                                         delegate:closeObserver];

    XCTAssertEqual(err, noErr, @"Should execute table.close.window command");

    BOOL completed = [closeObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"table.close.window should complete within timeout");
}

/// Runs a subcommand (by COMMAND_ID) against the running dialog, passing the window UUID
/// as text context — the same channel table.close.window uses to address the dialog by UUID.
- (void)runSubcommandID:(NSString *)commandID withUUID:(NSString *)uuid bundlePath:(NSString *)omcBundlePath {
    OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:commandID
                                   forCommandFile:omcBundlePath
                                      withContext:uuid
                                     useNavDialog:NO
                                         allowKeyWindowSubcommand:NO
                                         delegate:observer];

    XCTAssertEqual(err, noErr, @"Should execute %@ command", commandID);

    BOOL completed = [observer waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"%@ should complete within timeout", commandID);
}

/// Full programmatic-selection round trip: open the dialog, let the init subcommand populate
/// rows, run the given selection subcommand, close, and return the parsed termination diagnostic.
/// The selection verbs fire no actionID, so the only observable effect is the selected row
/// surfaced through OMC_ACTIONUI_TABLE_1_COLUMN_*_VALUE that the terminate script captures.
- (NSDictionary<NSString *, NSString *> *)diagnosticAfterSelectionSubcommand:(NSString *)selectionCommandID
                                                                 bundlePath:(NSString *)omcBundlePath
                                                                       uuid:(NSString **)outUUID {
    NSString *uuid = [self openPopulatedTableDialogWithBundlePath:omcBundlePath];
    if (outUUID != NULL) { *outUUID = uuid; }

    [self runSubcommandID:selectionCommandID withUUID:uuid bundlePath:omcBundlePath];

    // Give the dialog time to apply the (async, fire-and-forget) selection before terminating.
    // omc_dialog_control returns once the message is posted, not once it is processed, so this
    // settle window must comfortably cover the dialog's runloop turn even under full-suite load.
    [NSThread sleepForTimeInterval:2.0];

    [self closeActionUITableDialogWithUUID:uuid bundlePath:omcBundlePath];

    NSString *termPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_term_%@", uuid];
    BOOL termFound = [self pollForFileAtPath:termPath timeout:5.0];
    XCTAssertTrue(termFound, @"Termination diagnostic file should be created after %@", selectionCommandID);

    return [self readDiagnosticFile:termPath];
}

#pragma mark - Tests

- (void)testActionUITableDialogOpensAndClosesCleanly {
    // Verifies the basic lifecycle: open -> UUID captured -> close -> terminate script ran.
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
    // Waits for the init subcommand's readiness marker (it runs asynchronously after window opens).
    NSString *uuid = [self openPopulatedTableDialogWithBundlePath:omcBundlePath];

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
    //   OMC_ACTIONUI_TABLE_1_COLUMN_0_VALUE  -> whole selected row, tab-separated (empty if no selection)
    //   OMC_ACTIONUI_TABLE_1_COLUMN_1_VALUE  -> first data column "First Name" (empty if no selection)
    //   OMC_ACTIONUI_TABLE_1_COLUMN_2_VALUE  -> second data column "Action" (empty if no selection)
    //   OMC_ACTIONUI_TABLE_1_COLUMN_3_VALUE  -> absent/empty (no third data column)
    //
    // The init script does not explicitly select a row, so all column values are empty strings.
    // This test verifies that TABLE env vars for all defined columns ARE exported (keys present in
    // the diagnostic file) and that column 3 (beyond the defined column count) is not exported.
    // Specific selected-row values are asserted by the testActionUISelectRow* tests below, which
    // drive the omc_select_row / omc_select_row_with_content / omc_deselect verbs.
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Table"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Table.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openPopulatedTableDialogWithBundlePath:omcBundlePath];

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
    // OMC_ACTIONUI_TABLE_1_COLUMN_0_ALL_ROWS  -> newline-joined tab-separated rows (whole rows)
    // OMC_ACTIONUI_TABLE_1_COLUMN_1_ALL_ROWS  -> newline-joined values for the "First Name" column
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Table"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Table.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openPopulatedTableDialogWithBundlePath:omcBundlePath];

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

#pragma mark - Programmatic row selection

- (void)testActionUISelectRowByIndex {
    // table.select.row.index runs: omc_dialog_control <uuid> 1 omc_select_row 1
    // 0-based index 1 -> second populated row (Jack / Disable).
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Table"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Table.omc not found in test resources");
        return;
    }

    NSString *uuid = nil;
    NSDictionary *diag = [self diagnosticAfterSelectionSubcommand:@"table.select.row.index"
                                                       bundlePath:[bundleURL path]
                                                             uuid:&uuid];

    XCTAssertEqualObjects(diag[@"TABLE_1_COLUMN_1_VALUE"], @"Jack",
                          @"Selecting index 1 should put 'Jack' in column 1, got '%@'", diag[@"TABLE_1_COLUMN_1_VALUE"]);
    XCTAssertEqualObjects(diag[@"TABLE_1_COLUMN_2_VALUE"], @"Disable",
                          @"Selecting index 1 should put 'Disable' in column 2, got '%@'", diag[@"TABLE_1_COLUMN_2_VALUE"]);
    XCTAssertTrue([diag[@"TABLE_1_COLUMN_0_VALUE"] containsString:@"Jack"],
                  @"Whole-row column 0 should contain the selected row, got '%@'", diag[@"TABLE_1_COLUMN_0_VALUE"]);

    [self cleanupTermDiagnosticForUUID:uuid];
}

- (void)testActionUISelectRowByContentAnyColumn {
    // table.select.row.content runs: omc_select_row_with_content "Jill"
    // First row containing "Jill" in any column -> third row (Jill / Hide).
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Table"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Table.omc not found in test resources");
        return;
    }

    NSString *uuid = nil;
    NSDictionary *diag = [self diagnosticAfterSelectionSubcommand:@"table.select.row.content"
                                                       bundlePath:[bundleURL path]
                                                             uuid:&uuid];

    XCTAssertEqualObjects(diag[@"TABLE_1_COLUMN_1_VALUE"], @"Jill",
                          @"Matching 'Jill' should select the Jill row, got column 1 '%@'", diag[@"TABLE_1_COLUMN_1_VALUE"]);
    XCTAssertEqualObjects(diag[@"TABLE_1_COLUMN_2_VALUE"], @"Hide",
                          @"Jill's row column 2 should be 'Hide', got '%@'", diag[@"TABLE_1_COLUMN_2_VALUE"]);

    [self cleanupTermDiagnosticForUUID:uuid];
}

- (void)testActionUISelectRowByContentSpecificColumn {
    // table.select.row.content.column runs: omc_select_row_with_content "Hide" 2
    // Matches "Hide" only in column 2 (1-based) -> Jill / Hide; exercises the 1-based->0-based
    // column conversion in OMCActionUIWindowController.
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Table"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Table.omc not found in test resources");
        return;
    }

    NSString *uuid = nil;
    NSDictionary *diag = [self diagnosticAfterSelectionSubcommand:@"table.select.row.content.column"
                                                       bundlePath:[bundleURL path]
                                                             uuid:&uuid];

    XCTAssertEqualObjects(diag[@"TABLE_1_COLUMN_1_VALUE"], @"Jill",
                          @"Matching 'Hide' in column 2 should select the Jill row, got column 1 '%@'", diag[@"TABLE_1_COLUMN_1_VALUE"]);
    XCTAssertEqualObjects(diag[@"TABLE_1_COLUMN_2_VALUE"], @"Hide",
                          @"Selected row column 2 should be 'Hide', got '%@'", diag[@"TABLE_1_COLUMN_2_VALUE"]);

    [self cleanupTermDiagnosticForUUID:uuid];
}

- (void)testActionUIDeselectRow {
    // table.deselect runs: omc_select_row 1 then omc_deselect — the selection must end empty.
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Table"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Table.omc not found in test resources");
        return;
    }

    NSString *uuid = nil;
    NSDictionary<NSString *, NSString *> *diag = [self diagnosticAfterSelectionSubcommand:@"table.deselect"
                                                       bundlePath:[bundleURL path]
                                                             uuid:&uuid];

    XCTAssertEqual(diag[@"TABLE_1_COLUMN_1_VALUE"].length, (NSUInteger)0,
                   @"After deselect, column 1 should be empty, got '%@'", diag[@"TABLE_1_COLUMN_1_VALUE"]);
    XCTAssertEqual(diag[@"TABLE_1_COLUMN_2_VALUE"].length, (NSUInteger)0,
                   @"After deselect, column 2 should be empty, got '%@'", diag[@"TABLE_1_COLUMN_2_VALUE"]);
    XCTAssertEqual(diag[@"TABLE_1_COLUMN_0_VALUE"].length, (NSUInteger)0,
                   @"After deselect, whole-row column 0 should be empty, got '%@'", diag[@"TABLE_1_COLUMN_0_VALUE"]);

    [self cleanupTermDiagnosticForUUID:uuid];
}

@end

#endif // CURRENT_OMC_VERSION >= 50000

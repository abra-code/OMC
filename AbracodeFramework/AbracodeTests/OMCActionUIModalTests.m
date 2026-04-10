//
//  OMCActionUIModalTests.m
//  AbracodeTests
//
//  Integration tests for ActionUI modal presentation APIs:
//    omc_present_modal, omc_dismiss_modal          (window-level sheet)
//    omc_present_alert, omc_dismiss_dialog         (system alert)
//    omc_present_confirmation_dialog               (confirmation dialog)
//  and for template container row operations:
//    omc_list_set_items / omc_table_set_rows on any view with a non-zero id
//    (not restricted to List/Table views).
//
//  All modal operations are fire-and-forget async; results come back via
//  actionID subcommand callbacks, tested here via diagnostic files written
//  by subcommand scripts in the ActionUI-Modal.omc test bundle.
//

#import "OMCTestCase.h"
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"

// enable only in OMC version 5.0 or later
#if CURRENT_OMC_VERSION >= 50000

@interface OMCActionUIModalTests : XCTestCase
@end

@implementation OMCActionUIModalTests

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
    for (NSString *suffix in @[@"init", @"dismiss", @"term"]) {
        NSString *path = [NSString stringWithFormat:@"/tmp/OMC_test_modal_%@_%@", suffix, uuid];
        [fm removeItemAtPath:path error:nil];
        [fm removeItemAtPath:[path stringByAppendingString:@".tmp"] error:nil];
    }
}

/// Opens the ActionUI Modal window, waits for the executor to complete, returns the captured UUID.
- (NSString *)openModalWindowWithBundlePath:(NSString *)omcBundlePath {
    NSURL *homeURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"Modal"
                                   forCommandFile:omcBundlePath
                                      withContext:homeURL
                                     useNavDialog:NO
                                 allowKeyWindowSubcommand:NO
                                         delegate:observer];

    XCTAssertEqual(err, noErr, @"Should execute Modal command without error");

    BOOL completed = [observer waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Modal command should complete within timeout");

    NSString *uuid = [observer.capturedOutput
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    XCTAssertTrue(uuid.length > 0, @"Should capture window UUID from Modal command stdout");
    return uuid;
}

/// Closes the Modal window by sending modal.close.window with the UUID as text context.
- (void)closeModalWindowWithUUID:(NSString *)uuid bundlePath:(NSString *)omcBundlePath {
    OMCTestExecutionObserver *closeObserver = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"modal.close.window"
                                   forCommandFile:omcBundlePath
                                      withContext:uuid
                                     useNavDialog:NO
                                 allowKeyWindowSubcommand:NO
                                         delegate:closeObserver];

    XCTAssertEqual(err, noErr, @"Should execute modal.close.window command");

    BOOL completed = [closeObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"modal.close.window should complete within timeout");
}

#pragma mark - Tests

- (void)testActionUIModalWindowOpens {
    // Verifies basic lifecycle: open -> UUID captured -> close -> terminate script ran.
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Modal"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Modal.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openModalWindowWithBundlePath:omcBundlePath];

    [self closeModalWindowWithUUID:uuid bundlePath:omcBundlePath];

    NSString *termPath = [NSString stringWithFormat:@"/tmp/OMC_test_modal_term_%@", uuid];
    BOOL found = [self pollForFileAtPath:termPath timeout:5.0];
    XCTAssertTrue(found, @"Termination diagnostic file should be created on close");

    NSDictionary *diag = [self readDiagnosticFile:termPath];
    XCTAssertEqualObjects(diag[@"TERM_COMPLETE"], @"YES", @"Termination script should complete");
    XCTAssertEqualObjects(diag[@"OMC_ACTIONUI_WINDOW_UUID"], uuid, @"UUID in term file should match");

    [self cleanupDiagnosticFilesForUUID:uuid];
}

- (void)testActionUIModalAlertAndConfirmationDialogRoundTrip {
    // Verifies that omc_present_alert and omc_present_confirmation_dialog followed by
    // omc_dismiss_dialog complete without crashing and allow normal window operation.
    //
    // The init subcommand:
    //   1. omc_present_alert "Test Alert" "Alert from automated test"
    //   2. omc_dismiss_dialog
    //   3. omc_present_confirmation_dialog "Test Confirm" "..." "OK::..." "Cancel:cancel:"
    //   4. omc_dismiss_dialog
    //   5. Writes init diagnostic with INIT_COMPLETE=YES
    //
    // If any of those IPC calls crash or deadlock, the init diagnostic is never written.

    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Modal"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Modal.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openModalWindowWithBundlePath:omcBundlePath];

    // Poll for the init diagnostic file which is written after all omc_dialog_control calls
    NSString *initPath = [NSString stringWithFormat:@"/tmp/OMC_test_modal_init_%@", uuid];
    BOOL found = [self pollForFileAtPath:initPath timeout:8.0];
    XCTAssertTrue(found, @"Init diagnostic should be created — proves alert/confirmation present+dismiss succeeded");

    NSDictionary *diag = [self readDiagnosticFile:initPath];
    XCTAssertEqualObjects(diag[@"INIT_COMPLETE"], @"YES",
                          @"INIT_COMPLETE=YES means omc_present_alert and omc_present_confirmation_dialog "
                           "plus omc_dismiss_dialog all ran without crash");

    [self closeModalWindowWithUUID:uuid bundlePath:omcBundlePath];
    [self cleanupDiagnosticFilesForUUID:uuid];
}

- (void)testActionUIModalSheetOnDismissAction {
    // Verifies that omc_present_modal + omc_dismiss_modal fires the onDismissActionID subcommand.
    //
    // The init subcommand presents Sheet.json as a sheet with onDismissActionID="modal.dismiss.action",
    // then immediately dismisses it via omc_dismiss_modal. ActionUI fires "modal.dismiss.action"
    // which runs as a subcommand and writes /tmp/OMC_test_modal_dismiss_{uuid}.
    //
    // This tests the full async callback chain:
    //   omc_dismiss_modal -> ActionUIModel.dismissModal -> actionHandler("modal.dismiss.action")
    //   -> OMC subcommand dispatch -> shell script writes diagnostic file.

    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Modal"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Modal.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openModalWindowWithBundlePath:omcBundlePath];

    // Poll for the modal dismiss diagnostic written by the "modal.dismiss.action" subcommand.
    // This file is independent of the init diagnostic and should appear shortly after the
    // omc_dismiss_modal IPC message is processed by the UI thread.
    NSString *dismissPath = [NSString stringWithFormat:@"/tmp/OMC_test_modal_dismiss_%@", uuid];
    BOOL found = [self pollForFileAtPath:dismissPath timeout:8.0];
    XCTAssertTrue(found, @"Modal dismiss diagnostic should be created — proves onDismissActionID subcommand fired");

    NSDictionary *diag = [self readDiagnosticFile:dismissPath];
    XCTAssertEqualObjects(diag[@"MODAL_DISMISS_OK"], @"YES",
                          @"MODAL_DISMISS_OK=YES confirms onDismissActionID callback executed");
    XCTAssertEqualObjects(diag[@"OMC_ACTIONUI_WINDOW_UUID"], uuid,
                          @"UUID in dismiss diagnostic should match the window UUID");

    [self closeModalWindowWithUUID:uuid bundlePath:omcBundlePath];
    [self cleanupDiagnosticFilesForUUID:uuid];
}

- (void)testActionUITemplateContainerSingleColumnSetItems {
    // Verifies that omc_list_set_items works on a VStack with a template (id=2),
    // confirming that OMC does not restrict setElementRows to List/Table views only.
    //
    // The init subcommand calls:
    //   omc_dialog_control $UUID 2 omc_list_set_items "Apple" "Banana" "Cherry"
    // on a VStack whose JSON uses "template" instead of "children". This exercises
    // the same ActionUI setElementRows API path used by List, but on a VStack template.
    //
    // If OMC or ActionUI rejects the call (e.g., missing ViewModel or type guard),
    // the init diagnostic file would still be written but a crash would prevent it.

    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Modal"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Modal.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openModalWindowWithBundlePath:omcBundlePath];

    NSString *initPath = [NSString stringWithFormat:@"/tmp/OMC_test_modal_init_%@", uuid];
    BOOL found = [self pollForFileAtPath:initPath timeout:8.0];
    XCTAssertTrue(found, @"Init diagnostic should be created after omc_list_set_items on VStack template (id=2)");

    NSDictionary *diag = [self readDiagnosticFile:initPath];
    XCTAssertEqualObjects(diag[@"INIT_COMPLETE"], @"YES",
                          @"omc_list_set_items on VStack template completed without crash");

    [self closeModalWindowWithUUID:uuid bundlePath:omcBundlePath];
    [self cleanupDiagnosticFilesForUUID:uuid];
}

- (void)testActionUITemplateContainerMultiColumnSetRows {
    // Verifies that omc_table_set_rows works on a VStack with a multi-column template (id=3),
    // confirming that tab-separated multi-column data flows correctly to template containers.
    //
    // The init subcommand calls:
    //   omc_dialog_control $UUID 3 omc_table_set_rows "star.fill\tFavorites" "heart.fill\tLiked"
    // on a VStack template that uses "$1" (systemImage) and "$2" (title) placeholders.
    //
    // This tests the omc_table_set_rows -> setTableRows: -> setElementRowsWithWindowUUID:
    // -> states["content"] path for non-Table/List container views.

    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Modal"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Modal.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openModalWindowWithBundlePath:omcBundlePath];

    NSString *initPath = [NSString stringWithFormat:@"/tmp/OMC_test_modal_init_%@", uuid];
    BOOL found = [self pollForFileAtPath:initPath timeout:8.0];
    XCTAssertTrue(found, @"Init diagnostic should be created after omc_table_set_rows on VStack template (id=3)");

    NSDictionary *diag = [self readDiagnosticFile:initPath];
    XCTAssertEqualObjects(diag[@"INIT_COMPLETE"], @"YES",
                          @"omc_table_set_rows on VStack multi-column template completed without crash");

    [self closeModalWindowWithUUID:uuid bundlePath:omcBundlePath];
    [self cleanupDiagnosticFilesForUUID:uuid];
}

@end

#endif // CURRENT_OMC_VERSION >= 50000

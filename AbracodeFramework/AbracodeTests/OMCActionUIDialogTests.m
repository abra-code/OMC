//
//  OMCActionUIDialogTests.m
//  AbracodeTests
//
//  Integration tests for ActionUI dialog controller (setControlValues: code paths)
//

#import <AppKit/AppKit.h>
#import "OMCTestCase.h"
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"

// enable only in OMC version 5.0 or later
#if CURRENT_OMC_VERSION >= 50000

@interface OMCActionUIDialogTests : XCTestCase
@end

@implementation OMCActionUIDialogTests

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

/// Opens the ActionUI Form dialog, waits for observer completion, returns captured UUID
- (NSString *)openActionUIDialogWithBundlePath:(NSString *)omcBundlePath {
    NSURL *homeURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    OMCTestExecutionObserver *executionObserver = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"Form"
                                   forCommandFile:omcBundlePath
                                      withContext:homeURL
                                     useNavDialog:NO
                                         allowKeyWindowSubcommand:NO
                                         delegate:executionObserver];

    XCTAssertEqual(err, noErr, @"Should execute Form command");

    BOOL completed = [executionObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"Form should complete within timeout");

    NSString *firstLine = [executionObserver waitForFirstOutputLineWithTimeout:kDefaultExecutionTimeout];
    NSString *uuid = [firstLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] ?: @"";
    XCTAssertTrue(uuid.length > 0, @"Should capture window UUID");
    return uuid;
}

/// Closes the ActionUI dialog by sending form.close.window with the UUID as text context
- (void)closeActionUIDialogWithUUID:(NSString *)uuid bundlePath:(NSString *)omcBundlePath {
    OMCTestExecutionObserver *closeObserver = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"form.close.window"
                                   forCommandFile:omcBundlePath
                                      withContext:uuid
                                     useNavDialog:NO
                                         allowKeyWindowSubcommand:NO
                                         delegate:closeObserver];

    XCTAssertEqual(err, noErr, @"Should execute form.close.window command");

    BOOL completed = [closeObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"form.close.window should complete within timeout");
}

#pragma mark - Tests

- (void)testActionUIDialogInitialization {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openActionUIDialogWithBundlePath:omcBundlePath];

    // Poll for the diagnostic file written by the init script
    NSString *initPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_init_%@", uuid];
    BOOL found = [self pollForFileAtPath:initPath timeout:5.0];
    XCTAssertTrue(found, @"Init diagnostic file should be created");

    NSDictionary *diag = [self readDiagnosticFile:initPath];
    XCTAssertEqualObjects(diag[@"INIT_COMPLETE"], @"YES", @"Init script should complete");
    XCTAssertEqualObjects(diag[@"OMC_ACTIONUI_WINDOW_UUID"], uuid, @"UUID should match");
    XCTAssertTrue([diag[@"OMC_OBJ_PATH"] length] > 0, @"OMC_OBJ_PATH should be non-empty");
    XCTAssertTrue([diag[@"OMC_OMC_SUPPORT_PATH"] containsString:@"Support"],
                  @"OMC_OMC_SUPPORT_PATH should contain 'Support'");

    [self closeActionUIDialogWithUUID:uuid bundlePath:omcBundlePath];
    [self cleanupDiagnosticFilesForUUID:uuid prefix:@"actionui"];
}

- (void)testActionUIDialogTermination {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openActionUIDialogWithBundlePath:omcBundlePath];

    // Wait for init to complete first
    NSString *initPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_init_%@", uuid];
    BOOL initFound = [self pollForFileAtPath:initPath timeout:5.0];
    XCTAssertTrue(initFound, @"Init diagnostic file should be created");

    // Close the dialog (triggers terminate cancel subcommand)
    [self closeActionUIDialogWithUUID:uuid bundlePath:omcBundlePath];

    // Poll for the termination diagnostic file
    NSString *termPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_term_%@", uuid];
    BOOL termFound = [self pollForFileAtPath:termPath timeout:5.0];
    XCTAssertTrue(termFound, @"Termination diagnostic file should be created");

    NSDictionary *diag = [self readDiagnosticFile:termPath];
    XCTAssertEqualObjects(diag[@"TERM_COMPLETE"], @"YES", @"Termination script should complete");
    XCTAssertEqualObjects(diag[@"OMC_ACTIONUI_WINDOW_UUID"], uuid, @"UUID should match");

    // Verify control value round-trip: init set control 2 to "Papa Smurf"
    XCTAssertEqualObjects(diag[@"VIEW_2_VALUE"], @"Papa Smurf",
                          @"Control 2 value should round-trip through init to termination");

    [self cleanupDiagnosticFilesForUUID:uuid prefix:@"actionui"];
}

- (void)testActionUIDialogSetControlValue {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openActionUIDialogWithBundlePath:omcBundlePath];

    // The init script exercises omc_dialog_control calls:
    // - set control value: "$dialog_tool" UUID 2 "Papa Smurf"
    //   (exercises setControlStringValue:forControlID: in OMCActionUIControls.cpp)
    // - enable, show, select calls exercise base class setControlValues: code paths
    // If any call crashes, the diagnostic file won't be written
    NSString *initPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_init_%@", uuid];
    BOOL found = [self pollForFileAtPath:initPath timeout:5.0];
    XCTAssertTrue(found, @"Init diagnostic file should be created - proves all omc_dialog_control calls succeeded");

    NSDictionary *diag = [self readDiagnosticFile:initPath];
    XCTAssertEqualObjects(diag[@"INIT_COMPLETE"], @"YES",
                          @"All omc_dialog_control calls completed without errors");

    [self closeActionUIDialogWithUUID:uuid bundlePath:omcBundlePath];
    [self cleanupDiagnosticFilesForUUID:uuid prefix:@"actionui"];
}

- (void)testActionUIDialogInvokeCloseOnWindow {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openActionUIDialogWithBundlePath:omcBundlePath];

    // Wait for init to complete first
    NSString *initPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_init_%@", uuid];
    BOOL initFound = [self pollForFileAtPath:initPath timeout:5.0];
    XCTAssertTrue(initFound, @"Init diagnostic file should be created");

    // Close the window via INVOKE (omc_invoke close) instead of omc_terminate_cancel
    // This exercises the INVOKE code path with omc_window target in setControlValues:
    OMCTestExecutionObserver *invokeObserver = OMCTestExecutionObserver.new;

    OSStatus err = [OMCCommandExecutor runCommand:@"form.invoke.close"
                                   forCommandFile:omcBundlePath
                                      withContext:uuid
                                     useNavDialog:NO
                                         allowKeyWindowSubcommand:NO
                                         delegate:invokeObserver];

    XCTAssertEqual(err, noErr, @"Should execute form.invoke.close command");

    BOOL completed = [invokeObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"form.invoke.close should complete within timeout");

    // The INVOKE close triggers windowWillClose: -> terminate -> END_CANCEL_SUBCOMMAND_ID
    // which writes the termination diagnostic file
    NSString *termPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_term_%@", uuid];
    BOOL termFound = [self pollForFileAtPath:termPath timeout:5.0];
    XCTAssertTrue(termFound, @"INVOKE close should trigger terminate cancel subcommand");

    NSDictionary *diag = [self readDiagnosticFile:termPath];
    XCTAssertEqualObjects(diag[@"TERM_COMPLETE"], @"YES",
                          @"Terminate script should complete after INVOKE close");

    [self cleanupDiagnosticFilesForUUID:uuid prefix:@"actionui"];
}

/// A regular non-blocking ActionUI window must be minimizable: NSWindow disables the yellow
/// button and Window > Minimize (performMiniaturize:) for a window without the miniaturizable bit.
- (void)testActionUIRegularWindowIsMiniaturizable {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openActionUIDialogWithBundlePath:omcBundlePath];

    NSString *initPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_init_%@", uuid];
    BOOL initFound = [self pollForFileAtPath:initPath timeout:5.0];
    XCTAssertTrue(initFound, @"Init diagnostic file should be created");

    // The window controller names the frame autosave "OMC.<JSON_NAME>".
    NSWindow *formWindow = nil;
    for (NSWindow *window in [NSApp windows]) {
        if (window.isVisible && [window.frameAutosaveName isEqualToString:@"OMC.Form"]) {
            formWindow = window;
            break;
        }
    }
    XCTAssertNotNil(formWindow, @"The Form window should be open");
    XCTAssertTrue((formWindow.styleMask & NSWindowStyleMaskMiniaturizable) != 0,
                  @"A regular non-blocking window should have the miniaturizable style bit");

    NSMenuItem *minimizeItem = [[NSMenuItem alloc] initWithTitle:@"Minimize"
                                                          action:@selector(performMiniaturize:)
                                                   keyEquivalent:@"m"];
    XCTAssertTrue([formWindow validateMenuItem:minimizeItem],
                  @"Window > Minimize should be enabled for a regular non-blocking window");

    [self closeActionUIDialogWithUUID:uuid bundlePath:omcBundlePath];
    [self cleanupDiagnosticFilesForUUID:uuid prefix:@"actionui"];
}

#pragma mark - INVOKE with structure arguments

/// The open Form window (the window controller names the frame autosave "OMC.<JSON_NAME>").
- (NSWindow *)visibleFormWindow {
    for (NSWindow *window in [NSApp windows]) {
        if (window.isVisible && [window.frameAutosaveName isEqualToString:@"OMC.Form"])
            return window;
    }
    return nil;
}

/// Runs one of the form.invoke.* commands against the open Form window, then spins the run loop
/// until the condition holds (the INVOKE arrives through the dialog's message port) or 5 seconds pass.
- (BOOL)runInvokeCommand:(NSString *)commandID uuid:(NSString *)uuid bundlePath:(NSString *)omcBundlePath
               condition:(BOOL (^)(void))condition {
    OMCTestExecutionObserver *invokeObserver = OMCTestExecutionObserver.new;
    OSStatus err = [OMCCommandExecutor runCommand:commandID
                                   forCommandFile:omcBundlePath
                                      withContext:uuid
                                     useNavDialog:NO
                                         allowKeyWindowSubcommand:NO
                                         delegate:invokeObserver];
    XCTAssertEqual(err, noErr, @"Should execute %@", commandID);
    BOOL completed = [invokeObserver waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(completed, @"%@ should complete within timeout", commandID);

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return condition();
}

static BOOL OMCNearlyEqual(CGFloat a, CGFloat b) {
    return fabs(a - b) < 0.5;
}

/// On 64-bit macOS NSRect, NSPoint and NSSize encode as CGRect, CGPoint and CGSize. INVOKE used to look
/// only for the _NSRect-style names, so these messages were refused as "unsupported structure".
- (void)testActionUIInvokeWithGeometryStructureArguments {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }

    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openActionUIDialogWithBundlePath:omcBundlePath];

    NSString *initPath = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_init_%@", uuid];
    BOOL initFound = [self pollForFileAtPath:initPath timeout:5.0];
    XCTAssertTrue(initFound, @"Init diagnostic file should be created");

    NSWindow *formWindow = [self visibleFormWindow];
    XCTAssertNotNil(formWindow, @"The Form window should be open");

    // setFrame: 120,140,560,420 display: YES - a CGRect (four numbers) and a BOOL
    BOOL frameSet = [self runInvokeCommand:@"form.invoke.setframe" uuid:uuid bundlePath:omcBundlePath condition:^BOOL{
        NSRect frame = formWindow.frame;
        return OMCNearlyEqual(frame.origin.x, 120) && OMCNearlyEqual(frame.origin.y, 140) &&
               OMCNearlyEqual(frame.size.width, 560) && OMCNearlyEqual(frame.size.height, 420);
    }];
    XCTAssertTrue(frameSet, @"setFrame:display: should set the frame to {120,140,560,420}, got %@",
                  NSStringFromRect(formWindow.frame));

    // setFrameOrigin: 160,180 - a CGPoint; the size stays
    BOOL originSet = [self runInvokeCommand:@"form.invoke.setframeorigin" uuid:uuid bundlePath:omcBundlePath condition:^BOOL{
        NSRect frame = formWindow.frame;
        return OMCNearlyEqual(frame.origin.x, 160) && OMCNearlyEqual(frame.origin.y, 180);
    }];
    XCTAssertTrue(originSet, @"setFrameOrigin: should move the window to {160,180}, got %@",
                  NSStringFromRect(formWindow.frame));
    XCTAssertTrue(OMCNearlyEqual(formWindow.frame.size.width, 560) && OMCNearlyEqual(formWindow.frame.size.height, 420),
                  @"setFrameOrigin: should keep the size, got %@", NSStringFromRect(formWindow.frame));

    // setContentSize: 540,380 - a CGSize
    BOOL sizeSet = [self runInvokeCommand:@"form.invoke.setcontentsize" uuid:uuid bundlePath:omcBundlePath condition:^BOOL{
        NSRect content = [formWindow contentRectForFrameRect:formWindow.frame];
        return OMCNearlyEqual(content.size.width, 540) && OMCNearlyEqual(content.size.height, 380);
    }];
    XCTAssertTrue(sizeSet, @"setContentSize: should set the content size to {540,380}, got %@",
                  NSStringFromRect([formWindow contentRectForFrameRect:formWindow.frame]));

    [self closeActionUIDialogWithUUID:uuid bundlePath:omcBundlePath];
    [self cleanupDiagnosticFilesForUUID:uuid prefix:@"actionui"];
}

@end

#endif // CURRENT_OMC_VERSION >= 50000

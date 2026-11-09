//
//  OMCActionUIWindowTests.m
//  AbracodeTests
//
//  Pin tests for the window an ActionUI command opens (OMCActionUIWindowController.mm), before its
//  logic moves to C++ (Phase 5 step 8, Private/phase5-step8a-pin-test-gaps.md, gaps 6 and 7): where
//  the title comes from, the size limits taken from the content, a fixed-size window, a floating
//  panel, and the frame: centered the first time, restored from its autosave name after that.
//
//  The fixture is TestBundles/ActionUI-Window.omc. Each window is found by its frame autosave name,
//  "OMC.<JSON_NAME>". The window opened on a file (title from the file) is not tested here: in an
//  XCTest run the engine would add that file to the user's real recent documents.
//
//  Nor is the maximum size: the controller sets contentMaxSize from the content's maximum
//  (omcApplyContentSizeLimits), but once the window is open contentMaxSize reads infinite, for the
//  fixed-size window too - most likely AppKit taking the limits from the hosting view's layout
//  constraints instead. That is AppKit's behavior, not the controller's, so it is not pinned.
//

#import <AppKit/AppKit.h>
#import "OMCTestCase.h"
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"

#if CURRENT_OMC_VERSION >= 50000

static NSString * const kFixedAutosaveName = @"OMC.WindowFixed";
static NSString * const kFlexibleAutosaveName = @"OMC.WindowFlexible";
static NSString * const kFloatingAutosaveName = @"OMC.WindowFloating";

static BOOL OMCWindowNearlyEqual(CGFloat a, CGFloat b) {
    return fabs(a - b) < 0.5;
}

@interface OMCActionUIWindowTests : XCTestCase
@property (nonatomic, copy) NSString *bundlePath;
@end

@implementation OMCActionUIWindowTests

#pragma mark - Helpers

// The key under which NSWindow keeps a frame autosaved under `name`
static NSString *FrameDefaultsKey(NSString *name) {
    return [@"NSWindow Frame " stringByAppendingString:name];
}

- (void)removeSavedFrames {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *name in @[kFixedAutosaveName, kFlexibleAutosaveName, kFloatingAutosaveName])
        [defaults removeObjectForKey:FrameDefaultsKey(name)];
}

- (void)setUp {
    [super setUp];
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Window"];
    XCTAssertNotNil(bundleURL, @"ActionUI-Window.omc should be in the test resources");
    self.bundlePath = [bundleURL path];
    [self removeSavedFrames];
}

- (void)tearDown {
    [self removeSavedFrames];
    [super tearDown];
}

- (void)spinUntil:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

- (NSWindow *)visibleWindowNamed:(NSString *)autosaveName {
    for (NSWindow *window in [NSApp windows]) {
        if (window.isVisible && [window.frameAutosaveName isEqualToString:autosaveName])
            return window;
    }
    return nil;
}

// Runs a command of the fixture; its first output line is its window's UUID when it opens one
- (NSString *)runCommand:(NSString *)nameOrID context:(id)context {
    OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;
    OSStatus err = [OMCCommandExecutor runCommand:nameOrID
                                   forCommandFile:self.bundlePath
                                      withContext:context
                                     useNavDialog:NO
                                         allowKeyWindowSubcommand:NO
                                         delegate:observer];
    XCTAssertEqual(err, noErr, @"Should execute %@", nameOrID);
    XCTAssertTrue([observer waitForCompletionWithTimeout:kDefaultExecutionTimeout], @"%@ should complete", nameOrID);
    NSString *firstLine = [observer waitForFirstOutputLineWithTimeout:1.0];
    return [firstLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

// Opens the window of a fixture command and returns it, found by its autosave name
- (NSWindow *)openWindowWithCommand:(NSString *)name autosaveName:(NSString *)autosaveName uuid:(NSString **)outUUID {
    NSString *uuid = [self runCommand:name context:nil];
    XCTAssertTrue(uuid.length > 0, @"%@ should print its window's UUID", name);
    __block NSWindow *window = nil;
    [self spinUntil:^BOOL{ window = [self visibleWindowNamed:autosaveName]; return window != nil; } timeout:5.0];
    XCTAssertNotNil(window, @"%@ should open its window", name);
    if (outUUID != NULL)
        *outUUID = uuid;
    return window;
}

- (void)closeWindowWithUUID:(NSString *)uuid autosaveName:(NSString *)autosaveName {
    (void)[self runCommand:@"window.close" context:uuid];
    [self spinUntil:^BOOL{ return [self visibleWindowNamed:autosaveName] == nil; } timeout:5.0];
    XCTAssertNil([self visibleWindowNamed:autosaveName], @"the window should close");
}

// The part of the content view under the titlebar: the content view spans the full window height
// (NSWindowStyleMaskFullSizeContentView), the layout area does not
static CGFloat TitlebarHeight(NSWindow *window) {
    return NSHeight(window.contentView.frame) - NSHeight(window.contentLayoutRect);
}

#pragma mark - Title

- (void)testWindowTitleComesFromWINDOW_TITLE {
    NSString *uuid = nil;
    NSWindow *window = [self openWindowWithCommand:@"Window With A Title" autosaveName:kFixedAutosaveName uuid:&uuid];
    XCTAssertEqualObjects(window.title, @"A Title Of Its Own");
    [self closeWindowWithUUID:uuid autosaveName:kFixedAutosaveName];
}

- (void)testWindowTitleIsTheCommandNameWithoutWINDOW_TITLE {
    NSString *uuid = nil;
    NSWindow *window = [self openWindowWithCommand:@"Named By Its Command" autosaveName:kFlexibleAutosaveName uuid:&uuid];
    XCTAssertEqualObjects(window.title, @"Named By Its Command");
    XCTAssertNil(window.representedURL, @"a window opened on no file represents none");
    [self closeWindowWithUUID:uuid autosaveName:kFlexibleAutosaveName];
}

- (void)testOmcDialogControlSetsTheWindowTitle {
    NSString *uuid = nil;
    NSWindow *window = [self openWindowWithCommand:@"Window With A Title" autosaveName:kFixedAutosaveName uuid:&uuid];
    (void)[self runCommand:@"window.retitle" context:uuid];
    // omc_dialog_control's message arrives through the dialog's port
    [self spinUntil:^BOOL{ return [window.title isEqualToString:@"Retitled By A Handler"]; } timeout:5.0];
    XCTAssertEqualObjects(window.title, @"Retitled By A Handler",
                          @"omc_dialog_control <window> omc_window <text> sets the title");
    [self closeWindowWithUUID:uuid autosaveName:kFixedAutosaveName];
}

#pragma mark - Size

- (void)testFixedSizeContentMakesAFixedSizeWindow {
    NSString *uuid = nil;
    NSWindow *window = [self openWindowWithCommand:@"Window With A Title" autosaveName:kFixedAutosaveName uuid:&uuid];
    CGFloat titlebar = TitlebarHeight(window);
    XCTAssertTrue((window.styleMask & NSWindowStyleMaskResizable) == 0,
                  @"a root with an exact width and height gives a window the user cannot resize");
    XCTAssertTrue(OMCWindowNearlyEqual(window.contentMinSize.width, 320.0), @"min width %g", window.contentMinSize.width);
    XCTAssertTrue(OMCWindowNearlyEqual(window.contentMinSize.height, 180.0 + titlebar),
                  @"min height %g is the content's 180 plus the titlebar's %g", window.contentMinSize.height, titlebar);
    XCTAssertTrue(OMCWindowNearlyEqual(NSWidth(window.contentLayoutRect), 320.0), @"layout width %g", NSWidth(window.contentLayoutRect));
    XCTAssertTrue(OMCWindowNearlyEqual(NSHeight(window.contentLayoutRect), 180.0), @"layout height %g", NSHeight(window.contentLayoutRect));
    [self closeWindowWithUUID:uuid autosaveName:kFixedAutosaveName];
}

- (void)testFlexibleContentSetsTheWindowSizeLimits {
    NSString *uuid = nil;
    NSWindow *window = [self openWindowWithCommand:@"Named By Its Command" autosaveName:kFlexibleAutosaveName uuid:&uuid];
    CGFloat titlebar = TitlebarHeight(window);
    XCTAssertTrue((window.styleMask & NSWindowStyleMaskResizable) != 0, @"flexible content gives a resizable window");
    XCTAssertTrue((window.styleMask & NSWindowStyleMaskMiniaturizable) != 0, @"a regular non-blocking window minimizes");
    XCTAssertTrue((window.styleMask & NSWindowStyleMaskFullSizeContentView) != 0, @"the content view spans the titlebar");
    XCTAssertTrue(OMCWindowNearlyEqual(window.contentMinSize.width, 300.0), @"min width %g", window.contentMinSize.width);
    XCTAssertTrue(OMCWindowNearlyEqual(window.contentMinSize.height, 150.0 + titlebar),
                  @"min height %g is the content's 150 plus the titlebar's %g", window.contentMinSize.height, titlebar);
    [self closeWindowWithUUID:uuid autosaveName:kFlexibleAutosaveName];
}

- (void)testFloatingWindowTypeIsAFloatingPanel {
    NSString *uuid = nil;
    NSWindow *window = [self openWindowWithCommand:@"Window Floating" autosaveName:kFloatingAutosaveName uuid:&uuid];
    XCTAssertTrue([window isKindOfClass:[NSPanel class]], @"WINDOW_TYPE floating opens a panel");
    XCTAssertTrue([(NSPanel *)window isFloatingPanel]);
    XCTAssertEqual(window.level, NSFloatingWindowLevel);
    XCTAssertTrue((window.styleMask & NSWindowStyleMaskUtilityWindow) != 0, @"a utility window");
    XCTAssertTrue((window.styleMask & NSWindowStyleMaskMiniaturizable) == 0, @"panels do not minimize");
    [self closeWindowWithUUID:uuid autosaveName:kFloatingAutosaveName];
}

#pragma mark - Frame

- (void)testFirstOpenIsCenteredAndASavedFrameIsRestored {
    NSString *uuid = nil;
    NSWindow *window = [self openWindowWithCommand:@"Named By Its Command" autosaveName:kFlexibleAutosaveName uuid:&uuid];
    NSRect opened = window.frame;
    [window center];
    XCTAssertTrue(NSEqualRects(opened, window.frame), @"with no saved frame the window opens centered: %@ then %@",
                  NSStringFromRect(opened), NSStringFromRect(window.frame));

    NSRect moved = NSOffsetRect(opened, -37.0, -23.0);
    moved.size.width += 40.0;
    [window setFrame:moved display:NO];
    [window saveFrameUsingName:kFlexibleAutosaveName];
    [self closeWindowWithUUID:uuid autosaveName:kFlexibleAutosaveName];

    window = [self openWindowWithCommand:@"Named By Its Command" autosaveName:kFlexibleAutosaveName uuid:&uuid];
    XCTAssertTrue(NSEqualRects(window.frame, moved), @"the saved frame comes back: %@, expected %@",
                  NSStringFromRect(window.frame), NSStringFromRect(moved));
    [self closeWindowWithUUID:uuid autosaveName:kFlexibleAutosaveName];
}

- (void)testAFixedSizeWindowKeepsItsSizeOverASavedOne {
    NSString *uuid = nil;
    NSWindow *window = [self openWindowWithCommand:@"Window With A Title" autosaveName:kFixedAutosaveName uuid:&uuid];
    NSRect stale = NSOffsetRect(window.frame, -31.0, 0.0);
    stale.size.width += 60.0;
    stale.size.height += 40.0;
    [window setFrame:stale display:NO];
    [window saveFrameUsingName:kFixedAutosaveName];
    [self closeWindowWithUUID:uuid autosaveName:kFixedAutosaveName];

    window = [self openWindowWithCommand:@"Window With A Title" autosaveName:kFixedAutosaveName uuid:&uuid];
    XCTAssertTrue(OMCWindowNearlyEqual(NSWidth(window.contentLayoutRect), 320.0),
                  @"a saved size does not override fixed content: width %g", NSWidth(window.contentLayoutRect));
    XCTAssertTrue(OMCWindowNearlyEqual(NSHeight(window.contentLayoutRect), 180.0),
                  @"height %g", NSHeight(window.contentLayoutRect));
    XCTAssertTrue(OMCWindowNearlyEqual(NSMinX(window.frame), NSMinX(stale)),
                  @"its saved position is kept: x %g, saved %g", NSMinX(window.frame), NSMinX(stale));
    [self closeWindowWithUUID:uuid autosaveName:kFixedAutosaveName];
}

@end

#endif // CURRENT_OMC_VERSION >= 50000

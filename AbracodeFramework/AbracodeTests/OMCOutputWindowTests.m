//
//  OMCOutputWindowTests.m
//  AbracodeTests
//
//  OMC 5.6, Phase 2 (Private/phase2-builtin-actionui-windows-design.md, steps 2 and 4): what an
//  output window (EXECUTION_MODE *_with_output_window, OUTPUT_WINDOW_SETTINGS) shows. Written
//  against the 5.5 nib windows and kept for the built-in ActionUI document that replaced them
//  (BuiltInDocuments/omc_output.json): the tests read the window the user sees, through the probe
//  methods at the top. Changed with the document, by the owner's decisions: the default font is
//  Monaco 12 (was 10, and the nib's Helvetica 12 without OUTPUT_WINDOW_SETTINGS), and without
//  TEXT_COLOR and BACKGROUND_COLOR the window follows the system's light or dark appearance (was
//  black on white).
//
//  Not pinned: cascade placement (it restarts with every command run, so it only shows across the
//  objects of one run), WINDOW_ALPHA, the fades and custom PNG windows (all dropped in 5.6), and
//  localized titles.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"
#import "OMCTestCase.h"

// The adapter is linked into Abracode.framework, not into this bundle: look the class up
static id ActionUIObjCClass(void)
{
    return NSClassFromString(@"_TtC19ActionUIObjCAdapter12ActionUIObjC");
}

@interface NSObject (OMCOutputWindowTestsActionUI)
+ (nullable id)getElementPropertyWithWindowUUID:(NSString *)windowUUID viewID:(NSInteger)viewID propertyName:(NSString *)propertyName;
@end

static const NSTimeInterval kOutputWindowTestTimeout = 30.0;

@interface OMCOutputWindowTests : OMCTestCase
@property (nonatomic, strong) NSMutableArray<NSURL *> *bundlesToCleanup;
@property (nonatomic, strong) NSMutableArray<NSString *> *windowTitles;
@end

@implementation OMCOutputWindowTests

- (void)setUp
{
    [super setUp];
    self.bundlesToCleanup = [NSMutableArray array];
    self.windowTitles = [NSMutableArray array];
}

- (void)tearDown
{
    for (NSString *title in self.windowTitles)
        [[self outputWindowWithTitle:title] close];
    // the handler is deleted from a run loop timer after the window closes
    [self spinUntil:^BOOL{ return NO; } timeout:0.2];
    for (NSURL *bundleURL in self.bundlesToCleanup)
        [OMCBundleTestHelper removeTestBundle:bundleURL];
    [super tearDown];
}

#pragma mark - Probe: what the output window shows

/// The visible window with this title, or nil.
- (NSWindow *)outputWindowWithTitle:(NSString *)title
{
    for (NSWindow *window in [NSApp windows]) {
        if (window.isVisible && [window.title isEqualToString:title])
            return window;
    }
    return nil;
}

static NSTextView *FindTextView(NSView *view)
{
    if ([view isKindOfClass:[NSTextView class]])
        return (NSTextView *)view;
    for (NSView *subview in view.subviews) {
        NSTextView *found = FindTextView(subview);
        if (found != nil)
            return found;
    }
    return nil;
}

- (NSTextView *)textViewOfWindow:(NSWindow *)window
{
    return FindTextView(window.contentView);
}

- (NSString *)outputWindowText:(NSWindow *)window
{
    return [[self textViewOfWindow:window].string copy];
}

- (NSSize)outputWindowContentSize:(NSWindow *)window
{
    return [window contentRectForFrameRect:window.frame].size;
}

static NSColor *ColorFromHex(NSString *hex)
{
    if (![hex hasPrefix:@"#"] || hex.length != 7)
        return nil;
    unsigned int rgb = 0;
    if (![[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&rgb])
        return nil;
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

/// The color behind the text: the text view's own background, or, when it draws none, the
/// document's background color for it (BACKGROUND_COLOR).
- (NSColor *)outputWindowBackground:(NSWindow *)window
{
    NSTextView *textView = [self textViewOfWindow:window];
    if (textView.drawsBackground)
        return textView.backgroundColor;
    id background = [ActionUIObjCClass() getElementPropertyWithWindowUUID:window.identifier viewID:1 propertyName:@"background"];
    return [background isKindOfClass:[NSString class]] ? ColorFromHex(background) : nil;
}

#pragma mark - Helpers

/// Spins the run loop in the default mode until the block returns YES or the timeout passes.
- (BOOL)spinUntil:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return condition();
}

/// A unique window title, closed in tearDown.
- (NSString *)uniqueTitle:(NSString *)label
{
    NSString *title = [NSString stringWithFormat:@"Output %@ %@", label, [NSUUID UUID].UUIDString];
    [self.windowTitles addObject:title];
    return title;
}

/// Runs a one-command bundle whose script file's output goes to an output window, waits until the
/// command has finished, and returns the window with the given title (nil if none appeared).
- (NSWindow *)runScript:(NSString *)script label:(NSString *)label windowTitle:(NSString *)windowTitle
               settings:(NSDictionary *)settings
{
    NSString *commandID = [NSString stringWithFormat:@"output_%@", label];
    NSString *bundleName = [NSString stringWithFormat:@"OutputWindow_%@", label];
    NSMutableDictionary *command = [@{
        @"NAME": windowTitle,
        @"COMMAND_ID": commandID,
        @"EXECUTION_MODE": @"exe_script_file_with_output_window",
    } mutableCopy];
    if (settings != nil)
        command[@"OUTPUT_WINDOW_SETTINGS"] = settings;

    NSString *scriptName = [commandID stringByAppendingString:@".sh"];
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:bundleName withCommands:@[command] scripts:@{scriptName: script}];
    XCTAssertNotNil(bundleURL, @"Should create the %@ test bundle", bundleName);
    if (bundleURL == nil)
        return nil;
    [self.bundlesToCleanup addObject:bundleURL];

    OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
    OSStatus status = [OMCCommandExecutor runCommand:commandID
                                      forCommandFile:[bundleURL path]
                                         withContext:nil
                                        useNavDialog:NO
                            allowKeyWindowSubcommand:NO
                                            delegate:observer];
    XCTAssertEqual(status, noErr);
    XCTAssertTrue([observer waitForCompletionWithTimeout:kOutputWindowTestTimeout], @"The command should finish (%@)", label);
    // the window gets the last output in the same pass; give it one more
    [self spinUntil:^BOOL{ return NO; } timeout:0.1];
    return [self outputWindowWithTitle:windowTitle];
}

- (NSWindow *)runScript:(NSString *)script label:(NSString *)label settings:(NSMutableDictionary *)settings
{
    NSString *title = [self uniqueTitle:label];
    NSMutableDictionary *allSettings = (settings != nil) ? settings : [NSMutableDictionary dictionary];
    allSettings[@"WINDOW_TITLE"] = title;
    return [self runScript:script label:label windowTitle:title settings:allSettings];
}

static BOOL RunningAsRegularApp(void)
{
    return [NSRunningApplication currentApplication].activationPolicy == NSApplicationActivationPolicyRegular;
}

static void AssertColor(OMCOutputWindowTests *test, NSColor *color, CGFloat red, CGFloat green, CGFloat blue, NSString *what)
{
    // Resolved in Dark Mode: the nib's own colors (the system text color, a clear white background)
    // look the same as the engine's defaults in Light Mode, so only this tells them apart
    __block NSColor *rgb = nil;
    [[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] performAsCurrentDrawingAppearance:^{
        rgb = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    }];
    XCTAssertNotNil(rgb, @"%@ should be an RGB color", what);
    // the 5.5 engine divided by 256, not 255: FF was 0.996
    XCTAssertEqualWithAccuracy(rgb.redComponent, red, 0.01, @"%@ red", what);
    XCTAssertEqualWithAccuracy(rgb.greenComponent, green, 0.01, @"%@ green", what);
    XCTAssertEqualWithAccuracy(rgb.blueComponent, blue, 0.01, @"%@ blue", what);
    XCTAssertEqualWithAccuracy(rgb.alphaComponent, 1, 0.01, @"%@ alpha", what);
}

#pragma mark - Title and text

/// WINDOW_TITLE names the window; the output is all of the script's output, in order, also when
/// it arrives in several writes, and also when it is not ASCII.
- (void)testWindowShowsTheTitleAndAllOfTheOutput
{
    NSString *script = @"#!/bin/sh\necho one\n/bin/sleep 0.3\necho two\n/usr/bin/printf 'Za\\305\\274\\303\\263\\305\\202\\304\\207 \\342\\202\\254\\n'\n";
    NSWindow *window = [self runScript:script label:@"text" settings:nil];
    XCTAssertNotNil(window, @"The output window should be open after the command ends");
    XCTAssertEqualObjects([self outputWindowText:window], @"one\ntwo\nZa\u017C\u00F3\u0142\u0107 \u20AC\n");
}

/// Without OUTPUT_WINDOW_SETTINGS the window takes the command's name, and the default font.
- (void)testWindowWithoutSettingsTakesTheCommandNameAndTheDefaultFont
{
    NSString *name = [self uniqueTitle:@"untitled"];
    NSWindow *window = [self runScript:@"#!/bin/sh\necho named\n" label:@"untitled" windowTitle:name settings:nil];
    XCTAssertNotNil(window, @"The window should be titled with the command's NAME");
    XCTAssertEqualObjects([self outputWindowText:window], @"named\n");
    NSTextView *textView = [self textViewOfWindow:window];
    XCTAssertEqualObjects(textView.font.fontName, @"Monaco");
    XCTAssertEqualWithAccuracy(textView.font.pointSize, 12, 0.01);
}

/// Output that is not UTF-8 shows replacement characters instead of being dropped.
- (void)testBytesThatAreNotUTF8ShowAsReplacementCharacters
{
    NSWindow *window = [self runScript:@"#!/bin/sh\n/usr/bin/printf 'a\\377b\\n'\n" label:@"invalid" settings:nil];
    XCTAssertNotNil(window);
    NSString *expected = [NSString stringWithFormat:@"a%Cb\n", (unichar)0xFFFD];
    XCTAssertEqualObjects([self outputWindowText:window], expected);
}

/// A NUL byte in the output is left out; the rest of the piece still shows.
- (void)testANulByteDoesNotCutTheOutput
{
    NSWindow *window = [self runScript:@"#!/bin/sh\n/usr/bin/printf 'a\\000b\\n'\n" label:@"nul" settings:nil];
    XCTAssertNotNil(window);
    XCTAssertEqualObjects([self outputWindowText:window], @"ab\n");
}

/// Megabytes of output arrive in thousands of pieces; each is appended at the cost of the piece, so
/// the command ends long before the timeout (setting the whole text for every piece took minutes).
- (void)testLargeOutputIsAllShown
{
    NSString *script = @"#!/bin/sh\n/usr/bin/yes 0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789 | /usr/bin/head -n 20000\n";
    NSWindow *window = [self runScript:script label:@"large" settings:nil];
    XCTAssertNotNil(window);
    XCTAssertEqual([self outputWindowText:window].length, (NSUInteger)(20000 * 101), @"All 20000 lines of 101 characters should show");
}

#pragma mark - Size, position and level

/// With OUTPUT_WINDOW_SETTINGS that set only WINDOW_TITLE: a 400 x 200 content area, a floating
/// window (the utility level, staying visible when the app is not active, for a process that is
/// not a regular app), Monaco 12, read-only, in the system's text colors.
- (void)testDefaultSettings
{
    NSWindow *window = [self runScript:@"#!/bin/sh\necho defaults\n" label:@"defaults" settings:nil];
    XCTAssertNotNil(window);
    NSSize size = [self outputWindowContentSize:window];
    XCTAssertEqualWithAccuracy(size.width, 400, 0.5);
    XCTAssertEqualWithAccuracy(size.height, 200, 0.5);

    if (RunningAsRegularApp()) {
        XCTAssertEqual(window.level, NSFloatingWindowLevel);
    } else {
        XCTAssertEqual(window.level, (NSWindowLevel)kCGUtilityWindowLevel);
        XCTAssertFalse(window.hidesOnDeactivate);
    }

    NSTextView *textView = [self textViewOfWindow:window];
    XCTAssertEqualObjects(textView.font.fontName, @"Monaco");
    XCTAssertEqualWithAccuracy(textView.font.pointSize, 12, 0.01);
    XCTAssertFalse(textView.isEditable, @"The output is read-only");
    XCTAssertTrue(textView.isSelectable, @"The output can be selected and copied");
    XCTAssertEqualObjects(textView.textColor, [NSColor textColor], @"The default text color follows the appearance");
    XCTAssertEqualObjects([self outputWindowBackground:window], [NSColor textBackgroundColor], @"The default background follows the appearance");
}

- (void)testWidthAndHeight
{
    NSMutableDictionary *settings = [@{@"WINDOW_WIDTH": @520, @"WINDOW_HEIGHT": @260} mutableCopy];
    NSWindow *window = [self runScript:@"#!/bin/sh\necho sized\n" label:@"size" settings:settings];
    XCTAssertNotNil(window);
    NSSize size = [self outputWindowContentSize:window];
    XCTAssertEqualWithAccuracy(size.width, 520, 0.5);
    XCTAssertEqualWithAccuracy(size.height, 260, 0.5);
}

- (void)testRegularWindowType
{
    NSMutableDictionary *settings = [@{@"WINDOW_TYPE": @"regular"} mutableCopy];
    NSWindow *window = [self runScript:@"#!/bin/sh\necho regular\n" label:@"regular" settings:settings];
    XCTAssertNotNil(window);
    XCTAssertEqual(window.level, NSNormalWindowLevel);
}

- (void)testGlobalFloatingWindowType
{
    NSMutableDictionary *settings = [@{@"WINDOW_TYPE": @"global_floating"} mutableCopy];
    NSWindow *window = [self runScript:@"#!/bin/sh\necho global\n" label:@"global" settings:settings];
    XCTAssertNotNil(window);
    XCTAssertEqual(window.level, (NSWindowLevel)kCGUtilityWindowLevel);
    XCTAssertFalse(window.hidesOnDeactivate);
}

/// center puts the window's middle at the middle of the main screen's visible area.
- (void)testCenterPosition
{
    NSMutableDictionary *settings = [@{@"WINDOW_POSITION": @"center"} mutableCopy];
    NSWindow *window = [self runScript:@"#!/bin/sh\necho centered\n" label:@"center" settings:settings];
    XCTAssertNotNil(window);
    NSRect screen = [NSScreen mainScreen].visibleFrame;
    XCTAssertEqualWithAccuracy(NSMidX(window.frame), NSMidX(screen), 1.0);
    XCTAssertEqualWithAccuracy(NSMidY(window.frame), NSMidY(screen), 1.0);
}

/// absolute puts the window's top-left corner ABSOLUTE_POSITION_LEFT and ABSOLUTE_POSITION_TOP
/// points from the top-left corner of the main screen's visible area.
- (void)testAbsolutePosition
{
    NSMutableDictionary *settings = [@{@"WINDOW_POSITION": @"absolute",
                                       @"ABSOLUTE_POSITION_LEFT": @120,
                                       @"ABSOLUTE_POSITION_TOP": @90} mutableCopy];
    NSWindow *window = [self runScript:@"#!/bin/sh\necho placed\n" label:@"absolute" settings:settings];
    XCTAssertNotNil(window);
    NSRect screen = [NSScreen mainScreen].visibleFrame;
    XCTAssertEqualWithAccuracy(NSMinX(window.frame), NSMinX(screen) + 120, 1.0);
    XCTAssertEqualWithAccuracy(NSMaxY(window.frame), NSMaxY(screen) - 90, 1.0);
}

/// FRACT_POSITION_LEFT and FRACT_POSITION_TOP place the window's middle at that fraction of the
/// main screen's visible area, measured from its top-left corner.
- (void)testFractionalPosition
{
    NSMutableDictionary *settings = [@{@"WINDOW_POSITION": @"absolute",
                                       @"FRACT_POSITION_LEFT": @0.25,
                                       @"FRACT_POSITION_TOP": @0.4} mutableCopy];
    NSWindow *window = [self runScript:@"#!/bin/sh\necho fraction\n" label:@"fraction" settings:settings];
    XCTAssertNotNil(window);
    NSRect screen = [NSScreen mainScreen].visibleFrame;
    XCTAssertEqualWithAccuracy(NSMidX(window.frame), NSMinX(screen) + NSWidth(screen) * 0.25, 1.0);
    XCTAssertEqualWithAccuracy(NSMidY(window.frame), NSMaxY(screen) - NSHeight(screen) * 0.4, 1.0);
}

#pragma mark - Font and colors

- (void)testFontAndColors
{
    NSMutableDictionary *settings = [@{@"TEXT_FONT": @"Menlo-Regular", @"TEXT_SIZE": @13,
                                       @"TEXT_COLOR": @"FF0000", @"BACKGROUND_COLOR": @"0000FF"} mutableCopy];
    NSWindow *window = [self runScript:@"#!/bin/sh\necho styled\n" label:@"style" settings:settings];
    XCTAssertNotNil(window);
    NSTextView *textView = [self textViewOfWindow:window];
    XCTAssertEqualObjects(textView.font.fontName, @"Menlo-Regular");
    XCTAssertEqualWithAccuracy(textView.font.pointSize, 13, 0.01);
    AssertColor(self, textView.textColor, 1, 0, 0, @"TEXT_COLOR");
    AssertColor(self, [self outputWindowBackground:window], 0, 0, 1, @"BACKGROUND_COLOR");
}

#pragma mark - Closing by itself

/// Without AUTO_CLOSE_TIMEOUT the window stays open after the command ends.
- (void)testWindowStaysOpenWithoutATimeout
{
    NSWindow *window = [self runScript:@"#!/bin/sh\necho stays\n" label:@"stays" settings:nil];
    XCTAssertNotNil(window);
    [self spinUntil:^BOOL{ return NO; } timeout:0.5];
    XCTAssertTrue(window.isVisible, @"The window should stay open");
}

/// AUTO_CLOSE_TIMEOUT closes the window that long after a command that succeeded.
- (void)testWindowClosesAfterTheTimeoutOnSuccess
{
    NSMutableDictionary *settings = [@{@"AUTO_CLOSE_TIMEOUT": @1.0} mutableCopy];
    NSWindow *window = [self runScript:@"#!/bin/sh\necho closing\n" label:@"autoclose" settings:settings];
    XCTAssertNotNil(window, @"The window should still be open right after the command ends");
    BOOL closed = [self spinUntil:^BOOL{ return !window.isVisible; } timeout:5.0];
    XCTAssertTrue(closed, @"The window should close AUTO_CLOSE_TIMEOUT after the command ends");
}

/// By default (AUTO_CLOSE_ON_SUCCESS_ONLY true) a command that failed keeps its window open.
- (void)testWindowStaysOpenAfterAFailure
{
    NSMutableDictionary *settings = [@{@"AUTO_CLOSE_TIMEOUT": @0.2} mutableCopy];
    NSWindow *window = [self runScript:@"#!/bin/sh\necho failing\nexit 3\n" label:@"failure" settings:settings];
    XCTAssertNotNil(window);
    [self spinUntil:^BOOL{ return NO; } timeout:1.0];
    XCTAssertTrue(window.isVisible, @"A failed command's window should stay open");
    XCTAssertEqualObjects([self outputWindowText:window], @"failing\n");
}

/// AUTO_CLOSE_ON_SUCCESS_ONLY false closes the window after a failure too.
- (void)testWindowClosesAfterAFailureWhenAsked
{
    NSMutableDictionary *settings = [@{@"AUTO_CLOSE_TIMEOUT": @1.0, @"AUTO_CLOSE_ON_SUCCESS_ONLY": @NO} mutableCopy];
    NSWindow *window = [self runScript:@"#!/bin/sh\necho failing\nexit 3\n" label:@"failure_close" settings:settings];
    XCTAssertNotNil(window);
    BOOL closed = [self spinUntil:^BOOL{ return !window.isVisible; } timeout:5.0];
    XCTAssertTrue(closed, @"With AUTO_CLOSE_ON_SUCCESS_ONLY false the window should close after a failure");
}

@end

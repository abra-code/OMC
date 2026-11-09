//
//  OMCInputDialogTests.m
//  AbracodeTests
//
//  The INPUT dialog as a built-in ActionUI document (OMC 5.6, Phase 2, step 6; OMCInputDialog.cpp,
//  BuiltInDocuments/omc_input_*.json): what it shows and what it returns. A command echoes
//  __DLG_INPUT_TEXT__; the dialog runs modally inside runCommand, so a timer that also runs in the
//  modal run loop finds the dialog, reads it, sets the field through ActionUI and presses Return
//  or Escape, which the OK and Cancel buttons are bound to.
//
//  Not tested here: choosing a combo box menu item with the mouse (the menu's buttons are checked
//  to be there), and localized titles.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"
#import "OMCTestCase.h"

static const NSTimeInterval kInputDialogTestTimeout = 30.0;
static const NSTimeInterval kGiveUpOnDialog = 10.0;

// The documents' element ids (BuiltInDocuments/omc_input_*.json)
static const NSInteger kMessageTextID = 2;
static const NSInteger kInputFieldID = 3;
static const NSInteger kCancelButtonID = 5;
static const NSInteger kOKButtonID = 6;
static const NSInteger kFirstMenuItemID = 100;

// The adapter is linked into Abracode.framework, not into this bundle: look the class up
static id ActionUIObjCClass(void)
{
    return NSClassFromString(@"_TtC19ActionUIObjCAdapter12ActionUIObjC");
}

@interface NSObject (OMCInputDialogTestsActionUI)
+ (nullable id)getElementPropertyWithWindowUUID:(NSString *)windowUUID viewID:(NSInteger)viewID propertyName:(NSString *)propertyName;
+ (nullable NSString *)getElementValueAsStringWithWindowUUID:(NSString *)windowUUID viewID:(NSInteger)viewID viewPartID:(NSInteger)viewPartID contentType:(nullable NSString *)contentType;
+ (void)setElementValueFromStringWithWindowUUID:(NSString *)windowUUID viewID:(NSInteger)viewID viewPartID:(NSInteger)viewPartID value:(NSString *)value contentType:(nullable NSString *)contentType;
@end

@interface OMCInputDialogTests : OMCTestCase
@property (nonatomic, strong) NSMutableArray<NSURL *> *bundlesToCleanup;
@end

@implementation OMCInputDialogTests

- (void)setUp
{
    [super setUp];
    self.bundlesToCleanup = [NSMutableArray array];
}

- (void)tearDown
{
    for (NSURL *bundleURL in self.bundlesToCleanup)
        [OMCBundleTestHelper removeTestBundle:bundleURL];
    [super tearDown];
}

#pragma mark - Probe and answers

- (NSWindow *)dialogWithTitle:(NSString *)title
{
    for (NSWindow *window in [NSApp windows]) {
        if (window.isVisible && [window.title isEqualToString:title])
            return window;
    }
    return nil;
}

static id Property(NSWindow *dialog, NSInteger viewID, NSString *name)
{
    return [ActionUIObjCClass() getElementPropertyWithWindowUUID:dialog.identifier viewID:viewID propertyName:name];
}

static NSString *ValueString(NSWindow *dialog, NSInteger viewID)
{
    return [ActionUIObjCClass() getElementValueAsStringWithWindowUUID:dialog.identifier viewID:viewID viewPartID:0 contentType:nil];
}

static NSString *FieldValue(NSWindow *dialog)
{
    return ValueString(dialog, kInputFieldID);
}

static void SetFieldValue(NSWindow *dialog, NSString *value)
{
    [ActionUIObjCClass() setElementValueFromStringWithWindowUUID:dialog.identifier viewID:kInputFieldID viewPartID:0 value:value contentType:nil];
}

/// Presses a key the way the app hands it to the window: as a key equivalent. Returns whether a
/// button took it.
static BOOL PressKey(NSWindow *dialog, NSString *characters, unsigned short keyCode)
{
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                                     timestamp:[NSProcessInfo processInfo].systemUptime windowNumber:dialog.windowNumber
                                       context:nil characters:characters charactersIgnoringModifiers:characters
                                     isARepeat:NO keyCode:keyCode];
    return [dialog performKeyEquivalent:event];
}

static BOOL PressReturn(NSWindow *dialog) { return PressKey(dialog, @"\r", 36); }
static BOOL PressEscape(NSWindow *dialog) { return PressKey(dialog, [NSString stringWithFormat:@"%C", (unichar)0x1B], 53); }

/// Runs a command whose input dialog is inputDialog and which echoes "input=" and the input text.
/// While the dialog runs, answer gets its window once; a dialog still open after kGiveUpOnDialog
/// is closed. Returns the command's output, or nil when the command did not run (canceled: a
/// canceled command reports nothing, so a call that expects no output only waits a second).
- (NSString *)runInputDialog:(NSDictionary *)inputDialog label:(NSString *)label answer:(void (^)(NSWindow *dialog))answer
{
    return [self runInputDialog:inputDialog label:label expectOutput:YES answer:answer];
}

- (NSString *)runInputDialog:(NSDictionary *)inputDialog label:(NSString *)label expectOutput:(BOOL)expectOutput answer:(void (^)(NSWindow *dialog))answer
{
    NSString *title = [NSString stringWithFormat:@"Input %@ %@", label, [NSUUID UUID].UUIDString];
    NSString *commandID = [NSString stringWithFormat:@"input_%@", label];
    NSDictionary *command = @{
        @"NAME": title,
        @"COMMAND_ID": commandID,
        @"EXECUTION_MODE": @"exe_shell_script",
        @"COMMAND": @[@"echo input=", @"__DLG_INPUT_TEXT__"],
        @"INPUT_DIALOG": inputDialog,
    };
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:[NSString stringWithFormat:@"InputDialog_%@", label] withCommands:@[command] scripts:@{}];
    XCTAssertNotNil(bundleURL);
    if (bundleURL == nil)
        return nil;
    [self.bundlesToCleanup addObject:bundleURL];

    __block BOOL answered = NO;
    NSDate *start = [NSDate date];
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *aTimer) {
        NSWindow *dialog = [self dialogWithTitle:title];
        if (dialog != nil && !answered) {
            answered = YES;
            answer(dialog);
        }
        if ([[NSDate date] timeIntervalSinceDate:start] > kGiveUpOnDialog) {
            [aTimer invalidate];
            [[self dialogWithTitle:title] performClose:nil];
        }
    }];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];

    OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
    OSStatus status = [OMCCommandExecutor runCommand:commandID forCommandFile:[bundleURL path] withContext:nil
                                         useNavDialog:NO allowKeyWindowSubcommand:NO delegate:observer];
    [timer invalidate];
    XCTAssertTrue(answered, @"The input dialog should have shown (%@)", label);
    XCTAssertNil([self dialogWithTitle:title], @"The dialog should be closed when the command goes on (%@)", label);
    if (status != noErr)
        return nil;
    if (![observer waitForCompletionWithTimeout:(expectOutput ? kInputDialogTestTimeout : 1.0)])
        return nil;
    return [observer.capturedOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - Text and password

/// The message, the default text and the framework's button titles show; OK (Return) gives the
/// command the text in the field.
- (void)testTextDialogShowsItsSettingsAndReturnsTheText
{
    NSDictionary *settings = @{@"INPUT_TYPE": @"input_clear_text", @"MESSAGE": @"Name of the archive:", @"DEFAULT": @"Archive"};
    NSString *output = [self runInputDialog:settings label:@"text" answer:^(NSWindow *dialog) {
        XCTAssertEqualObjects(ValueString(dialog, kMessageTextID), @"Name of the archive:", @"The message is the Text's value (what it shows)");
        XCTAssertEqualObjects(FieldValue(dialog), @"Archive");
        XCTAssertEqualObjects(Property(dialog, kOKButtonID, @"title"), @"OK");
        XCTAssertEqualObjects(Property(dialog, kCancelButtonID, @"title"), @"Cancel");
        XCTAssertTrue([dialog.firstResponder isKindOfClass:[NSTextView class]], @"The text field should have the keyboard focus (first responder: %@)", dialog.firstResponder);
        SetFieldValue(dialog, @"Backup");
        XCTAssertTrue(PressReturn(dialog), @"Return should press OK");
    }];
    XCTAssertEqualObjects(output, @"input=Backup");
}

/// Escape is Cancel: the command does not run.
- (void)testEscapeCancelsTheCommand
{
    NSString *output = [self runInputDialog:@{@"INPUT_TYPE": @"input_clear_text"} label:@"escape" expectOutput:NO answer:^(NSWindow *dialog) {
        SetFieldValue(dialog, @"never used");
        XCTAssertTrue(PressEscape(dialog), @"Escape should press Cancel");
    }];
    XCTAssertNil(output, @"A canceled input dialog should cancel the command");
}

/// Closing the window is Cancel too.
- (void)testClosingTheDialogCancelsTheCommand
{
    NSString *output = [self runInputDialog:@{@"INPUT_TYPE": @"input_clear_text"} label:@"close" expectOutput:NO answer:^(NSWindow *dialog) {
        [dialog performClose:nil];
    }];
    XCTAssertNil(output, @"Closing the input dialog should cancel the command");
}

/// OK_BUTTON_NAME and CANCEL_BUTTON_NAME title the buttons; without a MESSAGE the message is hidden.
- (void)testButtonNamesAndNoMessage
{
    NSDictionary *settings = @{@"OK_BUTTON_NAME": @"Go", @"CANCEL_BUTTON_NAME": @"Never mind"};
    NSString *output = [self runInputDialog:settings label:@"names" answer:^(NSWindow *dialog) {
        XCTAssertEqualObjects(Property(dialog, kOKButtonID, @"title"), @"Go");
        XCTAssertEqualObjects(Property(dialog, kCancelButtonID, @"title"), @"Never mind");
        XCTAssertEqualObjects(Property(dialog, kMessageTextID, @"hidden"), @YES);
        SetFieldValue(dialog, @"x");
        PressReturn(dialog);
    }];
    XCTAssertEqualObjects(output, @"input=x");
}

/// A long message wraps, and the window is tall enough for all of it.
- (void)testALongMessageFitsInTheWindow
{
    NSString *message = @"This message is long enough to wrap onto several lines in the input dialog, which is about four hundred points wide, so the window has to grow to show all of it instead of cutting off its last lines.";
    NSString *output = [self runInputDialog:@{@"MESSAGE": message} label:@"long" answer:^(NSWindow *dialog) {
        // as the dialog first shows
        CGFloat shown = [dialog contentRectForFrameRect:dialog.frame].size.height;
        [dialog.contentView layoutSubtreeIfNeeded];
        CGFloat needed = dialog.contentViewController.view.fittingSize.height;
        XCTAssertEqualObjects(ValueString(dialog, kMessageTextID), message);
        XCTAssertGreaterThanOrEqual(shown + 0.5, needed, @"The window should be tall enough for the whole message");
        XCTAssertGreaterThan(shown, 150, @"Four lines of message, a field and the buttons need more than 150 points");
        SetFieldValue(dialog, @"y");
        PressReturn(dialog);
    }];
    XCTAssertEqualObjects(output, @"input=y");
}

- (void)testPasswordDialogReturnsTheText
{
    NSString *output = [self runInputDialog:@{@"INPUT_TYPE": @"input_password_text"} label:@"password" answer:^(NSWindow *dialog) {
        SetFieldValue(dialog, @"secret");
        XCTAssertTrue(PressReturn(dialog));
    }];
    XCTAssertEqualObjects(output, @"input=secret");
}

#pragma mark - Pop-up menu and combo box

/// The pop-up shows the items' names and starts on the DEFAULT name; OK gives the chosen item's
/// VALUE, or its NAME when it has none.
- (void)testPopupReturnsTheChosenItemsValue
{
    NSDictionary *settings = @{@"INPUT_TYPE": @"input_popup_menu", @"DEFAULT": @"Two",
                               @"INPUT_MENU": @[@{@"NAME": @"One", @"VALUE": @"1"}, @{@"NAME": @"Two", @"VALUE": @"2"}, @{@"NAME": @"Three"}]};
    NSString *output = [self runInputDialog:settings label:@"popup" answer:^(NSWindow *dialog) {
        NSArray *options = Property(dialog, kInputFieldID, @"options");
        XCTAssertEqual(options.count, (NSUInteger)3);
        XCTAssertEqualObjects([options.firstObject objectForKey:@"title"], @"One");
        XCTAssertEqualObjects(FieldValue(dialog), @"2", @"The DEFAULT item should be chosen");
        SetFieldValue(dialog, @"3");
        XCTAssertTrue(PressReturn(dialog));
    }];
    XCTAssertEqualObjects(output, @"input=Three");

    output = [self runInputDialog:settings label:@"popup_default" answer:^(NSWindow *dialog) {
        PressReturn(dialog);
    }];
    XCTAssertEqualObjects(output, @"input=2", @"OK without a change gives the DEFAULT item's VALUE");
}

/// The combo box's menu has a button per item; text that is an item's name gives its VALUE, any
/// other text is the choice itself.
- (void)testComboBoxReturnsAValueForANameAndOtherwiseTheText
{
    NSDictionary *settings = @{@"INPUT_TYPE": @"input_combo_box", @"DEFAULT": @"Pear",
                               @"INPUT_MENU": @[@{@"NAME": @"Apple", @"VALUE": @"a"}, @{@"NAME": @"Banana", @"VALUE": @"b"}]};
    NSString *output = [self runInputDialog:settings label:@"combo" answer:^(NSWindow *dialog) {
        XCTAssertEqualObjects(Property(dialog, kFirstMenuItemID, @"title"), @"Apple");
        XCTAssertEqualObjects(Property(dialog, kFirstMenuItemID + 1, @"title"), @"Banana");
        XCTAssertEqualObjects(FieldValue(dialog), @"Pear");
        SetFieldValue(dialog, @"Banana");
        XCTAssertTrue(PressReturn(dialog));
    }];
    XCTAssertEqualObjects(output, @"input=b");

    output = [self runInputDialog:settings label:@"combo_text" answer:^(NSWindow *dialog) {
        PressReturn(dialog);
    }];
    XCTAssertEqualObjects(output, @"input=Pear");
}

@end

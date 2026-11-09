//
//  OMCActionUIDialogControlTests.m
//  AbracodeTests
//
//  Pin tests for what omc_dialog_control's verbs do to an ActionUI command window, before the
//  window's logic moves to C++ (Phase 5 step 8, Private/phase5-step8a-pin-test-gaps.md, gap 8).
//  Each test sends a verb through the window's message port, as a handler would, and reads the
//  effect back from ActionUI's model or from the NSWindow: enable/disable, show/hide, properties
//  and states (with the string-or-JSON parsing of their values), list items, an emptied table,
//  a value from standard input, inserted and removed elements, and the window's move and resize.
//
//  The fixture is TestBundles/ActionUI-Window.omc: "Window Controls" opens WindowControls.json,
//  and window.control runs omc_dialog_control with the arguments on the first line of its text
//  context, passing any further lines to its standard input.
//
//  Not pinned: toasts (ActionUI has no getter for the current toast); the per-control omc_move,
//  omc_resize, omc_scroll, omc_select and omc_set_command_id, which only log for an ActionUI window
//  (OMCActionUIWindowController.mm).
//

#import <AppKit/AppKit.h>
#import "OMCTestCase.h"
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"

#if CURRENT_OMC_VERSION >= 50000

static NSString * const kControlsAutosaveName = @"OMC.WindowControls";

// WindowControls.json's element ids
static const NSInteger kFieldID = 2;
static const NSInteger kButtonID = 3;
static const NSInteger kListID = 4;
static const NSInteger kTableID = 5;
static const NSInteger kContainerID = 6;
static const NSInteger kRemovableTextID = 7;

// The adapter is linked into Abracode.framework, not into this bundle: look the class up
static id ActionUIObjCClass(void)
{
    return NSClassFromString(@"_TtC19ActionUIObjCAdapter12ActionUIObjC");
}

@interface NSObject (OMCActionUIDialogControlTestsActionUI)
+ (nullable id)getElementPropertyWithWindowUUID:(NSString *)windowUUID viewID:(NSInteger)viewID propertyName:(NSString *)propertyName;
+ (nullable id)getElementStateWithWindowUUID:(NSString *)windowUUID viewID:(NSInteger)viewID key:(NSString *)key;
+ (nullable NSString *)getElementValueAsStringWithWindowUUID:(NSString *)windowUUID viewID:(NSInteger)viewID viewPartID:(NSInteger)viewPartID contentType:(nullable NSString *)contentType;
+ (nullable NSArray *)getElementRowsWithWindowUUID:(NSString *)windowUUID viewID:(NSInteger)viewID;
+ (NSInteger)getElementColumnCountWithWindowUUID:(NSString *)windowUUID viewID:(NSInteger)viewID;
+ (NSDictionary *)getElementInfoWithWindowUUID:(NSString *)windowUUID;
@end

@interface OMCActionUIDialogControlTests : XCTestCase
@property (nonatomic, copy) NSString *bundlePath;
@property (nonatomic, copy) NSString *uuid;
@property (nonatomic, strong) NSWindow *window;
@end

@implementation OMCActionUIDialogControlTests

#pragma mark - Helpers

- (void)spinUntil:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

- (NSWindow *)visibleControlsWindow {
    for (NSWindow *window in [NSApp windows]) {
        if (window.isVisible && [window.frameAutosaveName isEqualToString:kControlsAutosaveName])
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

// Sends omc_dialog_control <window> <arguments> as a handler would; `input` goes to its standard input
- (void)control:(NSString *)arguments input:(NSString *)input {
    NSString *request = [NSString stringWithFormat:@"%@ %@", self.uuid, arguments];
    if (input != nil)
        request = [request stringByAppendingFormat:@"\n%@", input];
    (void)[self runCommand:@"window.control" context:request];
}

- (void)control:(NSString *)arguments {
    [self control:arguments input:nil];
}

// The message arrives through the window's port: wait until `read` returns what is expected
- (id)waitFor:(id)expected read:(id (^)(void))read {
    __block id value = nil;
    [self spinUntil:^BOOL{ value = read(); return [value isEqual:expected]; } timeout:5.0];
    return value;
}

- (id)property:(NSString *)name ofView:(NSInteger)viewID {
    return [ActionUIObjCClass() getElementPropertyWithWindowUUID:self.uuid viewID:viewID propertyName:name];
}

- (id)state:(NSString *)key ofView:(NSInteger)viewID {
    return [ActionUIObjCClass() getElementStateWithWindowUUID:self.uuid viewID:viewID key:key];
}

- (NSArray *)rowsOfView:(NSInteger)viewID {
    return [ActionUIObjCClass() getElementRowsWithWindowUUID:self.uuid viewID:viewID] ?: @[];
}

- (NSDictionary *)elementInfo {
    return [ActionUIObjCClass() getElementInfoWithWindowUUID:self.uuid];
}

- (void)setUp {
    [super setUp];
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Window"];
    XCTAssertNotNil(bundleURL, @"ActionUI-Window.omc should be in the test resources");
    self.bundlePath = [bundleURL path];
    XCTAssertNotNil(ActionUIObjCClass(), @"the ActionUI Objective-C adapter should be loaded");
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:[@"NSWindow Frame " stringByAppendingString:kControlsAutosaveName]];

    self.uuid = [self runCommand:@"Window Controls" context:nil];
    XCTAssertTrue(self.uuid.length > 0, @"Window Controls should print its window's UUID");
    __block NSWindow *window = nil;
    [self spinUntil:^BOOL{ window = [self visibleControlsWindow]; return window != nil; } timeout:5.0];
    XCTAssertNotNil(window, @"Window Controls should open its window");
    self.window = window;
}

- (void)tearDown {
    if (self.uuid.length > 0) {
        [self control:@"omc_window omc_terminate_cancel"];
        [self spinUntil:^BOOL{ return [self visibleControlsWindow] == nil; } timeout:5.0];
        XCTAssertNil([self visibleControlsWindow], @"the window should close");
    }
    self.window = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:[@"NSWindow Frame " stringByAppendingString:kControlsAutosaveName]];
    [super tearDown];
}

#pragma mark - Enable, show

- (void)testDisableAndEnableSetTheDisabledProperty {
    [self control:[NSString stringWithFormat:@"%ld omc_disable", (long)kButtonID]];
    XCTAssertEqualObjects([self waitFor:@YES read:^id{ return [self property:@"disabled" ofView:kButtonID]; }], @YES,
                          @"omc_disable sets the element's disabled property");
    [self control:[NSString stringWithFormat:@"%ld omc_enable", (long)kButtonID]];
    XCTAssertEqualObjects([self waitFor:@NO read:^id{ return [self property:@"disabled" ofView:kButtonID]; }], @NO,
                          @"omc_enable clears it");
}

- (void)testHideAndShowSetTheHiddenProperty {
    [self control:[NSString stringWithFormat:@"%ld omc_hide", (long)kButtonID]];
    XCTAssertEqualObjects([self waitFor:@YES read:^id{ return [self property:@"hidden" ofView:kButtonID]; }], @YES,
                          @"omc_hide sets the element's hidden property");
    [self control:[NSString stringWithFormat:@"%ld omc_show", (long)kButtonID]];
    XCTAssertEqualObjects([self waitFor:@NO read:^id{ return [self property:@"hidden" ofView:kButtonID]; }], @NO,
                          @"omc_show clears it");
}

#pragma mark - Properties and states

// A value that looks like a JSON fragment is parsed as JSON; anything else, or a fragment that
// fails to parse, is a string
- (void)testSetPropertyParsesJSONFragmentsAndKeepsOtherTextAsAString {
    NSString *button = [NSString stringWithFormat:@"%ld", (long)kButtonID];
    NSDictionary<NSString *, NSArray *> *cases = @{
        @"omcTestBool":   @[@"true", @YES],
        @"omcTestNumber": @[@"42", @42],
        @"omcTestArray":  @[@"'[\"a\",\"b\"]'", @[@"a", @"b"]],
        @"omcTestObject": @[@"'{\"k\":1}'", @{@"k": @1}],
        @"omcTestQuoted": @[@"'\"quoted\"'", @"quoted"],
        @"omcTestText":   @[@"'plain words'", @"plain words"],
        @"omcTestWord":   @[@"fred", @"fred"],
        @"omcTestNull":   @[@"null", [NSNull null]],
        // NSJSONSerialization, which read these values first, allowed a trailing comma
        @"omcTestTrailingComma": @[@"'[1,2,]'", @[@1, @2]],
    };
    for (NSString *key in cases) {
        NSString *argument = cases[key][0];
        id expected = cases[key][1];
        [self control:[NSString stringWithFormat:@"%@ omc_set_property %@ %@", button, key, argument]];
        id value = [self waitFor:expected read:^id{ return [self property:key ofView:kButtonID]; }];
        XCTAssertEqualObjects(value, expected, @"omc_set_property %@ %@", key, argument);
    }
}

// A number keeps the type it had when OMC parsed it with NSJSONSerialization and ActionUI took the
// NSNumber: an integral number, written with a fraction or not, is an integer, and any other a double.
// Equality cannot tell them apart (@1 equals @1.0), the number's type can.
- (void)testSetPropertyKeepsIntegerAndDoubleNumbers {
    NSString *button = [NSString stringWithFormat:@"%ld", (long)kButtonID];
    NSDictionary<NSString *, NSArray *> *cases = @{
        @"omcTestInteger":      @[@"7", @"q"],
        @"omcTestIntegralFloat": @[@"1.0", @"q"],
        @"omcTestDouble":       @[@"1.5", @"d"],
        @"omcTestNegative":     @[@"-0.25", @"d"],
    };
    for (NSString *key in cases) {
        NSString *argument = cases[key][0];
        [self control:[NSString stringWithFormat:@"%@ omc_set_property %@ %@", button, key, argument]];
        __block id value = nil;
        [self spinUntil:^BOOL{ value = [self property:key ofView:kButtonID]; return value != nil; } timeout:5.0];
        XCTAssertTrue([value isKindOfClass:[NSNumber class]], @"omc_set_property %@ %@ gives a number: %@", key, argument, value);
        NSString *type = [value isKindOfClass:[NSNumber class]] ? [NSString stringWithUTF8String:[(NSNumber *)value objCType]] : @"";
        XCTAssertEqualObjects(type, cases[key][1], @"omc_set_property %@ %@: %@", key, argument, value);
        XCTAssertEqualWithAccuracy([value doubleValue], [argument doubleValue], 1e-12);
    }

    // NSJSONSerialization read a number with a fraction as a double, so one past 2^53 lost its last
    // digit before ActionUI made it an integer; reading the text exactly would keep it
    [self control:[NSString stringWithFormat:@"%@ omc_set_property omcTestPastDoublePrecision 9007199254740993.0", button]];
    __block id value = nil;
    [self spinUntil:^BOOL{ value = [self property:@"omcTestPastDoublePrecision" ofView:kButtonID]; return value != nil; } timeout:5.0];
    XCTAssertTrue([value isKindOfClass:[NSNumber class]], @"a number: %@", value);
    XCTAssertEqual([value longLongValue], 9007199254740992LL, @"the double's value, as before: %@", value);
}

- (void)testSetStateParsesItsValueLikeAProperty {
    NSString *field = [NSString stringWithFormat:@"%ld", (long)kFieldID];
    [self control:[NSString stringWithFormat:@"%@ omc_set_state omcTestState '{\"k\":[1,2]}'", field]];
    id expected = @{@"k": @[@1, @2]};
    XCTAssertEqualObjects([self waitFor:expected read:^id{ return [self state:@"omcTestState" ofView:kFieldID]; }], expected,
                          @"omc_set_state parses a JSON value");
    // A second key: ActionUI refuses a value of another type for a key that already has one
    [self control:[NSString stringWithFormat:@"%@ omc_set_state omcTestText 'two words'", field]];
    XCTAssertEqualObjects([self waitFor:@"two words" read:^id{ return [self state:@"omcTestText" ofView:kFieldID]; }], @"two words",
                          @"and keeps other text as a string");
}

#pragma mark - Values, lists, tables

// The whole input, its final newline included: window.control ends its input with one
- (void)testSetValueFromStdinSetsTheValueToTheWholeInput {
    [self control:[NSString stringWithFormat:@"%ld omc_set_value_from_stdin", (long)kFieldID] input:@"from standard input"];
    NSString *value = [self waitFor:@"from standard input\n" read:^id{
        return [ActionUIObjCClass() getElementValueAsStringWithWindowUUID:self.uuid viewID:kFieldID viewPartID:0 contentType:nil];
    }];
    XCTAssertEqualObjects(value, @"from standard input\n");
}

- (void)testListVerbsSetAppendAndRemoveItems {
    NSString *list = [NSString stringWithFormat:@"%ld", (long)kListID];
    [self control:[list stringByAppendingString:@" omc_list_set_items alpha 'beta gamma'"]];
    NSArray *expected = @[@[@"alpha"], @[@"beta gamma"]];
    XCTAssertEqualObjects([self waitFor:expected read:^id{ return [self rowsOfView:kListID]; }], expected,
                          @"omc_list_set_items makes one single-column row per item");

    [self control:[list stringByAppendingString:@" omc_list_append_items delta"]];
    expected = @[@[@"alpha"], @[@"beta gamma"], @[@"delta"]];
    XCTAssertEqualObjects([self waitFor:expected read:^id{ return [self rowsOfView:kListID]; }], expected,
                          @"omc_list_append_items appends");

    [self control:[list stringByAppendingString:@" omc_list_set_items_from_stdin"] input:@"epsilon\nzeta"];
    expected = @[@[@"epsilon"], @[@"zeta"]];
    XCTAssertEqualObjects([self waitFor:expected read:^id{ return [self rowsOfView:kListID]; }], expected,
                          @"omc_list_set_items_from_stdin replaces the items, one per line");

    [self control:[list stringByAppendingString:@" omc_list_remove_all"]];
    XCTAssertEqualObjects([self waitFor:@[] read:^id{ return [self rowsOfView:kListID]; }], @[],
                          @"omc_list_remove_all removes every item");
}

// The longest verb: omc_dialog_control once skipped words longer than a stale longest-word limit
// and sent this one as the list's value, so the list became one item, the verb's own name
- (void)testListAppendItemsFromStdinAppendsOneItemPerLine {
    NSString *list = [NSString stringWithFormat:@"%ld", (long)kListID];
    [self control:[list stringByAppendingString:@" omc_list_set_items alpha"]];
    NSArray *expected = @[@[@"alpha"]];
    XCTAssertEqualObjects([self waitFor:expected read:^id{ return [self rowsOfView:kListID]; }], expected,
                          @"the list has an item before the append");

    [self control:[list stringByAppendingString:@" omc_list_append_items_from_stdin"] input:@"beta\ngamma"];
    expected = @[@[@"alpha"], @[@"beta"], @[@"gamma"]];
    XCTAssertEqualObjects([self waitFor:expected read:^id{ return [self rowsOfView:kListID]; }], expected,
                          @"omc_list_append_items_from_stdin appends one item per line");
}

- (void)testTablePrepareEmptyRemovesTheRowsAndKeepsTheColumns {
    NSString *table = [NSString stringWithFormat:@"%ld", (long)kTableID];
    [self control:[table stringByAppendingString:@" omc_table_set_rows \"$(printf 'a1\\tb1')\" \"$(printf 'a2\\tb2')\""]];
    NSArray *expected = @[@[@"a1", @"b1"], @[@"a2", @"b2"]];
    XCTAssertEqualObjects([self waitFor:expected read:^id{ return [self rowsOfView:kTableID]; }], expected,
                          @"the table has rows before it is emptied");

    [self control:[table stringByAppendingString:@" omc_table_prepare_empty"]];
    XCTAssertEqualObjects([self waitFor:@[] read:^id{ return [self rowsOfView:kTableID]; }], @[],
                          @"omc_table_prepare_empty removes every row");
    XCTAssertEqual([ActionUIObjCClass() getElementColumnCountWithWindowUUID:self.uuid viewID:kTableID], 2,
                   @"and keeps the columns");
}

- (NSString *)valueOfView:(NSInteger)viewID part:(NSInteger)part {
    return [ActionUIObjCClass() getElementValueAsStringWithWindowUUID:self.uuid viewID:viewID viewPartID:part contentType:nil];
}

- (void)testTableColumnsWidthsAddedRowsAndRowSelection {
    NSString *table = [NSString stringWithFormat:@"%ld", (long)kTableID];
    [self control:[table stringByAppendingString:@" omc_table_set_columns First Second"]];
    NSArray *columns = @[@"First", @"Second"];
    XCTAssertEqualObjects([self waitFor:columns read:^id{ return [self property:@"columns" ofView:kTableID]; }], columns,
                          @"omc_table_set_columns sets the columns property");

    [self control:[table stringByAppendingString:@" omc_table_set_column_widths 120 80.5"]];
    NSArray *widths = @[@120, @80.5];
    XCTAssertEqualObjects([self waitFor:widths read:^id{ return [self property:@"widths" ofView:kTableID]; }], widths,
                          @"omc_table_set_column_widths sets the widths property, as numbers");
    NSArray *storedWidths = [self property:@"widths" ofView:kTableID];
    if (storedWidths.count == 2) {
        XCTAssertEqualObjects([NSString stringWithUTF8String:[storedWidths[0] objCType]], @"q", @"an integral width is an integer");
        XCTAssertEqualObjects([NSString stringWithUTF8String:[storedWidths[1] objCType]], @"d", @"another a double");
    }

    [self control:[table stringByAppendingString:@" omc_table_set_rows \"$(printf 'a1\\tb1')\""]];
    [self control:[table stringByAppendingString:@" omc_table_add_rows \"$(printf 'a2\\tb2')\" \"$(printf 'a3\\tb3')\""]];
    NSArray *rows = @[@[@"a1", @"b1"], @[@"a2", @"b2"], @[@"a3", @"b3"]];
    XCTAssertEqualObjects([self waitFor:rows read:^id{ return [self rowsOfView:kTableID]; }], rows,
                          @"omc_table_add_rows appends rows split at their tabs");

    [self control:[table stringByAppendingString:@" omc_select_row 1"]];
    XCTAssertEqualObjects([self waitFor:@"b2" read:^id{ return [self valueOfView:kTableID part:2]; }], @"b2",
                          @"omc_select_row selects the row at a 0-based index");

    [self control:[table stringByAppendingString:@" omc_select_row_with_content b3 2"]];
    XCTAssertEqualObjects([self waitFor:@"a3" read:^id{ return [self valueOfView:kTableID part:1]; }], @"a3",
                          @"omc_select_row_with_content finds the text in the 1-based column");

    [self control:[table stringByAppendingString:@" omc_select_row_with_content b1"]];
    XCTAssertEqualObjects([self waitFor:@"a1" read:^id{ return [self valueOfView:kTableID part:1]; }], @"a1",
                          @"without a column it finds the text in any column");

    [self control:[table stringByAppendingString:@" omc_deselect"]];
    XCTAssertEqualObjects([self waitFor:@"" read:^id{ return [self valueOfView:kTableID part:1] ?: @""; }], @"",
                          @"omc_deselect clears the selection");
}

#pragma mark - Elements

// Read through ActionUI's element info (the window's live elements, as ActionUI lists them since
// its getElementInfo fix of 2026-11-09) and the elements' properties
- (void)testInsertElementAndRemoveElementChangeTheWindowsElements {
    XCTAssertEqualObjects([self elementInfo][@(kRemovableTextID)], @"Text", @"the element to remove is there to begin with");
    XCTAssertEqualObjects([self property:@"text" ofView:kRemovableTextID], @"Removable");

    [self control:[NSString stringWithFormat:@"%ld omc_insert_element '{\"id\":30,\"type\":\"Text\",\"properties\":{\"text\":\"Inserted\"}}'", (long)kContainerID]];
    XCTAssertEqualObjects([self waitFor:@"Text" read:^id{ return [self elementInfo][@30]; }], @"Text",
                          @"omc_insert_element adds the element");
    XCTAssertEqualObjects([self property:@"text" ofView:30], @"Inserted");

    [self control:[NSString stringWithFormat:@"%ld omc_remove_element", (long)kRemovableTextID]];
    [self spinUntil:^BOOL{ return [self elementInfo][@(kRemovableTextID)] == nil; } timeout:5.0];
    XCTAssertNil([self elementInfo][@(kRemovableTextID)], @"omc_remove_element removes the element from the window's elements");
    XCTAssertNil([self property:@"text" ofView:kRemovableTextID], @"and its properties");
    XCTAssertEqualObjects([self elementInfo][@30], @"Text", @"and leaves the others");
    XCTAssertEqualObjects([self property:@"text" ofView:30], @"Inserted");
}

#pragma mark - The window's move and resize

- (void)testWindowResizeSetsTheLayoutAreaAndMoveSetsTheTopLeft {
    [self control:@"omc_window omc_resize 420 330"];
    NSWindow *window = self.window;
    [self spinUntil:^BOOL{ return NSEqualSizes(window.contentLayoutRect.size, NSMakeSize(420, 330)); } timeout:5.0];
    XCTAssertTrue(NSEqualSizes(window.contentLayoutRect.size, NSMakeSize(420, 330)),
                  @"omc_window omc_resize W H sizes the layout area, below the titlebar: %@", NSStringFromSize(window.contentLayoutRect.size));

    [self control:@"omc_window omc_move 100 120"];
    // Measured from the top left of the main screen's visible area, in points
    NSRect screen = [[NSScreen mainScreen] visibleFrame];
    NSPoint expected = NSMakePoint(NSMinX(screen) + 100, NSMaxY(screen) - 120);
    [self spinUntil:^BOOL{ return NSMinX(window.frame) == expected.x && NSMaxY(window.frame) == expected.y; } timeout:5.0];
    XCTAssertEqual(NSMinX(window.frame), expected.x, @"omc_window omc_move X Y puts the window's left edge X points from the screen's");
    XCTAssertEqual(NSMaxY(window.frame), expected.y, @"and its top Y points below the top of the screen's visible area");
}

@end

#endif // CURRENT_OMC_VERSION >= 50000

//
//  OMCAboutWindowTests.m
//  CommandTests
//
//  The applet's About window (OMCAboutWindow.cpp, BuiltInDocuments/command_about.json): what it
//  shows from an app bundle (icon, name, version, Credits.md, copyright), what it leaves out when the
//  bundle lacks it, that one window shows at a time, and that the menu bar's About item opens it.
//  Each test makes a small app bundle in a temporary folder and shows its About window through
//  OMCShowAboutWindow; the window is found by its identifier, the document's window UUID, through
//  which the tests read the document's values.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>
#import "OMCMainMenuController.h"
#import "OMCCommandExecutor.h"
#include "OMCAboutWindow.h"
#import "OMCTestCase.h"

// The document's element ids (BuiltInDocuments/command_about.json)
static const NSInteger kIconID = 1;
static const NSInteger kNameID = 2;
static const NSInteger kVersionID = 3;
static const NSInteger kCreditsID = 5;
static const NSInteger kCopyrightID = 6;

// The adapter is linked into Command.framework, not into this bundle: look the class up
static id ActionUIObjCClass(void)
{
    return NSClassFromString(@"_TtC19ActionUIObjCAdapter12ActionUIObjC");
}

@interface NSObject (OMCAboutWindowTestsActionUI)
+ (nullable id)getElementPropertyWithWindowUUID:(NSString *)windowUUID viewID:(NSInteger)viewID propertyName:(NSString *)propertyName;
+ (nullable NSString *)getElementValueAsStringWithWindowUUID:(NSString *)windowUUID viewID:(NSInteger)viewID viewPartID:(NSInteger)viewPartID contentType:(nullable NSString *)contentType;
@end

@interface OMCAboutWindowTests : OMCTestCase
@property (nonatomic, strong) NSURL *folderURL;
@end

@implementation OMCAboutWindowTests

- (void)setUp
{
    [super setUp];
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"OMCAboutWindowTests-%@", [NSUUID UUID].UUIDString]];
    self.folderURL = [NSURL fileURLWithPath:folder isDirectory:YES];
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:self.folderURL withIntermediateDirectories:YES attributes:nil error:NULL]);
}

- (void)tearDown
{
    OMCCloseAboutWindow();
    [[NSFileManager defaultManager] removeItemAtURL:self.folderURL error:NULL];
    [super tearDown];
}

#pragma mark - Helpers

/// An app bundle named <name>.app with this Info.plist, and optionally Credits.md and an icon (the
/// engine's own app.icns, under the name CFBundleIconFile gives)
- (CFBundleRef)createBundleNamed:(NSString *)name info:(NSDictionary *)info credits:(nullable NSString *)credits CF_RETURNS_RETAINED
{
    NSURL *bundleURL = [self.folderURL URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"app"] isDirectory:YES];
    NSURL *resources = [bundleURL URLByAppendingPathComponent:@"Contents/Resources" isDirectory:YES];
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:resources withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSURL *infoURL = [bundleURL URLByAppendingPathComponent:@"Contents/Info.plist"];
    XCTAssertTrue([info writeToURL:infoURL error:NULL]);
    if (credits != nil)
        XCTAssertTrue([credits writeToURL:[resources URLByAppendingPathComponent:@"Credits.md"] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    NSString *iconFile = info[@"CFBundleIconFile"];
    if (iconFile != nil) {
        NSBundle *engineBundle = [NSBundle bundleForClass:[OMCCommandExecutor class]];
        NSURL *engineIcon = [engineBundle URLForResource:@"app" withExtension:@"icns"];
        XCTAssertNotNil(engineIcon);
        NSString *iconName = [iconFile.stringByDeletingPathExtension stringByAppendingPathExtension:@"icns"];
        XCTAssertTrue([[NSFileManager defaultManager] copyItemAtURL:engineIcon toURL:[resources URLByAppendingPathComponent:iconName] error:NULL]);
    }
    return CFBundleCreate(kCFAllocatorDefault, (__bridge CFURLRef)bundleURL);
}

- (nullable NSString *)aboutWindowUUID
{
    return CFBridgingRelease(OMCCopyAboutWindowUUID());
}

- (nullable NSWindow *)windowWithUUID:(NSString *)uuid
{
    for (NSWindow *window in [NSApp windows]) {
        if ([window.identifier isEqualToString:uuid])
            return window;
    }
    return nil;
}

- (nullable NSString *)valueOf:(NSInteger)viewID inWindow:(NSString *)uuid
{
    return [ActionUIObjCClass() getElementValueAsStringWithWindowUUID:uuid viewID:viewID viewPartID:0 contentType:nil];
}

#pragma mark - Tests

- (void)testShowsWhatTheBundleHas
{
    NSDictionary *info = @{
        @"CFBundleIdentifier": @"com.abracode.test.about-full",
        @"CFBundleName": @"Sample Applet",
        @"CFBundleShortVersionString": @"2.1",
        @"CFBundleVersion": @"2105",
        @"CFBundleIconFile": @"SampleIcon",
        @"NSHumanReadableCopyright": @"Copyright 2026 Sample Maker",
    };
    NSString *credits = @"# Thanks\n\nBuilt with **Command Engine**.\n";
    CFBundleRef bundle = [self createBundleNamed:@"Sample" info:info credits:credits];
    XCTAssertTrue(bundle != NULL);
    if (bundle == NULL)
        return;

    OMCShowAboutWindow(bundle);
    NSString *uuid = [self aboutWindowUUID];
    XCTAssertNotNil(uuid);
    NSWindow *window = [self windowWithUUID:uuid];
    XCTAssertNotNil(window);
    XCTAssertTrue(window.isVisible);
    XCTAssertEqualObjects(window.title, @"About Sample Applet");
    XCTAssertFalse((window.styleMask & NSWindowStyleMaskResizable) != 0, @"fixed size, as macOS's About panel");

    XCTAssertEqualObjects([self valueOf:kNameID inWindow:uuid], @"Sample Applet");
    XCTAssertEqualObjects([self valueOf:kVersionID inWindow:uuid], @"Version 2.1 (2105)");
    XCTAssertEqualObjects([self valueOf:kCopyrightID inWindow:uuid], @"Copyright 2026 Sample Maker");
    XCTAssertEqualObjects([self valueOf:kCreditsID inWindow:uuid], credits);
    NSString *iconPath = [ActionUIObjCClass() getElementPropertyWithWindowUUID:uuid viewID:kIconID propertyName:@"filePath"];
    XCTAssertEqualObjects(iconPath.lastPathComponent, @"SampleIcon.icns");

    // One at a time: About again brings the same window to the front
    OMCShowAboutWindow(bundle);
    XCTAssertEqualObjects([self aboutWindowUUID], uuid);

    // Closed by the user: gone, and About makes a new one
    [window performClose:nil];
    XCTAssertNil([self aboutWindowUUID]);
    OMCShowAboutWindow(bundle);
    NSString *newUUID = [self aboutWindowUUID];
    XCTAssertNotNil(newUUID);
    XCTAssertNotEqualObjects(newUUID, uuid);
    XCTAssertTrue([self windowWithUUID:newUUID].isVisible);
    CFRelease(bundle);
}

- (void)testLeavesOutWhatTheBundleLacks
{
    // No icon, copyright or Credits.md; the build version alone
    NSDictionary *info = @{
        @"CFBundleIdentifier": @"com.abracode.test.about-bare",
        @"CFBundleName": @"Bare Applet",
        @"CFBundleVersion": @"7",
    };
    CFBundleRef bundle = [self createBundleNamed:@"Bare" info:info credits:nil];
    XCTAssertTrue(bundle != NULL);
    if (bundle == NULL)
        return;

    OMCShowAboutWindow(bundle);
    NSString *uuid = [self aboutWindowUUID];
    XCTAssertNotNil(uuid);
    XCTAssertEqualObjects([self valueOf:kNameID inWindow:uuid], @"Bare Applet");
    XCTAssertEqualObjects([self valueOf:kVersionID inWindow:uuid], @"Version 7");
    XCTAssertNil([self valueOf:kCreditsID inWindow:uuid], @"the credits area is taken out");
    XCTAssertNil([self valueOf:kCopyrightID inWindow:uuid], @"the copyright is taken out");
    XCTAssertNil([ActionUIObjCClass() getElementPropertyWithWindowUUID:uuid viewID:kIconID propertyName:@"filePath"], @"the icon is taken out");
    CFRelease(bundle);
}

- (void)testSameShortAndBuildVersionShowOnce
{
    NSDictionary *info = @{
        @"CFBundleIdentifier": @"com.abracode.test.about-same",
        @"CFBundleName": @"Same Applet",
        @"CFBundleShortVersionString": @"6.0.0",
        @"CFBundleVersion": @"6.0.0",
    };
    CFBundleRef bundle = [self createBundleNamed:@"Same" info:info credits:@"x"];
    XCTAssertTrue(bundle != NULL);
    if (bundle == NULL)
        return;
    OMCShowAboutWindow(bundle);
    NSString *uuid = [self aboutWindowUUID];
    XCTAssertEqualObjects([self valueOf:kVersionID inWindow:uuid], @"Version 6.0.0");
    CFRelease(bundle);
}

/// The content height of the About window for credits of this many paragraphs
- (CGFloat)windowHeightForParagraphs:(int)count
{
    NSMutableString *credits = [NSMutableString stringWithString:@"# Credits\n\n"];
    for (int i = 1; i <= count; i++)
        [credits appendFormat:@"Paragraph %d of the credits, long enough to wrap onto a second line in the window.\n\n", i];
    NSString *name = [NSString stringWithFormat:@"Credits%d", count];
    NSDictionary *info = @{
        @"CFBundleIdentifier": [@"com.abracode.test.about-" stringByAppendingString:name],
        @"CFBundleName": name,
        @"CFBundleVersion": @"1",
    };
    CFBundleRef bundle = [self createBundleNamed:name info:info credits:credits];
    XCTAssertTrue(bundle != NULL);
    if (bundle == NULL)
        return 0;
    OMCShowAboutWindow(bundle);
    NSWindow *window = [self windowWithUUID:[self aboutWindowUUID]];
    XCTAssertNotNil(window);
    CGFloat height = window.contentView.frame.size.height;
    OMCCloseAboutWindow();
    CFRelease(bundle);
    return height;
}

- (void)testCreditsAreaFitsShortCreditsAndScrollsLongOnes
{
    CGFloat shortHeight = [self windowHeightForParagraphs:1];
    CGFloat longHeight = [self windowHeightForParagraphs:15];
    CGFloat longerHeight = [self windowHeightForParagraphs:40];
    XCTAssertGreaterThan(shortHeight, 0);
    XCTAssertLessThan(shortHeight, longHeight, @"the area fits short credits");
    XCTAssertEqualWithAccuracy(longHeight, longerHeight, 0.5, @"long credits scroll in an area of capped height");
}

- (void)testMenuBarAboutItemOpensTheWindow
{
    OMCMainMenuController *controller = [[OMCMainMenuController alloc] init];
    NSMenu *savedMenu = [NSApp mainMenu];
    XCTAssertTrue([controller installMenuBar]);
    NSMenuItem *about = nil;
    for (NSMenuItem *item in [[[NSApp mainMenu] itemAtIndex:0] submenu].itemArray) {
        if ([item.identifier isEqualToString:@"about"])
            about = item;
    }
    XCTAssertNotNil(about);
    XCTAssertEqual(about.target, controller);
    XCTAssertEqual(about.action, @selector(showAbout:));

    [NSApp sendAction:about.action to:about.target from:about];
    XCTAssertNotNil([self aboutWindowUUID], @"the main bundle's About window");
    [NSApp setMainMenu:savedMenu];
}

@end

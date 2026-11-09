//
//  OMCAEContextTests.m
//  AbracodeTests
//
//  Pin tests for the Apple event context API in OMC.h (OMCExamineContextAE, OMCRunCommandAE), the path
//  the contextual menu plugin uses (loaded by Shortcuts.app) and that Phase 5 step 6 moves to
//  EntryPoints/Apple (Private/phase5-interfaces-design.md). Written against the code before the move:
//  which commands a file, text or null context offers in the menu, how the menu nests submenus, and
//  what a command receives from a file or text context.
//

#import <XCTest/XCTest.h>
#import <Carbon/Carbon.h>
#import "OMC.h"
#import "OMCTestCase.h"

static const NSTimeInterval kAEContextTestTimeout = 10.0;

@interface OMCAEContextTests : OMCTestCase
@property (nonatomic, strong) NSString *outputPath;
@property (nonatomic, strong) NSString *tempFolder;
@end

@implementation OMCAEContextTests

- (void)setUp
{
    [super setUp];
    self.tempFolder = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"OMCAEContextTests-%@", [NSUUID UUID].UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempFolder withIntermediateDirectories:YES attributes:nil error:nil];
    self.outputPath = [self.tempFolder stringByAppendingPathComponent:@"output.txt"];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:self.tempFolder error:nil];
    [super tearDown];
}

#pragma mark - Commands and contexts

/// A command that appends its __OBJ_PATH__ or __OBJ_TEXT__ to the output file
- (NSDictionary *)command:(NSString *)name commandID:(NSString *)commandID activation:(NSString *)activation object:(NSString *)objectWord
{
    return @{
        @"NAME": name,
        @"COMMAND_ID": commandID,
        @"ACTIVATION_MODE": activation,
        @"EXECUTION_MODE": @"exe_shell_script",
        @"COMMAND": @[@"/usr/bin/printf '%s\\n' ", objectWord, [NSString stringWithFormat:@" >> '%@'", self.outputPath]],
    };
}

- (NSDictionary *)commandList
{
    NSMutableDictionary *nested = [[self command:@"Nested" commandID:@"ae.nested" activation:@"act_always" object:@"__OBJ_PATH__"] mutableCopy];
    nested[@"SUBMENU_NAME"] = @"Group";
    return @{
        @"VERSION": @2,
        @"COMMAND_LIST": @[
            [self command:@"File Command" commandID:@"ae.file" activation:@"act_file" object:@"__OBJ_PATH__"],
            [self command:@"Folder Command" commandID:@"ae.folder" activation:@"act_folder" object:@"__OBJ_PATH__"],
            [self command:@"File Or Folder Command" commandID:@"ae.fileorfolder" activation:@"act_file_or_folder" object:@"__OBJ_PATH__"],
            [self command:@"Text Command" commandID:@"ae.text" activation:@"act_selected_text" object:@"__OBJ_TEXT__"],
            [self command:@"Always Command" commandID:@"ae.always" activation:@"act_always" object:@"__OBJ_PATH__"],
            nested,
        ],
    };
}

- (NSString *)makeFile:(NSString *)name
{
    NSString *path = [self.tempFolder stringByAppendingPathComponent:name];
    [@"content" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return path;
}

/// A list of file URLs, as the Finder and Shortcuts.app hand them to a contextual menu plugin
static OSStatus CreateFileListDesc(NSArray<NSString *> *paths, AEDescList *outList)
{
    OSStatus err = AECreateList(NULL, 0, false, outList);
    if (err != noErr)
        return err;
    for (NSString *path in paths) {
        NSData *urlData = [[NSURL fileURLWithPath:path].absoluteString dataUsingEncoding:NSUTF8StringEncoding];
        err = AEPutPtr(outList, 0, typeFileURL, urlData.bytes, (Size)urlData.length);
        if (err != noErr)
            return err;
    }
    return noErr;
}

static OSStatus CreateTextDesc(NSString *text, AEDesc *outDesc)
{
    NSData *textData = [text dataUsingEncoding:NSUTF8StringEncoding];
    return AECreateDesc(typeUTF8Text, textData.bytes, (Size)textData.length, outDesc);
}

#pragma mark - Reading the menu

static NSString *MenuItemName(const AERecord *item)
{
    AEDesc nameDesc = {typeNull, NULL};
    if (AEGetKeyDesc(item, keyContextualMenuName, typeWildCard, &nameDesc) != noErr)
        return nil;
    NSString *name = nil;
    if (nameDesc.descriptorType == typeCFStringRef) {
        CFStringRef nameRef = NULL;
        if (AEGetDescData(&nameDesc, &nameRef, sizeof(nameRef)) == noErr && nameRef != NULL)
            name = [(__bridge NSString *)nameRef copy];
    } else {
        AEDesc textDesc = {typeNull, NULL};
        if (AECoerceDesc(&nameDesc, typeUTF8Text, &textDesc) == noErr) {
            Size size = AEGetDescDataSize(&textDesc);
            NSMutableData *bytes = [NSMutableData dataWithLength:(NSUInteger)size];
            AEGetDescData(&textDesc, bytes.mutableBytes, size);
            name = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
            AEDisposeDesc(&textDesc);
        }
    }
    AEDisposeDesc(&nameDesc);
    return name;
}

/// The menu as nested arrays: a name for an item, @{name: [...]} for a submenu
static NSArray *MenuContents(const AEDescList *menu)
{
    NSMutableArray *contents = [NSMutableArray array];
    long count = 0;
    if (AECountItems(menu, &count) != noErr)
        return contents;
    for (long i = 1; i <= count; i++) {
        AEKeyword keyword = 0;
        AERecord item = {typeNull, NULL};
        if (AEGetNthDesc(menu, i, typeAERecord, &keyword, &item) != noErr)
            continue;
        NSString *name = MenuItemName(&item);
        AEDescList submenu = {typeNull, NULL};
        if (AEGetKeyDesc(&item, keyContextualMenuSubmenu, typeAEList, &submenu) == noErr) {
            [contents addObject:@{ (name ?: @""): MenuContents(&submenu) }];
            AEDisposeDesc(&submenu);
        } else if (name != nil) {
            [contents addObject:name];
        }
        AEDisposeDesc(&item);
    }
    return contents;
}

/// The menu a fresh executor builds for the context
- (NSArray *)menuForContext:(const AEDesc *)context
{
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFDictionaryRef)[self commandList]);
    XCTAssertTrue(executor != NULL);
    AEDescList menu = {typeNull, NULL};
    AECreateList(NULL, 0, false, &menu);
    OSStatus err = OMCExamineContextAE(executor, kOmcUnspecifiedCommand, context, &menu);
    XCTAssertEqual(err, noErr);
    NSArray *contents = MenuContents(&menu);
    AEDisposeDesc(&menu);
    OMCReleaseExecutor(executor);
    return contents;
}

- (NSString *)waitForOutput
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:kAEContextTestTimeout];
    NSString *output = nil;
    while ([deadline timeIntervalSinceNow] > 0) {
        output = [NSString stringWithContentsOfFile:self.outputPath encoding:NSUTF8StringEncoding error:nil];
        if (output.length > 0)
            break;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return output;
}

#pragma mark - Menus

/// One file: the file, file-or-folder and always commands, and the submenu; not the folder or text ones.
- (void)testAFileContextOffersTheFileCommands
{
    AEDescList files = {typeNull, NULL};
    XCTAssertEqual(CreateFileListDesc(@[[self makeFile:@"one.txt"]], &files), noErr);
    NSArray *menu = [self menuForContext:&files];
    AEDisposeDesc(&files);
    NSArray *expected = @[@"File Command", @"File Or Folder Command", @"Always Command", @{@"Group": @[@"Nested"]}];
    XCTAssertEqualObjects(menu, expected);
}

/// One folder: the folder, file-or-folder and always commands.
- (void)testAFolderContextOffersTheFolderCommands
{
    NSString *folder = [self.tempFolder stringByAppendingPathComponent:@"folder"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    AEDescList files = {typeNull, NULL};
    XCTAssertEqual(CreateFileListDesc(@[folder], &files), noErr);
    NSArray *menu = [self menuForContext:&files];
    AEDisposeDesc(&files);
    NSArray *expected = @[@"Folder Command", @"File Or Folder Command", @"Always Command", @{@"Group": @[@"Nested"]}];
    XCTAssertEqualObjects(menu, expected);
}

/// Selected text: the text and always commands.
- (void)testATextContextOffersTheTextCommands
{
    AEDesc text = {typeNull, NULL};
    XCTAssertEqual(CreateTextDesc(@"selected words", &text), noErr);
    NSArray *menu = [self menuForContext:&text];
    AEDisposeDesc(&text);
    NSArray *expected = @[@"Text Command", @"Always Command", @{@"Group": @[@"Nested"]}];
    XCTAssertEqualObjects(menu, expected);
}

/// No context: only the always commands.
- (void)testANullContextOffersTheAlwaysCommands
{
    AEDesc nothing = {typeNull, NULL};
    NSArray *menu = [self menuForContext:&nothing];
    NSArray *expected = @[@"Always Command", @{@"Group": @[@"Nested"]}];
    XCTAssertEqualObjects(menu, expected);
}

#pragma mark - Running with a context

/// OMCRunCommandAE with a file list hands the command the file's path.
- (void)testRunningWithAFileContextPassesThePath
{
    NSString *path = [self makeFile:@"two.txt"];
    AEDescList files = {typeNull, NULL};
    XCTAssertEqual(CreateFileListDesc(@[path], &files), noErr);
    OSStatus err = OMCRunCommandAE((__bridge CFDictionaryRef)[self commandList], CFSTR("ae.file"), &files);
    AEDisposeDesc(&files);
    XCTAssertEqual(err, noErr);
    NSString *output = [[self waitForOutput] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    XCTAssertEqualObjects(output.stringByResolvingSymlinksInPath, path.stringByResolvingSymlinksInPath);
}

/// OMCRunCommandAE with text hands the command the text.
- (void)testRunningWithATextContextPassesTheText
{
    AEDesc text = {typeNull, NULL};
    XCTAssertEqual(CreateTextDesc(@"hello there", &text), noErr);
    OSStatus err = OMCRunCommandAE((__bridge CFDictionaryRef)[self commandList], CFSTR("ae.text"), &text);
    AEDisposeDesc(&text);
    XCTAssertEqual(err, noErr);
    NSString *output = [[self waitForOutput] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    XCTAssertEqualObjects(output, @"hello there");
}

@end

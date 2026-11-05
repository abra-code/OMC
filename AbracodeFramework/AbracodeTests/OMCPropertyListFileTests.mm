//
//  OMCPropertyListFileTests.mm
//  AbracodeTests
//
//  Common/ACFPropertyList.cpp reads and writes property list and JSON files for the framework and
//  plister with POSIX calls instead of NSData. Its atomic write must leave the file system as
//  NSData writeToURL:options:NSDataWritingAtomic did (modes, links, failures), so each test sets
//  up the same situation twice and lets NSData write one copy and WritePropertyList the other.
//
//  The functions are not exported from Abracode.framework, so the source compiles into this
//  bundle (ACFJSON.cpp comes in through OMCJSONFoundationParityTests, ACFPath.cpp through
//  OMCTestsACFPath.cpp).
//

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include <unistd.h>

#include "../../Common/ACFPropertyList.cpp"

@interface OMCPropertyListFileTests : XCTestCase
@property (nonatomic, copy) NSString *root;
@end

@implementation OMCPropertyListFileTests

- (void)setUp
{
    [super setUp];
    char pattern[PATH_MAX];
    snprintf(pattern, sizeof(pattern), "%sOMCPropertyListFileTests.XXXXXX", NSTemporaryDirectory().fileSystemRepresentation);
    XCTAssertTrue(mkdtemp(pattern) != NULL);
    self.root = [NSString stringWithUTF8String:pattern];
}

- (void)tearDown
{
    // folders made read-only by a test must be writable again to be removed
    NSDirectoryEnumerator *walker = [[NSFileManager defaultManager] enumeratorAtPath:self.root];
    for(NSString *relative in walker)
        chmod([self.root stringByAppendingPathComponent:relative].fileSystemRepresentation, 0755);
    [[NSFileManager defaultManager] removeItemAtPath:self.root error:NULL];
    [super tearDown];
}

// One folder per writer, so both see the same starting state.
- (NSString *)folderFor:(NSString *)writer scenario:(NSString *)scenario
{
    NSString *folder = [[self.root stringByAppendingPathComponent:scenario] stringByAppendingPathComponent:writer];
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL]);
    return folder;
}

static void WriteText(NSString *path, NSString *text, mode_t mode)
{
    [text writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    chmod(path.fileSystemRepresentation, mode);
}

typedef void (^ScenarioSetup)(NSString *folder);

// What a write left behind, for comparing the two writers.
static NSString *Describe(NSString *folder, NSString *name, ino_t inodeBefore, BOOL succeeded)
{
    NSString *path = [folder stringByAppendingPathComponent:name];
    struct stat info;
    NSMutableString *result = [NSMutableString stringWithFormat:@"%@;", succeeded ? @"ok" : @"failed"];
    if(lstat(path.fileSystemRepresentation, &info) != 0)
    {
        [result appendString:@"missing"];
        return result;
    }
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    [result appendFormat:@"%s mode=%o newInode=%d content=%@", S_ISLNK(info.st_mode) ? "link" : "file", info.st_mode & 07777,
                         info.st_ino != inodeBefore, content];
    NSArray *others = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for(NSString *other in others)
    {
        if([other isEqualToString:name])
            continue;
        NSString *otherContent = [NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:other] encoding:NSUTF8StringEncoding error:NULL];
        [result appendFormat:@" | %@=%@", other, otherContent];
    }
    return result;
}

- (void)checkScenario:(NSString *)scenario name:(NSString *)name umask:(mode_t)mask setup:(ScenarioSetup)setup
{
    CFStringRef value = CFSTR("new");
    CFObj<CFDataRef> expectedBytes( ACFJSONCreateData(value, NULL) );

    NSMutableArray<NSString *> *outcomes = [NSMutableArray array];
    for(NSString *writer in @[@"foundation", @"ported"])
    {
        NSString *folder = [self folderFor:writer scenario:scenario];
        if(setup != nil)
            setup(folder);
        NSString *path = [folder stringByAppendingPathComponent:name];
        struct stat before;
        ino_t inodeBefore = (lstat(path.fileSystemRepresentation, &before) == 0) ? before.st_ino : 0;

        mode_t savedMask = umask(mask);
        BOOL succeeded = NO;
        if([writer isEqualToString:@"foundation"])
            succeeded = [(__bridge NSData *)expectedBytes.Get() writeToURL:[NSURL fileURLWithPath:path] options:NSDataWritingAtomic error:NULL];
        else
            succeeded = WritePropertyList(value, (__bridge CFURLRef)[NSURL fileURLWithPath:path], kACFPropertyListFormat_json);
        umask(savedMask);

        // a read-only folder is made writable again before looking, so stray files would show
        chmod(folder.fileSystemRepresentation, 0755);
        [outcomes addObject:Describe(folder, name, inodeBefore, succeeded)];
    }
    XCTAssertEqualObjects(outcomes[1], outcomes[0], @"%@: WritePropertyList differs from NSData", scenario);
}

- (void)testNewFileTakesTheUmask
{
    [self checkScenario:@"new022" name:@"x.json" umask:022 setup:nil];
    [self checkScenario:@"new077" name:@"x.json" umask:077 setup:nil];
}

- (void)testExistingFileKeepsItsMode
{
    [self checkScenario:@"existing0600" name:@"x.json" umask:022 setup:^(NSString *folder) {
        WriteText([folder stringByAppendingPathComponent:@"x.json"], @"old", 0600);
    }];
    [self checkScenario:@"existing0755" name:@"x.json" umask:022 setup:^(NSString *folder) {
        WriteText([folder stringByAppendingPathComponent:@"x.json"], @"old", 0755);
    }];
    // a write clears the set-user-ID bit, so the mode must be set after writing
    [self checkScenario:@"existing4755" name:@"x.json" umask:022 setup:^(NSString *folder) {
        WriteText([folder stringByAppendingPathComponent:@"x.json"], @"old", 04755);
    }];
}

// A name close to NAME_MAX: the temporary name must still fit.
- (void)testLongNameIsWritten
{
    NSString *longName = [[@"" stringByPaddingToLength:250 withString:@"a" startingAtIndex:0] stringByAppendingString:@".json"];
    [self checkScenario:@"longNew" name:longName umask:022 setup:nil];
    [self checkScenario:@"longExisting" name:longName umask:022 setup:^(NSString *folder) {
        WriteText([folder stringByAppendingPathComponent:longName], @"old", 0600);
    }];
}

- (void)testSymbolicLinkIsReplacedAndItsTargetKept
{
    [self checkScenario:@"symlink" name:@"link.json" umask:022 setup:^(NSString *folder) {
        WriteText([folder stringByAppendingPathComponent:@"target.json"], @"old", 0644);
        symlink("target.json", [folder stringByAppendingPathComponent:@"link.json"].fileSystemRepresentation);
    }];
}

- (void)testHardLinkIsBroken
{
    [self checkScenario:@"hardlink" name:@"x.json" umask:022 setup:^(NSString *folder) {
        NSString *path = [folder stringByAppendingPathComponent:@"x.json"];
        WriteText(path, @"old", 0644);
        link(path.fileSystemRepresentation, [folder stringByAppendingPathComponent:@"other.json"].fileSystemRepresentation);
    }];
}

- (void)testReadOnlyFolderFailsAndLeavesNothing
{
    [self checkScenario:@"readonly" name:@"x.json" umask:022 setup:^(NSString *folder) {
        WriteText([folder stringByAppendingPathComponent:@"x.json"], @"old", 0644);
        chmod(folder.fileSystemRepresentation, 0555);
    }];
}

- (void)testMissingFolderFails
{
    [self checkScenario:@"missing" name:@"nofolder/x.json" umask:022 setup:nil];
}

// Reading: the format comes from the extension, or the content when the extension says nothing;
// a folder or a missing file gives NULL with the extension's format.
- (void)testReadingFormatsAndFailures
{
    NSString *json = [self.root stringByAppendingPathComponent:@"a.json"];
    WriteText(json, @"{\"k\":[1,2.5,\"s\"]}", 0644);
    NSString *xml = [self.root stringByAppendingPathComponent:@"a.plist"];
    [[NSPropertyListSerialization dataWithPropertyList:@{@"k": @1} format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL] writeToFile:xml atomically:NO];
    NSString *binary = [self.root stringByAppendingPathComponent:@"b.plist"];
    [[NSPropertyListSerialization dataWithPropertyList:@{@"k": @1} format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL] writeToFile:binary atomically:NO];
    NSString *jsonOther = [self.root stringByAppendingPathComponent:@"c.pkgproj"];
    WriteText(jsonOther, @"[true]", 0644);
    NSString *oldStyle = [self.root stringByAppendingPathComponent:@"d.strings"];
    WriteText(oldStyle, @"{ k = v; }", 0644);
    NSString *folder = [self.root stringByAppendingPathComponent:@"e.json"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:NO attributes:nil error:NULL];
    NSString *linked = [self.root stringByAppendingPathComponent:@"f.json"];
    symlink("a.json", linked.fileSystemRepresentation);
    NSString *fifo = [self.root stringByAppendingPathComponent:@"g.json"];//NSData refused it at once; open() alone would wait
    XCTAssertEqual(mkfifo(fifo.fileSystemRepresentation, 0644), 0);

    struct { NSString *path; ACFPropertyListFormat format; BOOL readable; } cases[] = {
        { json, kACFPropertyListFormat_json, YES }, { xml, kACFPropertyListFormat_xml, YES },
        { binary, kACFPropertyListFormat_binary, YES }, { jsonOther, kACFPropertyListFormat_json, YES },
        { oldStyle, kACFPropertyListFormat_xml, YES }, { folder, kACFPropertyListFormat_json, NO },
        { linked, kACFPropertyListFormat_json, YES }, { fifo, kACFPropertyListFormat_json, NO },
        { [self.root stringByAppendingPathComponent:@"missing.plist"], kACFPropertyListFormat_xml, NO },
        { [self.root stringByAppendingPathComponent:@"missing.other"], kACFPropertyListFormat_xml, NO },
    };
    for(size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++)
    {
        ACFPropertyListFormat format = kACFPropertyListFormat_unknown;
        CFObj<CFPropertyListRef> value( CreatePropertyListAndFormat((__bridge CFURLRef)[NSURL fileURLWithPath:cases[i].path],
                                                              kCFPropertyListImmutable, &format) );
        XCTAssertEqual(value != NULL, (bool)cases[i].readable, @"%@", cases[i].path.lastPathComponent);
        XCTAssertEqual(format, cases[i].format, @"%@", cases[i].path.lastPathComponent);
    }

    // a URL that is not a file URL reads as missing, though CF gives its path
    NSURL *httpURL = [NSURL URLWithString:[@"http://localhost" stringByAppendingString:json]];
    CFObj<CFPropertyListRef> httpValue( CreatePropertyList((__bridge CFURLRef)httpURL, kCFPropertyListImmutable) );
    XCTAssertTrue(httpValue == NULL);

    // mutable containers when asked: the result can be changed in place
    CFObj<CFPropertyListRef> mutableValue( CreatePropertyList((__bridge CFURLRef)[NSURL fileURLWithPath:json], kCFPropertyListMutableContainers) );
    XCTAssertTrue(mutableValue != NULL);
    if(mutableValue != NULL)
    {
        CFDictionarySetValue((CFMutableDictionaryRef)mutableValue.Get(), CFSTR("added"), kCFBooleanTrue);
        CFArrayAppendValue((CFMutableArrayRef)CFDictionaryGetValue((CFDictionaryRef)mutableValue.Get(), CFSTR("k")), kCFNull);
        XCTAssertEqual(CFArrayGetCount((CFArrayRef)CFDictionaryGetValue((CFDictionaryRef)mutableValue.Get(), CFSTR("k"))), 4);
    }
}

// Writing a value JSON cannot hold fails and leaves no file.
- (void)testWritingUnrepresentableValueFails
{
    NSString *path = [self.root stringByAppendingPathComponent:@"bad.json"];
    XCTAssertFalse(WritePropertyList((__bridge CFPropertyListRef)@{@"d": [NSDate date]}, (__bridge CFURLRef)[NSURL fileURLWithPath:path], kACFPropertyListFormat_json));
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:path]);
    NSArray *left = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.root error:NULL];
    XCTAssertEqual(left.count, (NSUInteger)0, @"%@", left);
}

@end

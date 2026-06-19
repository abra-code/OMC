//
//  OMCEngineTempDirTests.m
//  AbracodeTests
//
//  Unit tests for Common/OMCEngineTempDir.h - the single source of truth for the engine's
//  private IPC directory and file paths shared between Abracode.framework and the helper
//  tools (omc_dialog_control, omc_next_command). This is the H2 security fix: the engine's
//  IPC files moved off the world-writable /tmp/OMC (0777, no sticky bit) to the per-user
//  temp dir ($TMPDIR/OMC, 0700).
//
//  The header is pure C static-inline, so it compiles directly into this test bundle - no
//  framework linkage is required (and these symbols are not exported anyway).
//

#import <XCTest/XCTest.h>
#import <sys/stat.h>
#import <unistd.h>
#import <stdlib.h>

#import "OMCEngineTempDir.h"

@interface OMCEngineTempDirTests : XCTestCase
@property (nonatomic, copy) NSString *savedTMPDIR;   // nil means TMPDIR was unset
@property (nonatomic, copy) NSString *sandboxDir;    // a unique throwaway temp root for tests that override TMPDIR
@end

@implementation OMCEngineTempDirTests

- (void)setUp {
    [super setUp];

    // Preserve the real TMPDIR so tests that override it cannot leak into other tests.
    const char *tmp = getenv("TMPDIR");
    self.savedTMPDIR = (tmp != NULL) ? [NSString stringWithUTF8String:tmp] : nil;

    // A fresh, empty directory we fully control. Created under the ORIGINAL per-user temp dir
    // (not the about-to-be-overridden TMPDIR) so it is always private and writable.
    NSString *base = NSTemporaryDirectory();
    NSString *templ = [base stringByAppendingPathComponent:@"OMCEngineTempDirTests.XXXXXX"];
    char templBuf[PATH_MAX];
    [templ getFileSystemRepresentation:templBuf maxLength:sizeof(templBuf)];
    char *made = mkdtemp(templBuf);
    XCTAssertTrue(made != NULL, @"mkdtemp should create a unique test directory");
    self.sandboxDir = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:templBuf length:strlen(templBuf)];
}

- (void)tearDown {
    // Restore TMPDIR exactly as it was.
    if (self.savedTMPDIR != nil)
        setenv("TMPDIR", self.savedTMPDIR.UTF8String, 1);
    else
        unsetenv("TMPDIR");

    if (self.sandboxDir != nil)
        [[NSFileManager defaultManager] removeItemAtPath:self.sandboxDir error:nil];

    [super tearDown];
}

// MARK: - OMCGetUserTempDir

- (void)testUserTempDirHonorsTMPDIR {
    setenv("TMPDIR", self.sandboxDir.UTF8String, 1);

    char buf[PATH_MAX] = {0};
    bool ok = OMCGetUserTempDir(buf, sizeof(buf));

    XCTAssertTrue(ok, @"Should resolve a temp dir");
    XCTAssertEqualObjects(@(buf), self.sandboxDir, @"Should return $TMPDIR verbatim");
}

- (void)testUserTempDirStripsTrailingSlashes {
    NSString *withSlashes = [self.sandboxDir stringByAppendingString:@"///"];
    setenv("TMPDIR", withSlashes.UTF8String, 1);

    char buf[PATH_MAX] = {0};
    bool ok = OMCGetUserTempDir(buf, sizeof(buf));

    XCTAssertTrue(ok);
    XCTAssertEqualObjects(@(buf), self.sandboxDir,
                          @"Trailing slashes must be stripped for consistent path building");
}

- (void)testUserTempDirFallsBackToConfstrWhenTMPDIRUnset {
    unsetenv("TMPDIR");

    char buf[PATH_MAX] = {0};
    bool ok = OMCGetUserTempDir(buf, sizeof(buf));
    XCTAssertTrue(ok, @"Should fall back when TMPDIR is unset");

    // Expected = confstr(_CS_DARWIN_USER_TEMP_DIR) with any trailing slash stripped.
    char confBuf[PATH_MAX] = {0};
    size_t n = confstr(_CS_DARWIN_USER_TEMP_DIR, confBuf, sizeof(confBuf));
    XCTAssertGreaterThan(n, (size_t)0, @"Platform should provide a per-user temp dir");
    NSString *expected = @(confBuf);
    while ([expected hasSuffix:@"/"] && expected.length > 1)
        expected = [expected substringToIndex:expected.length - 1];

    XCTAssertEqualObjects(@(buf), expected, @"Fallback should match the canonical per-user temp dir");
}

- (void)testUserTempDirRejectsTooSmallBuffer {
    setenv("TMPDIR", self.sandboxDir.UTF8String, 1);

    char tiny[4] = {0};   // far smaller than any real temp path
    bool ok = OMCGetUserTempDir(tiny, sizeof(tiny));
    XCTAssertFalse(ok, @"Must refuse rather than truncate/overflow when the buffer is too small");
}

- (void)testUserTempDirRejectsNullOrZeroBuffer {
    char buf[PATH_MAX] = {0};
    XCTAssertFalse(OMCGetUserTempDir(NULL, sizeof(buf)), @"NULL buffer must be rejected");
    XCTAssertFalse(OMCGetUserTempDir(buf, 0), @"Zero size must be rejected");
}

// MARK: - OMCGetEngineTempFilePath

- (void)testEngineTempFilePathBuildsUnderOMCSubdir {
    setenv("TMPDIR", self.sandboxDir.UTF8String, 1);

    char path[PATH_MAX] = {0};
    bool ok = OMCGetEngineTempFilePath("ABC123.id", false /*reader: do not create*/, path, sizeof(path));

    XCTAssertTrue(ok);
    NSString *expected = [self.sandboxDir stringByAppendingPathComponent:@"OMC/ABC123.id"];
    XCTAssertEqualObjects(@(path), expected, @"Path must be <tmpdir>/OMC/<leaf>");
}

- (void)testReaderDoesNotCreateDir {
    setenv("TMPDIR", self.sandboxDir.UTF8String, 1);

    char path[PATH_MAX] = {0};
    bool ok = OMCGetEngineTempFilePath("x.plist", false /*reader*/, path, sizeof(path));
    XCTAssertTrue(ok);

    NSString *omcDir = [self.sandboxDir stringByAppendingPathComponent:@"OMC"];
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:omcDir];
    XCTAssertFalse(exists, @"Readers (inCreateDir=false) must not create the OMC directory");
}

- (void)testWriterCreatesPrivateDir0700 {
    setenv("TMPDIR", self.sandboxDir.UTF8String, 1);

    NSString *omcDir = [self.sandboxDir stringByAppendingPathComponent:@"OMC"];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:omcDir],
                   @"Precondition: OMC dir should not exist yet");

    char path[PATH_MAX] = {0};
    bool ok = OMCGetEngineTempFilePath("y.id", true /*writer: create*/, path, sizeof(path));
    XCTAssertTrue(ok);

    struct stat st = {0};
    int rc = stat(omcDir.fileSystemRepresentation, &st);
    XCTAssertEqual(rc, 0, @"OMC dir should have been created");
    XCTAssertTrue(S_ISDIR(st.st_mode), @"OMC path should be a directory");

    // The whole point of the H2 fix: the directory is private to the current user.
    XCTAssertEqual(st.st_mode & S_IRWXU, (mode_t)S_IRWXU, @"Owner must have rwx");
    XCTAssertEqual(st.st_mode & (S_IRWXG | S_IRWXO), (mode_t)0,
                   @"Group/other must have NO access (not world-writable like the old /tmp/OMC)");
}

- (void)testWriterIsIdempotentWhenDirExists {
    setenv("TMPDIR", self.sandboxDir.UTF8String, 1);

    char path1[PATH_MAX] = {0};
    char path2[PATH_MAX] = {0};
    XCTAssertTrue(OMCGetEngineTempFilePath("a.id", true, path1, sizeof(path1)));
    // Second call with the dir already present must still succeed (mkdir EEXIST is ignored).
    XCTAssertTrue(OMCGetEngineTempFilePath("b.id", true, path2, sizeof(path2)));
}

- (void)testReaderAndWriterResolveSamePath {
    setenv("TMPDIR", self.sandboxDir.UTF8String, 1);

    // This is the core engine-IPC contract: the writer tool (create=true) and the framework
    // reader (create=false) must compute the identical path for the same leaf name.
    char writerPath[PATH_MAX] = {0};
    char readerPath[PATH_MAX] = {0};
    XCTAssertTrue(OMCGetEngineTempFilePath("DEADBEEF.plist", true,  writerPath, sizeof(writerPath)));
    XCTAssertTrue(OMCGetEngineTempFilePath("DEADBEEF.plist", false, readerPath, sizeof(readerPath)));

    XCTAssertEqual(strcmp(writerPath, readerPath), 0,
                   @"Writer and reader must agree on the exact IPC file path");
}

- (void)testEngineTempFilePathRejectsNullArgs {
    char path[PATH_MAX] = {0};
    XCTAssertFalse(OMCGetEngineTempFilePath(NULL, false, path, sizeof(path)), @"NULL leaf rejected");
    XCTAssertFalse(OMCGetEngineTempFilePath("x.id", false, NULL, sizeof(path)), @"NULL out buffer rejected");
    XCTAssertFalse(OMCGetEngineTempFilePath("x.id", false, path, 0), @"Zero size rejected");
}

- (void)testEngineTempFilePathRejectsTooSmallBuffer {
    setenv("TMPDIR", self.sandboxDir.UTF8String, 1);

    char tiny[8] = {0};
    bool ok = OMCGetEngineTempFilePath("some_long_leaf_name.plist", false, tiny, sizeof(tiny));
    XCTAssertFalse(ok, @"Must refuse rather than truncate when the result does not fit");
}

@end

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

// MARK: - The private OMC folder (decided 2026-11-09, linux_port_plan_review.md D5)

// A folder at sandbox/<name> with the given mode (after the umask, set exactly with chmod)
- (NSString *)makeFolder:(NSString *)name mode:(mode_t)mode {
    NSString *path = [self.sandboxDir stringByAppendingPathComponent:name];
    XCTAssertEqual(mkdir(path.fileSystemRepresentation, S_IRWXU), 0);
    XCTAssertEqual(chmod(path.fileSystemRepresentation, mode), 0);
    return path;
}

- (void)testPrivateDirectoryCheck {
    XCTAssertTrue(OMCIsPrivateDirectory(self.sandboxDir.fileSystemRepresentation), @"mkdtemp's 0700 folder is private");
    XCTAssertFalse(OMCIsPrivateDirectory([self makeFolder:@"group" mode:0750].fileSystemRepresentation), @"group may enter");
    XCTAssertFalse(OMCIsPrivateDirectory([self makeFolder:@"others" mode:0701].fileSystemRepresentation), @"others may enter");
    NSString *file = [self.sandboxDir stringByAppendingPathComponent:@"file"];
    [@"x" writeToFile:file atomically:NO encoding:NSUTF8StringEncoding error:nil];
    XCTAssertEqual(chmod(file.fileSystemRepresentation, 0600), 0);
    XCTAssertFalse(OMCIsPrivateDirectory(file.fileSystemRepresentation), @"a file is not a folder");
    XCTAssertFalse(OMCIsPrivateDirectory([self.sandboxDir stringByAppendingPathComponent:@"missing"].fileSystemRepresentation));
    NSString *link = [self.sandboxDir stringByAppendingPathComponent:@"link"];
    XCTAssertEqual(symlink(self.sandboxDir.fileSystemRepresentation, link.fileSystemRepresentation), 0);
    XCTAssertFalse(OMCIsPrivateDirectory(link.fileSystemRepresentation), @"a link to a private folder is not one");
    XCTAssertFalse(OMCIsPrivateDirectory([link stringByAppendingString:@"/"].UTF8String), @"nor with a trailing slash, which lstat would follow");
    XCTAssertTrue(OMCIsPrivateDirectory([self.sandboxDir stringByAppendingString:@"/"].UTF8String), @"a private folder with a trailing slash (as confstr gives it) is one");
}

// The Linux temporary folder's check (the call is plain POSIX, so it runs here): the path it gives
// back is the resolved one it checked, never the one asked about with its links
- (void)testResolvePrivateDirectoryOnSafePath {
    char expected[PATH_MAX] = {0};
    XCTAssertTrue(realpath(self.sandboxDir.fileSystemRepresentation, expected) != NULL);
    char resolved[PATH_MAX] = {0};
    XCTAssertTrue(OMCResolvePrivateDirectoryOnSafePath(self.sandboxDir.fileSystemRepresentation, resolved, sizeof(resolved)),
                  @"the test folder (0700, under the user's temporary folder) is private on a safe path");
    XCTAssertEqual(strcmp(resolved, expected), 0, @"the resolved path comes back: %s, not %s", resolved, expected);
    if ([self.sandboxDir hasPrefix:@"/var/"])
        XCTAssertTrue(strncmp(resolved, "/private/var/", 13) == 0, @"/var is a link to private/var; it is resolved: %s", resolved);

    // Through a link of our own: the folder linked to comes back
    NSString *target = [self makeFolder:@"target" mode:0700];
    NSString *link = [self.sandboxDir stringByAppendingPathComponent:@"tolink"];
    XCTAssertEqual(symlink(target.fileSystemRepresentation, link.fileSystemRepresentation), 0);
    char targetResolved[PATH_MAX] = {0};
    XCTAssertTrue(realpath(target.fileSystemRepresentation, targetResolved) != NULL);
    XCTAssertTrue(OMCResolvePrivateDirectoryOnSafePath(link.fileSystemRepresentation, resolved, sizeof(resolved)));
    XCTAssertEqual(strcmp(resolved, targetResolved), 0, @"a link gives back the folder it leads to: %s", resolved);

    // Refused, with "" given back: not private; under a folder others may write; no room
    XCTAssertFalse(OMCResolvePrivateDirectoryOnSafePath([self makeFolder:@"open" mode:0750].fileSystemRepresentation, resolved, sizeof(resolved)));
    XCTAssertEqual(resolved[0], '\0');
    NSString *shared = [self makeFolder:@"shared" mode:0777];
    NSString *inner = [shared stringByAppendingPathComponent:@"inner"];
    XCTAssertEqual(mkdir(inner.fileSystemRepresentation, S_IRWXU), 0);
    XCTAssertTrue(OMCIsPrivateDirectory(inner.fileSystemRepresentation), @"the inner folder itself is private");
    XCTAssertFalse(OMCResolvePrivateDirectoryOnSafePath(inner.fileSystemRepresentation, resolved, sizeof(resolved)),
                   @"but anyone may replace it through the folder above");
    XCTAssertEqual(resolved[0], '\0');
    char tiny[4] = {'x', 'x', 'x', 0};
    XCTAssertFalse(OMCResolvePrivateDirectoryOnSafePath(self.sandboxDir.fileSystemRepresentation, tiny, sizeof(tiny)), @"no room: refused, not cut short");
    XCTAssertEqual(tiny[0], '\0');
}

- (void)testAnOMCFolderOthersCanEnterIsRefused {
    setenv("TMPDIR", self.sandboxDir.UTF8String, 1);
    [self makeFolder:@"OMC" mode:0755];

    char path[PATH_MAX] = {0};
    XCTAssertFalse(OMCGetEngineTempFilePath("w.id", true /*writer*/, path, sizeof(path)), @"a writer must not use it");
    XCTAssertFalse(OMCGetEngineTempFilePath("r.plist", false /*reader*/, path, sizeof(path)), @"a reader must not use it");
}

- (void)testAnOMCSymbolicLinkIsRefused {
    setenv("TMPDIR", self.sandboxDir.UTF8String, 1);
    NSString *elsewhere = [self makeFolder:@"elsewhere" mode:0700];
    NSString *link = [self.sandboxDir stringByAppendingPathComponent:@"OMC"];
    XCTAssertEqual(symlink(elsewhere.fileSystemRepresentation, link.fileSystemRepresentation), 0);

    char path[PATH_MAX] = {0};
    XCTAssertFalse(OMCGetEngineTempFilePath("w.id", true /*writer*/, path, sizeof(path)), @"a writer must not follow the link");
    XCTAssertFalse(OMCGetEngineTempFilePath("r.plist", false /*reader*/, path, sizeof(path)), @"a reader must not follow the link");
}

- (void)testTheTwoMacOSOrders {
    // Engine files: $TMPDIR first (children inherit it; a sandboxed app's container temp).
    // Files another app reads (Terminal's environment script): the user's own temp folder first.
    setenv("TMPDIR", self.sandboxDir.UTF8String, 1);
    char engineDir[PATH_MAX] = {0};
    char otherAppsDir[PATH_MAX] = {0};
    XCTAssertTrue(OMCPlatformUserTempDir(engineDir, sizeof(engineDir)));
    XCTAssertTrue(OMCPlatformUserTempDirForOtherApps(otherAppsDir, sizeof(otherAppsDir)));
    XCTAssertEqualObjects(@(engineDir), self.sandboxDir);

    char confBuf[PATH_MAX] = {0};
    size_t n = confstr(_CS_DARWIN_USER_TEMP_DIR, confBuf, sizeof(confBuf));
    XCTAssertTrue((n > 0) && (n <= sizeof(confBuf)));
    XCTAssertEqualObjects(@(otherAppsDir), @(confBuf));
}

@end

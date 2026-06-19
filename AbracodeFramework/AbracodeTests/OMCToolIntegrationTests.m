//
//  OMCToolIntegrationTests.m
//  AbracodeTests
//
//  Integration tests that drive OMCCommandExecutor with real Command.plist commands which
//  invoke the bundled helper CLI tools (in Abracode.framework/Versions/A/Support, exported to
//  scripts as $OMC_OMC_SUPPORT_PATH) and observe the effects of their execution.
//
//  Coverage target = the code paths touched by the 2026-06 security/correctness review:
//   - omc_next_command + OmcTaskManager::CopyNextCommandID (H2): dynamic command chaining now
//     uses the per-user temp dir ($TMPDIR/OMC/<guid>.id) instead of the world-writable /tmp/OMC.
//     The chaining test proves the writer (tool) and reader (engine) agree on that path end to end.
//   - plister "set" branch (L2), filt optional-subgroup handling (L3), b64 file read (L4),
//     pasteboard stdin reader (L4): exercised with valid inputs (the unbounded "too large data"
//     overflow guards are not reachable through normal input and are intentionally not tested here).
//

#import <XCTest/XCTest.h>
#import "OMCTestCase.h"          // kDefaultExecutionTimeout
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"

@interface OMCToolIntegrationTests : XCTestCase
@property (nonatomic, strong) NSMutableArray<NSURL *> *bundlesToCleanup;
@property (nonatomic, strong) NSMutableArray<NSString *> *pathsToCleanup;
@end

@implementation OMCToolIntegrationTests

- (void)setUp {
    [super setUp];
    self.bundlesToCleanup = [NSMutableArray array];
    self.pathsToCleanup = [NSMutableArray array];
}

- (void)tearDown {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSURL *bundleURL in self.bundlesToCleanup)
        [OMCBundleTestHelper removeTestBundle:bundleURL];
    for (NSString *path in self.pathsToCleanup)
        [fm removeItemAtPath:path error:nil];
    [self.bundlesToCleanup removeAllObjects];
    [self.pathsToCleanup removeAllObjects];
    [super tearDown];
}

#pragma mark - Helpers

// Builds a bundle from inline shell commands and registers it for cleanup.
- (NSURL *)bundleNamed:(NSString *)name withCommands:(NSArray<NSDictionary *> *)commands {
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:name withCommands:commands scripts:@{}];
    XCTAssertNotNil(bundleURL, @"Should create test bundle %@", name);
    if (bundleURL != nil)
        [self.bundlesToCleanup addObject:bundleURL];
    return bundleURL;
}

// Runs a command by ID to completion and returns the captured stdout.
- (NSString *)runCommandID:(NSString *)commandID inBundle:(NSURL *)bundleURL {
    OMCTestExecutionObserver *observer = [OMCTestExecutionObserver new];
    OSStatus err = [OMCCommandExecutor runCommand:commandID
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:observer];
    XCTAssertEqual(err, noErr, @"Command '%@' should start", commandID);
    BOOL done = [observer waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(done, @"Command '%@' should finish within timeout", commandID);
    return observer.capturedOutput;
}

- (BOOL)pollForFileAtPath:(NSString *)path timeout:(NSTimeInterval)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    NSFileManager *fm = [NSFileManager defaultManager];
    while ([deadline timeIntervalSinceNow] > 0) {
        if ([fm fileExistsAtPath:path])
            return YES;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return [fm fileExistsAtPath:path];
}

- (NSString *)tempPathWithSuffix:(NSString *)suffix {
    NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"omc_tool_test_%@_%@", [[NSUUID UUID] UUIDString], suffix]];
    [self.pathsToCleanup addObject:p];
    return p;
}

#pragma mark - H2: omc_next_command dynamic chaining via the per-user temp dir

- (void)testNextCommandChainingExecutesTargetCommand {
    // chain_start writes a marker, then asks the engine (via omc_next_command) to run chain_target
    // next. omc_next_command writes $TMPDIR/OMC/<current-guid>.id; after chain_start finishes,
    // OmcTaskManager::CopyNextCommandID reads that exact path and runs chain_target. If the H2
    // writer/reader path contract were broken, chain_target would never run.
    NSString *startMarker = [self tempPathWithSuffix:@"start"];
    NSString *targetMarker = [self tempPathWithSuffix:@"target"];

    NSString *startCmd = [NSString stringWithFormat:
        @"echo started > '%@'; \"$OMC_OMC_SUPPORT_PATH/omc_next_command\" \"$OMC_CURRENT_COMMAND_GUID\" chain_target",
        startMarker];
    NSString *targetCmd = [NSString stringWithFormat:@"echo ran > '%@'", targetMarker];

    NSURL *bundleURL = [self bundleNamed:@"NextCommandChain" withCommands:@[
        @{ @"NAME": @"Chain Start",  @"COMMAND_ID": @"chain_start",  @"EXECUTION_MODE": @"exe_shell_script", @"COMMAND": @[startCmd] },
        @{ @"NAME": @"Chain Target", @"COMMAND_ID": @"chain_target", @"EXECUTION_MODE": @"exe_shell_script", @"COMMAND": @[targetCmd] },
    ]];
    if (bundleURL == nil) return;

    [self runCommandID:@"chain_start" inBundle:bundleURL];

    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertTrue([fm fileExistsAtPath:startMarker], @"chain_start should have run");
    XCTAssertTrue([self pollForFileAtPath:targetMarker timeout:kDefaultExecutionTimeout],
                  @"chain_target must run, proving omc_next_command -> engine IPC via $TMPDIR/OMC works end to end");
}

#pragma mark - L2: plister "set" branch

- (void)testPlisterSetThenGetRoundTrip {
    NSString *plistPath = [self tempPathWithSuffix:@"plist"];
    // Start from a valid empty-dict plist so /MyKey can be set on a dictionary root.
    XCTAssertTrue([@{} writeToURL:[NSURL fileURLWithPath:plistPath] atomically:YES],
                  @"Precondition: write empty dict plist");

    NSString *value = [NSString stringWithFormat:@"PlisterValue_%@", [[NSUUID UUID] UUIDString]];
    // 1) valid set (exercises the modified set branch with type+value present)
    // 2) truncated "set string" with no value (exercises the L2 argument-count guard; returns
    //    cleanly instead of reading past argv) - must not corrupt the plist
    // 3) get the value back
    NSString *cmd = [NSString stringWithFormat:
        @"\"$OMC_OMC_SUPPORT_PATH/plister\" set string '%@' '%@' /MyKey; "
        @"\"$OMC_OMC_SUPPORT_PATH/plister\" set string; "
        @"\"$OMC_OMC_SUPPORT_PATH/plister\" get value '%@' /MyKey",
        value, plistPath, plistPath];

    NSURL *bundleURL = [self bundleNamed:@"PlisterRoundTrip" withCommands:@[
        @{ @"NAME": @"Plister", @"COMMAND_ID": @"plister_cmd", @"EXECUTION_MODE": @"exe_shell_script", @"COMMAND": @[cmd] },
    ]];
    if (bundleURL == nil) return;

    NSString *output = [self runCommandID:@"plister_cmd" inBundle:bundleURL];
    XCTAssertTrue([output containsString:value],
                  @"plister get should return the value written by plister set (got: '%@')", output);
}

#pragma mark - L3: filt optional subgroup that does not participate

- (void)testFiltOptionalSubgroupNotPresent {
    // Regex (foo)?(bar): on input "bar", group 1 does not participate (rm_so == rm_eo == -1).
    // The replace string [\1][\2] references the missing group 1 and the present group 2.
    // Pre-fix this formed inputLine + (size_t)-1 (out of bounds); the L3 fix skips a group whose
    // offsets are negative, so the expected output is "[][bar]".
    NSString *cmd = @"echo 'bar' | \"$OMC_OMC_SUPPORT_PATH/filt\" '(foo)?(bar)' '[\\1][\\2]'";

    NSURL *bundleURL = [self bundleNamed:@"FiltSubgroup" withCommands:@[
        @{ @"NAME": @"Filt", @"COMMAND_ID": @"filt_cmd", @"EXECUTION_MODE": @"exe_shell_script", @"COMMAND": @[cmd] },
    ]];
    if (bundleURL == nil) return;

    NSString *output = [self runCommandID:@"filt_cmd" inBundle:bundleURL];
    XCTAssertTrue([output containsString:@"[][bar]"],
                  @"Optional non-participating subgroup must contribute nothing (got: '%@')", output);
}

- (void)testFiltPassThroughHandlesEmptyLine {
    // An empty line in the middle of the input exercises the lineLen > 0 guard. The filter
    // should pass the non-empty matching lines through without crashing.
    NSString *cmd = @"printf 'x\\n\\ny\\n' | \"$OMC_OMC_SUPPORT_PATH/filt\" 'x|y' '\\0'";

    NSURL *bundleURL = [self bundleNamed:@"FiltEmptyLine" withCommands:@[
        @{ @"NAME": @"Filt", @"COMMAND_ID": @"filt_cmd", @"EXECUTION_MODE": @"exe_shell_script", @"COMMAND": @[cmd] },
    ]];
    if (bundleURL == nil) return;

    NSString *output = [self runCommandID:@"filt_cmd" inBundle:bundleURL];
    XCTAssertTrue([output containsString:@"x"] && [output containsString:@"y"],
                  @"Both matching lines should pass through despite the empty line (got: '%@')", output);
}

#pragma mark - L4: b64 file read + decode round trip

- (void)testB64EncodeFileThenDecodeStdinRoundTrip {
    NSString *content = [NSString stringWithFormat:@"B64_%@", [[NSUUID UUID] UUIDString]];
    NSString *filePath = [self tempPathWithSuffix:@"b64in"];
    XCTAssertTrue([content writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil],
                  @"Precondition: write input file");

    NSString *expectedEncoded =
        [[content dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];

    // Encode the file (exercises the modified file-read path: ftell <= 0 / short-read checks),
    // then decode the result from stdin and confirm the round trip. Uses printf (not echo -n,
    // which /bin/sh prints literally) so the base64 piped to decode has no stray bytes.
    NSString *cmd = [NSString stringWithFormat:
        @"enc=$(\"$OMC_OMC_SUPPORT_PATH/b64\" encode file '%@'); echo \"ENC=$enc\"; "
        @"dec=$(printf '%%s' \"$enc\" | \"$OMC_OMC_SUPPORT_PATH/b64\" decode stdin); echo \"DEC=$dec\"",
        filePath];

    NSURL *bundleURL = [self bundleNamed:@"B64RoundTrip" withCommands:@[
        @{ @"NAME": @"B64", @"COMMAND_ID": @"b64_cmd", @"EXECUTION_MODE": @"exe_shell_script", @"COMMAND": @[cmd] },
    ]];
    if (bundleURL == nil) return;

    NSString *output = [self runCommandID:@"b64_cmd" inBundle:bundleURL];
    NSString *expectedEnc = [NSString stringWithFormat:@"ENC=%@", expectedEncoded];
    NSString *expectedDec = [NSString stringWithFormat:@"DEC=%@", content];
    XCTAssertTrue([output containsString:expectedEnc],
                  @"b64 encode file should match Foundation base64 (got: '%@')", output);
    XCTAssertTrue([output containsString:expectedDec],
                  @"b64 decode should round-trip back to the original file content (got: '%@')", output);
}

#pragma mark - L4: pasteboard stdin reader

- (void)testPasteboardStdinPutThenGet {
    // With no value argument, pasteboard reads the string from stdin (CreateCStringFromStdIn,
    // the function carrying the L4 overflow guard). Put to a private named pasteboard, then get.
    NSString *pbName = [NSString stringWithFormat:@"OMCToolTest_%@", [[NSUUID UUID] UUIDString]];
    NSString *value = [NSString stringWithFormat:@"PB_%@", [[NSUUID UUID] UUIDString]];

    // printf (not echo -n, which /bin/sh prints literally) feeds the exact value on stdin.
    NSString *cmd = [NSString stringWithFormat:
        @"printf '%%s' '%@' | \"$OMC_OMC_SUPPORT_PATH/pasteboard\" '%@' put; "
        @"got=$(\"$OMC_OMC_SUPPORT_PATH/pasteboard\" '%@' get); echo \"GOT=$got\"",
        value, pbName, pbName];

    NSURL *bundleURL = [self bundleNamed:@"PasteboardStdin" withCommands:@[
        @{ @"NAME": @"Pasteboard", @"COMMAND_ID": @"pb_cmd", @"EXECUTION_MODE": @"exe_shell_script", @"COMMAND": @[cmd] },
    ]];
    if (bundleURL == nil) return;

    NSString *output = [self runCommandID:@"pb_cmd" inBundle:bundleURL];
    NSString *expectedGot = [NSString stringWithFormat:@"GOT=%@", value];
    XCTAssertTrue([output containsString:expectedGot],
                  @"pasteboard should read the put value from stdin and return it on get (got: '%@')", output);
}

@end

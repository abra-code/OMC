//
//  OMCActionUIRemoteTests.m
//  AbracodeTests
//
//  The ActionUI remote bridge inside an OMC host: that a window starts it, that the endpoint
//  reaches a handler under all three variable names, and that a client on the other end of the
//  socket can read the window the engine just built.
//
//  Socket work runs on a background queue while the test pumps the main run loop. The server
//  hops every request to the main queue, so a blocking read on the main thread starves it and
//  every request comes back 1005 (main thread unavailable) instead of an answer.
//

#import "OMCTestCase.h"
#import "OMCCommandExecutor.h"
#import "OMCBundleTestHelper.h"
#import "OMCTestExecutionObserver.h"
#include "OMCEngineTempDir.h"
#include "OMCActionUIRemoteHost.h"

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

// enable only in OMC version 5.0 or later
#if CURRENT_OMC_VERSION >= 50000

@interface OMCActionUIRemoteTests : XCTestCase
@property (nonatomic, strong) NSMutableArray<NSURL *> *bundlesToCleanup;
@property (nonatomic, copy) NSString *cachedTestToken;
@end

@implementation OMCActionUIRemoteTests

- (void)setUp {
    [super setUp];
    self.bundlesToCleanup = [NSMutableArray array];
}

- (void)tearDown {
    if (self.cachedTestToken != nil) {
        OMCRevokeActionUIRemoteTokens(kTestTokenLabel);
        self.cachedTestToken = nil;
    }
    for (NSURL *url in self.bundlesToCleanup) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    }
    [super tearDown];
}

#pragma mark - Helpers

/// TEXT wrapped in single quotes for a /bin/sh command line, with embedded single quotes escaped
/// the only way sh allows: close, escape, reopen.
- (NSString *)shellQuoted:(NSString *)text {
    NSString *escaped = [text stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

/// The label this test case's own grant is registered under, so tearDown can withdraw exactly it.
static const char * const kTestTokenLabel = "AbracodeTests";

/// A token this test process may present. The host requires one - that is the whole point of the
/// bridge's access control - and the test process is NOT a process the host spawned, so it has no
/// token in its environment and no descriptor to read one from. It mints its own instead, which
/// is the same entry point the engine uses per command.
///
/// nil when no bridge is running; the caller then sends an unauthenticated request, which is the
/// right behavior for a test that has not opened a window yet.
- (NSString *)testToken {
    if (self.cachedTestToken != nil) {
        return self.cachedTestToken;
    }
    char token[kOMCActionUIRemoteTokenBufferSize];
    if (!OMCMintActionUIRemoteToken(kTestTokenLabel, token, sizeof(token))) {
        return nil;
    }
    self.cachedTestToken = [NSString stringWithUTF8String:token];
    memset(token, 0, sizeof(token));
    return self.cachedTestToken;
}

/// Add this test case's token to a request, unless the request already carries one of its own -
/// which is how the refusal tests present a wrong token deliberately.
///
/// Done by decoding and re-encoding rather than by splicing text, so that a request whose params
/// contain a brace or a quote cannot produce a line that happens to parse into something else.
- (NSString *)requestLineWithToken:(NSString *)requestLine {
    NSString *token = [self testToken];
    if (token.length == 0) {
        return requestLine;
    }

    NSData *data = [requestLine dataUsingEncoding:NSUTF8StringEncoding];
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        return requestLine;       // a batch or a deliberately malformed line: left exactly as written
    }

    NSMutableDictionary *request = parsed;
    NSMutableDictionary *params = [request[@"params"] isKindOfClass:[NSDictionary class]]
                                ? [request[@"params"] mutableCopy] : [NSMutableDictionary dictionary];
    if (params[@"token"] == nil) {
        params[@"token"] = token;
    }
    request[@"params"] = params;

    NSData *encoded = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    if (encoded == nil) {
        return requestLine;
    }
    return [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
}

/// The socket path this host must be serving on, built from the documented rule rather than read
/// back out of the engine: OMCGetEngineTempFilePath (a static inline, so no framework symbol is
/// involved) plus the per-process leaf name. Deriving it independently is what makes the
/// assertions below check the contract instead of comparing the engine to a mirror of itself.
- (NSString *)expectedEndpoint {
    char leafName[64];
    int leafLength = snprintf(leafName, sizeof(leafName), "aui-%d.sock", (int)getpid());
    XCTAssertTrue((leafLength > 0) && ((size_t)leafLength < sizeof(leafName)));

    char path[PATH_MAX];
    if (!OMCGetEngineTempFilePath(leafName, false, path, sizeof(path))) return nil;
    return [NSString stringWithUTF8String:path];
}

/// The bridge is up exactly when its socket file is on disk at that path.
- (NSString *)runningEndpoint {
    NSString *expected = [self expectedEndpoint];
    if (expected == nil) return nil;
    return [[NSFileManager defaultManager] fileExistsAtPath:expected] ? expected : nil;
}

/// Opens the ActionUI Form dialog and returns its window UUID. Opening any ActionUI window is
/// what starts the bridge, so every test that talks to the socket goes through here first.
- (NSString *)openFormDialogWithBundlePath:(NSString *)omcBundlePath {
    OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;
    OSStatus err = [OMCCommandExecutor runCommand:@"Form"
                                   forCommandFile:omcBundlePath
                                      withContext:[NSURL fileURLWithPath:NSHomeDirectory()]
                                     useNavDialog:NO
                             allowKeyWindowSubcommand:NO
                                         delegate:observer];
    XCTAssertEqual(err, noErr, @"Form command should start");
    XCTAssertTrue([observer waitForCompletionWithTimeout:kDefaultExecutionTimeout],
                  @"Form command should complete");

    NSString *uuid = [observer.capturedOutput
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    XCTAssertTrue(uuid.length > 0, @"Form should report its window UUID");
    return uuid;
}

/// Poll for a file, pumping the run loop. The init and terminate handlers are separate commands
/// with their own child scripts, so neither has run when the command that opened the window
/// returns; their diagnostic files are the only signal that they have.
- (BOOL)waitForFileAtPath:(NSString *)path timeout:(NSTimeInterval)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    NSFileManager *fm = [NSFileManager defaultManager];
    while (![fm fileExistsAtPath:path] && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return [fm fileExistsAtPath:path];
}

- (NSString *)reportPathForInitHandlerOfUUID:(NSString *)uuid {
    return [NSString stringWithFormat:@"/tmp/OMC_test_actionui_init_%@", uuid];
}

/// Both diagnostic files, on every exit path - the sibling suite leaves these behind and they
/// accumulate in /tmp across runs.
- (void)removeDiagnosticFilesForUUID:(NSString *)uuid {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *suffix in @[@"init", @"term"]) {
        NSString *path = [NSString stringWithFormat:@"/tmp/OMC_test_actionui_%@_%@", suffix, uuid];
        [fm removeItemAtPath:path error:nil];
        [fm removeItemAtPath:[path stringByAppendingString:@".tmp"] error:nil];
    }
}

- (void)closeFormDialogWithUUID:(NSString *)uuid bundlePath:(NSString *)omcBundlePath {
    OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;
    OSStatus err = [OMCCommandExecutor runCommand:@"form.close.window"
                                   forCommandFile:omcBundlePath
                                      withContext:uuid
                                     useNavDialog:NO
                             allowKeyWindowSubcommand:NO
                                         delegate:observer];
    XCTAssertEqual(err, noErr, @"form.close.window should start");
    [observer waitForCompletionWithTimeout:kDefaultExecutionTimeout];
}

/// One request, one reply, over a fresh connection. Returns the decoded JSON object, or nil.
///
/// The connect/write/read all happen on a background queue; the caller's thread (main, under
/// XCTest) pumps its run loop until the reply lands, which is what lets the server's main-queue
/// hop actually run.
- (NSDictionary *)sendJSONRPC:(NSString *)requestLine toEndpoint:(NSString *)endpoint {
    requestLine = [self requestLineWithToken:requestLine];
    __block NSData *replyData = nil;
    __block NSString *failure = nil;
    XCTestExpectation *done = [self expectationWithDescription:@"jsonrpc reply"];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0) {
            failure = [NSString stringWithFormat:@"socket() failed: %s", strerror(errno)];
            [done fulfill];
            return;
        }

        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        const char *path = [endpoint fileSystemRepresentation];
        if (strlen(path) >= sizeof(addr.sun_path)) {
            close(fd);
            failure = @"endpoint does not fit in sun_path";
            [done fulfill];
            return;
        }
        strlcpy(addr.sun_path, path, sizeof(addr.sun_path));

        // Without this the worker can sit in read() for the life of the process after the
        // expectation below times out, holding the fd and racing the main thread for replyData.
        struct timeval receiveTimeout = { .tv_sec = 8, .tv_usec = 0 };
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, sizeof(receiveTimeout));
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &receiveTimeout, sizeof(receiveTimeout));

        if (connect(fd, (struct sockaddr *)&addr, (socklen_t)SUN_LEN(&addr)) != 0) {
            failure = [NSString stringWithFormat:@"connect() failed: %s", strerror(errno)];
            close(fd);
            [done fulfill];
            return;
        }

        NSData *out = [[requestLine stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        const uint8_t *bytes = out.bytes;
        size_t remaining = out.length;
        while (remaining > 0) {
            ssize_t written = write(fd, bytes, remaining);
            if ((written < 0) && (errno == EINTR)) {
                continue;
            }
            if (written <= 0) {
                failure = [NSString stringWithFormat:@"write() failed: %s", strerror(errno)];
                close(fd);
                [done fulfill];
                return;
            }
            bytes += written;
            remaining -= (size_t)written;
        }

        // Read to the first newline: the protocol is one JSON object per line.
        NSMutableData *accumulated = [NSMutableData data];
        uint8_t buffer[4096];
        while (1) {
            ssize_t got = read(fd, buffer, sizeof(buffer));
            if (got <= 0) break;
            [accumulated appendBytes:buffer length:(NSUInteger)got];
            if (memchr(accumulated.bytes, '\n', accumulated.length) != NULL) break;
        }
        close(fd);
        replyData = accumulated;
        [done fulfill];
    });

    [self waitForExpectations:@[done] timeout:10.0];

    XCTAssertNil(failure, @"%@", failure);
    if (replyData.length == 0) return nil;

    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:replyData options:0 error:&error];
    XCTAssertNil(error, @"reply should be JSON: %@", error);
    return [parsed isKindOfClass:[NSDictionary class]] ? parsed : nil;
}

#pragma mark - The token on a descriptor

/// The engine hands every handler its own token on descriptor 3 and keeps it out of the
/// environment. These tests cover both halves independently, because either one alone would let
/// a naive test pass while the other is broken: the descriptor could be delivered while the
/// variable is still exported, or the variable could be gone with no descriptor to replace it.

- (void)testTheHostProcessHasNoTokenInItsEnvironmentOnceTheBridgeStarts {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:omcBundlePath];
    XCTAssertNotNil([self runningEndpoint], @"the bridge must be up, or this proves nothing");

    // CreateEnviron copies this process's environment into every handler, so a token here is a
    // token in every child - and a python3 child shows its environment to any same-uid `ps`.
    // getenv, not NSProcessInfo, whose environment dictionary is a snapshot taken at first use.
    XCTAssertEqual(getenv("ACTIONUI_REMOTE_TOKEN"), NULL,
                   @"starting the bridge must leave no token in the host's own environment");

    [self closeFormDialogWithUUID:uuid bundlePath:omcBundlePath];
    [self removeDiagnosticFilesForUUID:uuid];
}

- (void)testASpawnedHandlerSeesTheDescriptorAndNotTheToken {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:omcBundlePath];
    XCTAssertNotNil([self runningEndpoint]);

    // `env` rather than a shell expansion of each name, so that an unexpected THIRD spelling
    // would show up too.
    NSString *output = [self runProbeNamed:@"token_env_probe"
                             executionMode:@"exe_shell_script"
                                   command:@[@"env | grep '^ACTIONUI_REMOTE_TOKEN' | sort"]];

    XCTAssertEqualObjects(output, @"ACTIONUI_REMOTE_TOKEN_FD=3",
                          @"a handler gets the descriptor's number and nothing else; got: %@", output);

    [self closeFormDialogWithUUID:uuid bundlePath:omcBundlePath];
    [self removeDiagnosticFilesForUUID:uuid];
}

- (void)testTheModesThatCannotCarryADescriptorGetNoToken {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:omcBundlePath];
    XCTAssertNotNil([self runningEndpoint]);

    // exe_silent_system runs a bare system(), which takes neither an environment nor a descriptor
    // from the engine - so there is nowhere to put the token, and a handler in that mode is
    // refused with 1006. That is the bridge's reach and not a loss: reading window state out of
    // process is what the bridge newly adds, and no released build ever offered it from this
    // mode. Mutation from here still goes through omc_dialog_control, which needs no token.
    // Pinned so the boundary stays where it is by test, and in step with the bridge guide,
    // which names all four affected modes.
    //
    // COVERAGE, stated plainly because the guide names four modes and this exercises one.
    // exe_silent_system is the one that both spawns a process and can be driven from a test.
    // exe_applescript runs OSADoScript in-process and spawns nothing the engine configures, so
    // there is no environment to assert on - a `do shell script` probe would be measuring
    // AppleScript's own inheritance rules, not the engine's behavior. exe_terminal and
    // exe_iterm would launch Terminal or iTerm on the machine running the suite, which is not
    // something a test may do; their case rests on the token never entering the environment
    // DICTIONARY those modes serialize, which testASpawnedHandlerSeesTheDescriptorAndNotTheToken
    // asserts from the other side.
    //
    // Its output is discarded by the mode, so the handler reports through a file.
    NSString *reportPath = [NSString stringWithFormat:@"%@/omc_silent_token_%@",
                            NSTemporaryDirectory(), uuid];
    [[NSFileManager defaultManager] removeItemAtPath:reportPath error:nil];
    NSString *command = [NSString stringWithFormat:
                         @"env | grep -c '^ACTIONUI_REMOTE_TOKEN' > '%@' 2>&1 || true", reportPath];
    [self runProbeNamed:@"silent_token_probe" executionMode:@"exe_silent_system" command:@[command]];
    XCTAssertTrue([self waitForFileAtPath:reportPath timeout:5.0], @"the handler must have run");

    NSString *seen = [[NSString stringWithContentsOfFile:reportPath encoding:NSUTF8StringEncoding error:nil]
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    XCTAssertEqualObjects(seen, @"0",
                          @"exe_silent_system gets neither the token nor a descriptor; got '%@'", seen);
    [[NSFileManager defaultManager] removeItemAtPath:reportPath error:nil];

    // And the contrast, so this is not just an assertion that the probe produced nothing:
    // a mode that DOES spawn gets the descriptor.
    NSString *spawned = [self runProbeNamed:@"silent_token_contrast"
                              executionMode:@"exe_shell_script"
                                    command:@[@"env | grep -c '^ACTIONUI_REMOTE_TOKEN_FD='"]];
    XCTAssertEqualObjects(spawned, @"1", @"exe_shell_script does get one");

    [self closeFormDialogWithUUID:uuid bundlePath:omcBundlePath];
    [self removeDiagnosticFilesForUUID:uuid];
}

- (void)testTheTokenOnDescriptorThreeIsOneTheServerAccepts {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:omcBundlePath];
    NSString *endpoint = [self runningEndpoint];
    XCTAssertNotNil(endpoint);

    // The handler reads its own token off the descriptor and reports it, so that this test can
    // present exactly what the engine handed it. That the value leaves the handler at all is a
    // property of this test, not of the design: in production nothing prints it.
    NSString *handlerToken = [self runProbeNamed:@"token_fd_probe"
                                   executionMode:@"exe_shell_script"
                                         command:@[@"IFS= read -r t <&3; printf '%s' \"$t\""]];
    XCTAssertEqual(handlerToken.length, (NSUInteger)64,
                   @"32 bytes hex; got %lu characters: %@", (unsigned long)handlerToken.length, handlerToken);

    // The positive half first: a test that only checked the refusal would pass against a server
    // that refused everything.
    NSDictionary *accepted = [self sendJSONRPC:
        [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"actionui.hello\","
                                    "\"params\":{\"token\":\"%@\"}}", handlerToken]
                                    toEndpoint:endpoint];
    XCTAssertNil(accepted[@"error"], @"the handler's own token must authenticate: %@", accepted[@"error"]);
    XCTAssertNotNil(accepted[@"result"]);

    NSDictionary *refused = [self sendJSONRPC:
        @"{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"actionui.hello\",\"params\":{\"token\":\"\"}}"
                                   toEndpoint:endpoint];
    XCTAssertEqualObjects(refused[@"error"][@"code"], @1006,
                          @"and a blanked token must not: %@", refused);

    // Each handler gets its OWN grant, not a shared one: a second probe reports a different value.
    NSString *secondToken = [self runProbeNamed:@"token_fd_probe2"
                                  executionMode:@"exe_shell_script"
                                        command:@[@"IFS= read -r t <&3; printf '%s' \"$t\""]];
    XCTAssertEqual(secondToken.length, (NSUInteger)64);
    XCTAssertNotEqualObjects(secondToken, handlerToken,
                             @"one token per spawn, so a leaked one cannot outlive its command");

    [self closeFormDialogWithUUID:uuid bundlePath:omcBundlePath];
    [self removeDiagnosticFilesForUUID:uuid];
}

- (void)testARevokedCommandsTokenIsRefused {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:omcBundlePath];
    NSString *endpoint = [self runningEndpoint];
    XCTAssertNotNil(endpoint);

    // The engine labels a command's grants with the command's GUID and does not revoke them per
    // command today (see the commit note on the revocation policy). This test drives the route a
    // tighter policy would use, so that the label is known to be the GUID and known to work.
    NSString *guid = [self runProbeNamed:@"token_revoke_probe"
                           executionMode:@"exe_shell_script"
                                 command:@[@"IFS= read -r t <&3; printf '%s %s' \"$OMC_CURRENT_COMMAND_GUID\" \"$t\""]];
    NSArray<NSString *> *parts = [guid componentsSeparatedByString:@" "];
    XCTAssertEqual(parts.count, (NSUInteger)2, @"expected '<guid> <token>', got: %@", guid);
    NSString *commandGUID = parts.firstObject;
    NSString *token = parts.lastObject;
    XCTAssertGreaterThan(commandGUID.length, (NSUInteger)0);

    NSString *request = [NSString stringWithFormat:
        @"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"actionui.hello\",\"params\":{\"token\":\"%@\"}}", token];
    XCTAssertNil([self sendJSONRPC:request toEndpoint:endpoint][@"error"],
                 @"the grant is live before it is withdrawn");

    OMCRevokeActionUIRemoteTokens([commandGUID UTF8String]);

    XCTAssertEqualObjects([self sendJSONRPC:request toEndpoint:endpoint][@"error"][@"code"], @1006,
                          @"withdrawing the command's label withdraws its token");

    [self closeFormDialogWithUUID:uuid bundlePath:omcBundlePath];
    [self removeDiagnosticFilesForUUID:uuid];
}

- (void)testTheGrantCapNeverWithdrawsTheTokenItJustIssued {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:omcBundlePath];
    NSString *endpoint = [self runningEndpoint];
    XCTAssertNotNil(endpoint);

    // Grants are bounded, and the bound is enforced by withdrawing the oldest. But revocation is
    // BY LABEL and takes every grant carrying it, so an eviction must not fire while newer
    // siblings share that label - in the extreme, minting past the cap under one label would
    // withdraw the token being handed back. The engine's own labels are per-command GUIDs, so
    // this drives the public entry point directly, which is where a caller could reuse one.
    const char *sharedLabel = "AbracodeTests.sharedLabel";
    char firstToken[kOMCActionUIRemoteTokenBufferSize] = {0};
    XCTAssertTrue(OMCMintActionUIRemoteToken(sharedLabel, firstToken, sizeof(firstToken)));

    char latestToken[kOMCActionUIRemoteTokenBufferSize] = {0};
    for (int index = 0; index < 300; index++) {          // comfortably past the 256 cap
        memset(latestToken, 0, sizeof(latestToken));
        XCTAssertTrue(OMCMintActionUIRemoteToken(sharedLabel, latestToken, sizeof(latestToken)),
                      @"minting must keep working past the cap");
    }
    XCTAssertNotEqualObjects(@(latestToken), @(firstToken), @"each mint is its own grant");

    NSString *request = [NSString stringWithFormat:
        @"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"actionui.hello\",\"params\":{\"token\":\"%s\"}}",
        latestToken];
    XCTAssertNil([self sendJSONRPC:request toEndpoint:endpoint][@"error"],
                 @"the token the cap just handed back must still be live");

    // And the cap really does withdraw: everything under that label goes when it is revoked.
    OMCRevokeActionUIRemoteTokens(sharedLabel);
    XCTAssertEqualObjects([self sendJSONRPC:request toEndpoint:endpoint][@"error"][@"code"], @1006,
                          @"and revoking the label withdraws it");

    [self closeFormDialogWithUUID:uuid bundlePath:omcBundlePath];
    [self removeDiagnosticFilesForUUID:uuid];
}

- (void)testPsCannotSeeTheTokenOfALivePythonHandler {
    NSURL *formURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (formURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *packages = [self shippedPackagesDirectory];
    if (![[NSFileManager defaultManager] fileExistsAtPath:
          [packages stringByAppendingPathComponent:@"actionui_remote.py"]]) {
        NSLog(@"Skipping - actionui_remote.py not found at %@", packages);
        return;
    }

    NSString *formPath = [formURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:formPath];
    XCTAssertNotNil([self runningEndpoint]);

    NSDictionary *savedEnvironment = [[NSProcessInfo processInfo] environment];
    NSString *savedPythonPath = savedEnvironment[@"PYTHONPATH"];
    NSString *savedWindowUUID = savedEnvironment[@"ACTIONUI_WINDOW_UUID"];
    setenv("PYTHONPATH", [packages fileSystemRepresentation], 1);
    setenv("ACTIONUI_WINDOW_UUID", [uuid UTF8String], 1);
    setenv("PYTHONDONTWRITEBYTECODE", "1", 1);

    // The sweep runs INSIDE the handler, while it is alive and holding a bridge connection.
    // Doing it from the test afterwards would prove nothing: `ps` reads the exec-time snapshot
    // of a process, and by then there is no process. The marker is in the handler's own argv,
    // which every process can read whatever its code-signing flags - that is the positive
    // control, without which "the token was not found" would also be true of an empty sweep.
    NSString *marker = @"OMC_TOKEN_PS_PROBE_MARKER";
    NSString *handler = [NSString stringWithFormat:
        @"import os, subprocess, sys, actionui_remote as aui\n"
        @"win = aui.Window(os.environ['ACTIONUI_WINDOW_UUID'])\n"
        @"win.set_string(2, 'alive')\n"                      // a real request: the token was accepted
        @"token = win.connection.token\n"
        @"sweep = subprocess.run(['/bin/ps', '-A', '-E', '-o', 'command='],\n"
        @"                       capture_output=True, text=True).stdout\n"
        @"print('len', len(token))\n"
        @"print('sawself', '%@' in sweep)\n"
        @"print('leaked', token in sweep)\n"
        @"print('envtoken', 'ACTIONUI_REMOTE_TOKEN' in os.environ)\n"
        @"print('envfd', 'ACTIONUI_REMOTE_TOKEN_FD' in os.environ)\n", marker];

    // python3 inherits descriptor 3 and ACTIONUI_REMOTE_TOKEN_FD from the shell the engine
    // spawned, which is the grandchild case the design allows for: the shell did not read the
    // pipe, so the first reader is python3. The marker rides in argv on purpose.
    NSString *command = [NSString stringWithFormat:@"/usr/bin/python3 -c %@ %@",
                         [self shellQuoted:handler], marker];
    NSString *output = [self runProbeNamed:@"token_ps_probe"
                             executionMode:@"exe_shell_script"
                                   command:@[command]];

    XCTAssertTrue([output containsString:@"len 64"],
                  @"the handler must have read a real token off the descriptor; got:\n%@", output);
    XCTAssertTrue([output containsString:@"sawself True"],
                  @"the sweep must see the handler itself, or it saw nothing at all; got:\n%@", output);
    XCTAssertTrue([output containsString:@"leaked False"],
                  @"`ps -A -E` must not show the token of a live python3 handler; got:\n%@", output);
    XCTAssertTrue([output containsString:@"envtoken False"],
                  @"and the handler's environment must not carry it either; got:\n%@", output);
    XCTAssertTrue([output containsString:@"envfd False"],
                  @"the client removes the descriptor variable once it has read it; got:\n%@", output);

    // Restored, or a later test's handler inherits a window UUID naming a window that is closed.
    if (savedPythonPath != nil) { setenv("PYTHONPATH", [savedPythonPath UTF8String], 1); }
    else { unsetenv("PYTHONPATH"); }
    if (savedWindowUUID != nil) { setenv("ACTIONUI_WINDOW_UUID", [savedWindowUUID UTF8String], 1); }
    else { unsetenv("ACTIONUI_WINDOW_UUID"); }

    [self closeFormDialogWithUUID:uuid bundlePath:formPath];
    [self removeDiagnosticFilesForUUID:uuid];
}

#pragma mark - Lifecycle

- (void)testBridgeStartsWithTheFirstActionUIWindow {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:omcBundlePath];

    NSString *endpoint = [self runningEndpoint];
    XCTAssertNotNil(endpoint,
                    @"an ActionUI window must have started the bridge; expected a socket at %@",
                    [self expectedEndpoint]);
    XCTAssertLessThanOrEqual(strlen([endpoint fileSystemRepresentation]), (size_t)103,
                             @"sun_path holds 103 bytes");
    XCTAssertTrue([endpoint containsString:@"/OMC/"],
                  @"the socket belongs in the engine's private temp directory, not loose in temp");

    // A socket, not a regular file left behind by something else.
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:endpoint error:nil];
    XCTAssertEqualObjects(attributes[NSFileType], NSFileTypeSocket);

    [self closeFormDialogWithUUID:uuid bundlePath:omcBundlePath];
}

- (void)testStartingIsIdempotentAcrossWindows {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];

    NSString *firstUUID = [self openFormDialogWithBundlePath:omcBundlePath];
    XCTAssertNotNil([self runningEndpoint]);
    [self closeFormDialogWithUUID:firstUUID bundlePath:omcBundlePath];

    // The window that started the bridge is gone. The socket must not be: a script the applet
    // spawned earlier is holding this path, and rebinding it on the next window would break it.
    XCTAssertNotNil([self runningEndpoint],
                    @"closing the last ActionUI window must NOT stop the bridge");

    NSString *secondUUID = [self openFormDialogWithBundlePath:omcBundlePath];
    XCTAssertNotEqualObjects(firstUUID, secondUUID, @"the two windows really are different");
    XCTAssertNotNil([self runningEndpoint]);

    // And the second window is reachable on that same, still-valid endpoint.
    NSDictionary *reply = [self sendJSONRPC:@"{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"actionui.hello\"}"
                                 toEndpoint:[self runningEndpoint]];
    XCTAssertTrue([reply[@"result"][@"windows"] containsObject:secondUUID],
                  @"the reused server should list the new window");

    [self closeFormDialogWithUUID:secondUUID bundlePath:omcBundlePath];
}

#pragma mark - Environment export

- (void)testEndpointSubstitutesIntoCommandText {
    NSURL *formURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (formURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *formPath = [formURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:formPath];
    NSString *endpoint = [self runningEndpoint];
    XCTAssertNotNil(endpoint);

    // The substitution path (AppendTextToCommand) is a different switch from the environment path
    // (PopulateEnvironList); this covers the former, which no environment assertion would reach.
    NSDictionary *command = @{
        @"NAME": @"Remote Endpoint Word Test",
        @"COMMAND_ID": @"remote_endpoint_word_test",
        @"EXECUTION_MODE": @"exe_shell_script",
        @"COMMAND": @[@"echo endpoint=", @"__ACTIONUI_REMOTE_ENDPOINT__"]
    };
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"RemoteEndpointWordTest"
                                                withCommands:@[command]
                                                     scripts:@{}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];

    OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;
    OSStatus err = [OMCCommandExecutor runCommand:@"remote_endpoint_word_test"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                             allowKeyWindowSubcommand:NO
                                         delegate:observer];
    XCTAssertEqual(err, noErr);
    XCTAssertTrue([observer waitForCompletionWithTimeout:kDefaultExecutionTimeout]);

    NSString *output = [observer.capturedOutput
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    XCTAssertEqualObjects(output, ([NSString stringWithFormat:@"endpoint=%@", endpoint]),
                          @"__ACTIONUI_REMOTE_ENDPOINT__ should substitute to the live socket path");

    [self closeFormDialogWithUUID:uuid bundlePath:formPath];
}

- (void)testAllThreeVariablesReachTheDialogsOwnHandler {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:omcBundlePath];
    NSString *endpoint = [self runningEndpoint];
    XCTAssertNotNil(endpoint);

    NSString *initPath = [self reportPathForInitHandlerOfUUID:uuid];
    XCTAssertTrue([self waitForFileAtPath:initPath timeout:5.0],
                  @"the init handler should have written its report");

    NSString *contents = [NSString stringWithContentsOfFile:initPath encoding:NSUTF8StringEncoding error:nil];
    NSMutableDictionary *diag = [NSMutableDictionary dictionary];
    for (NSString *line in [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location != NSNotFound) {
            diag[[line substringToIndex:eq.location]] = [line substringFromIndex:eq.location + 1];
        }
    }

    // OMC's own spelling, from the special-word table.
    XCTAssertEqualObjects(diag[@"OMC_ACTIONUI_REMOTE_ENDPOINT"], endpoint);
    // The protocol's spelling, inherited from the process environment rather than the dictionary.
    XCTAssertEqualObjects(diag[@"ACTIONUI_REMOTE_ENDPOINT"], endpoint);
    // The per-dialog alias, which cannot come from the process environment.
    XCTAssertEqualObjects(diag[@"ACTIONUI_WINDOW_UUID"], uuid);
    XCTAssertEqualObjects(diag[@"OMC_ACTIONUI_WINDOW_UUID"], uuid,
                          @"the OMC-prefixed name keeps working");

    [self closeFormDialogWithUUID:uuid bundlePath:omcBundlePath];
    [self removeDiagnosticFilesForUUID:uuid];
}

/// Run a one-line probe command in a synthesized bundle and return its trimmed output.
- (NSString *)runProbeNamed:(NSString *)commandID
              executionMode:(NSString *)mode
                    command:(NSArray *)commandParts {
    NSDictionary *command = @{
        @"NAME": commandID,
        @"COMMAND_ID": commandID,
        @"EXECUTION_MODE": mode,
        @"COMMAND": commandParts
    };
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:commandID
                                                withCommands:@[command]
                                                     scripts:@{}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];

    OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;
    OSStatus err = [OMCCommandExecutor runCommand:commandID
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                             allowKeyWindowSubcommand:NO
                                         delegate:observer];
    XCTAssertEqual(err, noErr);
    XCTAssertTrue([observer waitForCompletionWithTimeout:kDefaultExecutionTimeout]);
    return [observer.capturedOutput
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/// The endpoint reaches a handler by two independent routes, and either one alone is enough to
/// make a naive test pass while the other is broken: PopulateEnvironList puts it in the command's
/// environment dictionary, and CreateEnviron merges the process environment underneath that
/// dictionary. These two tests isolate one route each.

- (void)testTheDictionaryPathSuppliesTheEndpointOnItsOwn {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:omcBundlePath];
    NSString *endpoint = [self runningEndpoint];
    XCTAssertNotNil(endpoint);

    // Take BOTH names out of our own environment, so CreateEnviron has nothing to contribute and
    // the child can only see them if CreateEnvironmentVariablesDict put them in the dictionary.
    // Both matter: the OMC-prefixed one comes from PopulateEnvironList, and the unprefixed one is
    // the alias copied beside it - which is the only route either has in the Terminal and iTerm
    // modes, where the dictionary is serialized into an export script for a process that is not
    // our descendant and inherits nothing from us.
    char *savedPrefixed = getenv("OMC_ACTIONUI_REMOTE_ENDPOINT");
    NSString *savedPrefixedValue = (savedPrefixed != NULL) ? [NSString stringWithUTF8String:savedPrefixed] : nil;
    char *savedPlain = getenv("ACTIONUI_REMOTE_ENDPOINT");
    NSString *savedPlainValue = (savedPlain != NULL) ? [NSString stringWithUTF8String:savedPlain] : nil;
    unsetenv("OMC_ACTIONUI_REMOTE_ENDPOINT");
    unsetenv("ACTIONUI_REMOTE_ENDPOINT");

    NSString *output = [self runProbeNamed:@"endpoint_dict_probe"
                             executionMode:@"exe_shell_script"
                                   command:@[@"echo dict=$OMC_ACTIONUI_REMOTE_ENDPOINT plain=$ACTIONUI_REMOTE_ENDPOINT"]];

    if (savedPrefixedValue != nil) {
        setenv("OMC_ACTIONUI_REMOTE_ENDPOINT", [savedPrefixedValue UTF8String], 1);
    }
    if (savedPlainValue != nil) {
        setenv("ACTIONUI_REMOTE_ENDPOINT", [savedPlainValue UTF8String], 1);
    }

    XCTAssertEqualObjects(output,
                          ([NSString stringWithFormat:@"dict=%@ plain=%@", endpoint, endpoint]),
                          @"the dictionary must carry both spellings without help from environ");

    [self closeFormDialogWithUUID:uuid bundlePath:omcBundlePath];
    [self removeDiagnosticFilesForUUID:uuid];
}

- (void)testTheProcessEnvironmentSuppliesTheEndpointOnItsOwn {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:omcBundlePath];
    NSString *endpoint = [self runningEndpoint];
    XCTAssertNotNil(endpoint);

    // exe_system runs a bare system() and is handed no environment dictionary at all, so only a
    // setenv into our own environ can reach this child. Same probe shape as
    // OMCEnvironmentVariablesTests uses for OMC_APP_PROCESS_ID.
    //
    // Probe the OMC-prefixed name specifically. The unprefixed one is exported by ActionUIRemote's
    // own startShared, so a probe of it passes even with OMC's setenv deleted - it would pin
    // ActionUI's behavior rather than this file's. Verified by mutation.
    NSString *probeFile = [NSString stringWithFormat:@"/tmp/OMC_test_remote_env_%d", (int)getpid()];
    [[NSFileManager defaultManager] removeItemAtPath:probeFile error:nil];

    [self runProbeNamed:@"endpoint_environ_probe"
          executionMode:@"exe_system"
                command:@[[NSString stringWithFormat:
                           @"echo \"env=$OMC_ACTIONUI_REMOTE_ENDPOINT\" > %@", probeFile]]];

    XCTAssertTrue([self waitForFileAtPath:probeFile timeout:5.0],
                  @"the exe_system probe should have written its file");
    NSString *contents = [[NSString stringWithContentsOfFile:probeFile encoding:NSUTF8StringEncoding error:nil]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [[NSFileManager defaultManager] removeItemAtPath:probeFile error:nil];

    XCTAssertEqualObjects(contents, ([NSString stringWithFormat:@"env=%@", endpoint]),
                          @"the process environment must carry the endpoint into a mode that gets no dictionary");

    [self closeFormDialogWithUUID:uuid bundlePath:omcBundlePath];
}

#pragma mark - The shipped omc module, against the real engine

/// Where AppletBuilder keeps the modules it installs into Python applets.
///
/// Derived from this file's own source path, which is the only way a test running out of a
/// built .xctest can find the repository. The point of the test below is the SHIPPED copies -
/// the ones an applet actually receives - so pointing at anything else would prove less.
- (NSString *)shippedPackagesDirectory {
    NSString *thisFile = [NSString stringWithUTF8String:__FILE__];
    NSString *repo = [[[thisFile stringByDeletingLastPathComponent]     // AbracodeTests
                       stringByDeletingLastPathComponent]               // AbracodeFramework
                      stringByDeletingLastPathComponent];               // repo root
    return [repo stringByAppendingPathComponent:
            @"Distribution/AppletBuilder.app/Contents/Library/Packages"];
}

/// The whole stack, in one test: a Python handler the engine dispatches, importing the module
/// AppletBuilder ships, talking over the real bridge to a real ActionUI window.
///
/// Everything else in this file drives the socket with raw JSON built by hand, and the omc
/// module's own tests drive it against a fake host. Neither one would notice if the shipped
/// module and the shipped engine disagreed.
- (void)testTheShippedOmcModuleDrivesARealWindow {
    NSURL *formURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (formURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *packages = [self shippedPackagesDirectory];
    if (![[NSFileManager defaultManager] fileExistsAtPath:
          [packages stringByAppendingPathComponent:@"omc.py"]]) {
        NSLog(@"Skipping - omc.py not found at %@", packages);
        return;
    }

    NSString *formPath = [formURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:formPath];
    XCTAssertNotNil([self runningEndpoint]);
    XCTAssertTrue([self waitForFileAtPath:[self reportPathForInitHandlerOfUUID:uuid] timeout:5.0],
                  @"the init handler must have run before its write can be read back");

    // Stand in for what the engine does for an applet with an embedded runtime: put the
    // modules on PYTHONPATH, and name the window. Both reach the child through CreateEnviron,
    // exactly as they would in production - this is not a back door into the handler.
    NSString *savedPythonPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"PYTHONPATH"];
    setenv("PYTHONPATH", [packages fileSystemRepresentation], 1);
    setenv("ACTIONUI_WINDOW_UUID", [uuid UTF8String], 1);
    // The handler imports from inside AppletBuilder.app, and this test host has no embedded
    // Python - so the engine sets no PYTHONPYCACHEPREFIX and CPython would write __pycache__
    // into a bundle that gets codesigned. A real applet has both and never hits this; the test
    // has to say so itself rather than leave bytecode behind in the tree.
    setenv("PYTHONDONTWRITEBYTECODE", "1", 1);

    NSString *reportPath = [NSString stringWithFormat:@"/tmp/OMC_test_omc_module_%@", uuid];
    [[NSFileManager defaultManager] removeItemAtPath:reportPath error:nil];

    NSString *handler = [NSString stringWithFormat:
        @"import omc\n"
        @"win = omc.window()\n"
        @"before = win.get_string(2)\n"                       // what omc_dialog_control wrote
        @"win.set_string(2, 'set by the omc module')\n"
        @"after = win.get_string(2)\n"                        // read our own write back
        @"win.set_rows(5, [['one', 'two']])\n"
        @"rows = win.get_rows(5)\n"
        @"ctx = omc.context()\n"
        @"with open('%@', 'w') as fh:\n"
        @"    fh.write(before + chr(10))\n"
        @"    fh.write(after + chr(10))\n"
        @"    fh.write(repr(rows) + chr(10))\n"
        @"    fh.write(ctx.window_uuid + chr(10))\n", reportPath];

    NSDictionary *command = @{
        @"NAME": @"omc module probe",
        @"COMMAND_ID": @"omc_module_probe",
        @"EXECUTION_MODE": @"exe_script_file"
    };
    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"OMCModuleProbe"
                                                withCommands:@[command]
                                                     scripts:@{@"omc_module_probe.py": handler}];
    XCTAssertNotNil(bundleURL);
    [self.bundlesToCleanup addObject:bundleURL];

    OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;
    OSStatus err = [OMCCommandExecutor runCommand:@"omc_module_probe"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                             allowKeyWindowSubcommand:NO
                                         delegate:observer];
    XCTAssertEqual(err, noErr);
    XCTAssertTrue([observer waitForCompletionWithTimeout:kDefaultExecutionTimeout]);

    if (savedPythonPath != nil) {
        setenv("PYTHONPATH", [savedPythonPath UTF8String], 1);
    } else {
        unsetenv("PYTHONPATH");
    }
    unsetenv("ACTIONUI_WINDOW_UUID");
    unsetenv("PYTHONDONTWRITEBYTECODE");

    XCTAssertTrue([self waitForFileAtPath:reportPath timeout:5.0],
                  @"the Python handler should have written its report; output was: %@",
                  observer.capturedOutput);
    NSArray<NSString *> *lines = [[NSString stringWithContentsOfFile:reportPath
                                                           encoding:NSUTF8StringEncoding error:nil]
                                  componentsSeparatedByString:@"\n"];
    XCTAssertGreaterThanOrEqual(lines.count, (NSUInteger)4, @"report was %@", lines);

    // It read what OMC's own tool had written - the read path, which is the point.
    XCTAssertEqualObjects(lines[0], @"Papa Smurf");
    // It wrote, and read its own write back.
    XCTAssertEqualObjects(lines[1], @"set by the omc module");
    XCTAssertEqualObjects(lines[2], @"[['one', 'two']]");
    // And resolved the window from the environment rather than being handed one.
    XCTAssertEqualObjects(lines[3], uuid);

    // Independently: the engine really holds what the module wrote.
    NSString *request = [NSString stringWithFormat:
        @"{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"actionui.getValue\",\"params\":{\"window\":\"%@\",\"viewID\":2}}",
        uuid];
    NSDictionary *reply = [self sendJSONRPC:request toEndpoint:[self runningEndpoint]];
    XCTAssertEqualObjects(reply[@"result"], @"set by the omc module",
                          @"the engine should hold what the module set");

    [[NSFileManager defaultManager] removeItemAtPath:reportPath error:nil];
    [self closeFormDialogWithUUID:uuid bundlePath:formPath];
    [self removeDiagnosticFilesForUUID:uuid];
}

#pragma mark - Stopping

- (void)testStopUnbindsAndALaterWindowStartsItAgain {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:omcBundlePath];
    XCTAssertNotNil([self runningEndpoint]);
    [self closeFormDialogWithUUID:uuid bundlePath:omcBundlePath];

    // -appWillTerminate: is what calls this in a real host, and XCTest never gets there. The class
    // is not in AbracodeFramework.exp so it cannot be linked, but it IS registered in the loaded
    // image, which is all NSClassFromString needs.
    Class hostClass = NSClassFromString(@"OMCActionUIRemoteHost");
    XCTAssertNotNil(hostClass, @"OMCActionUIRemoteHost should be in the loaded framework image");
    id host = [hostClass performSelector:@selector(shared)];
    XCTAssertNotNil(host);
    [host performSelector:@selector(stop)];

    XCTAssertNil([self runningEndpoint], @"stop must unlink the socket");
    XCTAssertTrue(getenv("ACTIONUI_REMOTE_ENDPOINT") == NULL,
                  @"stop must unset the protocol's variable");
    XCTAssertTrue(getenv("OMC_ACTIONUI_REMOTE_ENDPOINT") == NULL,
                  @"stop must unset OMC's variable");

    // And the host is not latched shut: the next window binds again, so a stop from any other
    // in-process user of ActionUIRemote is recoverable.
    NSString *secondUUID = [self openFormDialogWithBundlePath:omcBundlePath];
    XCTAssertNotNil([self runningEndpoint], @"a later window must be able to restart the bridge");
    [self closeFormDialogWithUUID:secondUUID bundlePath:omcBundlePath];
    [self removeDiagnosticFilesForUUID:uuid];
    [self removeDiagnosticFilesForUUID:secondUUID];
}

#pragma mark - It really serves

- (void)testBridgeAnswersHelloAndListsTheOpenWindow {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:omcBundlePath];
    NSString *endpoint = [self runningEndpoint];
    XCTAssertNotNil(endpoint);

    NSDictionary *reply = [self sendJSONRPC:@"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"actionui.hello\"}"
                                 toEndpoint:endpoint];
    XCTAssertNotNil(reply, @"hello should get a reply");
    XCTAssertNil(reply[@"error"], @"hello should not error: %@", reply[@"error"]);

    NSDictionary *result = reply[@"result"];
    XCTAssertTrue([result isKindOfClass:[NSDictionary class]]);
    XCTAssertEqualObjects(result[@"protocolVersion"], @1, @"this host speaks protocol version 1");

    NSArray *windows = result[@"windows"];
    XCTAssertTrue([windows containsObject:uuid],
                  @"hello should list the window the engine just opened; got %@", windows);

    // The version must be the ENGINE's, from Abracode.framework's own Info.plist. Asserting only
    // that it is non-empty would pass if -hostVersion were deleted, because ActionUIRemote falls
    // back to the main bundle's version on its own.
    NSDictionary *host = result[@"host"];
    NSString *engineVersion = [[NSBundle bundleWithIdentifier:@"com.abracode.AbracodeFramework"]
                               objectForInfoDictionaryKey:@"CFBundleVersion"];
    XCTAssertTrue([engineVersion length] > 0, @"the framework should report a version");
    XCTAssertEqualObjects(host[@"version"], engineVersion,
                          @"hello should report the OMC engine version, not the host app's");
    XCTAssertTrue([host[@"name"] length] > 0, @"the host names itself");

    // No omc.* verbs are registered: mutation stays with omc_dialog_control, which already covers
    // every one of them. If that decision is ever revisited, this assertion is the reminder.
    NSArray *methods = result[@"methods"];
    for (NSString *method in methods) {
        XCTAssertFalse([method hasPrefix:@"omc."],
                       @"unexpected host extension method %@", method);
    }

    [self closeFormDialogWithUUID:uuid bundlePath:omcBundlePath];
}

- (void)testBridgeReadsBackAValueWrittenByTheEngine {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:omcBundlePath];
    NSString *endpoint = [self runningEndpoint];
    XCTAssertNotNil(endpoint);

    // The Form init handler sets view 2 to "Papa Smurf" through omc_dialog_control. Reading it
    // back over the socket is the whole point of the bridge: OMC could already write, and could
    // not read. Wait for that handler first - it is a separate command, and the command that
    // opened the window returns before it has run.
    XCTAssertTrue([self waitForFileAtPath:[self reportPathForInitHandlerOfUUID:uuid] timeout:5.0],
                  @"the init handler must have run before its write can be read back");
    NSString *request = [NSString stringWithFormat:
        @"{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"actionui.getValue\",\"params\":{\"window\":\"%@\",\"viewID\":2}}",
        uuid];
    NSDictionary *reply = [self sendJSONRPC:request toEndpoint:endpoint];
    XCTAssertNotNil(reply);
    XCTAssertNil(reply[@"error"], @"getValue should not error: %@", reply[@"error"]);
    XCTAssertEqualObjects(reply[@"result"], @"Papa Smurf",
                          @"the bridge should read the value omc_dialog_control wrote");

    [self closeFormDialogWithUUID:uuid bundlePath:omcBundlePath];
}

- (void)testUnknownWindowIsReportedAsProtocolError1001 {
    NSURL *bundleURL = [OMCBundleTestHelper testBundleURL:@"ActionUI-Form"];
    if (bundleURL == nil) {
        NSLog(@"Skipping - ActionUI-Form.omc not found in test resources");
        return;
    }
    NSString *omcBundlePath = [bundleURL path];
    NSString *uuid = [self openFormDialogWithBundlePath:omcBundlePath];
    NSString *endpoint = [self runningEndpoint];
    XCTAssertNotNil(endpoint);

    NSDictionary *reply = [self sendJSONRPC:
        @"{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"actionui.getValue\",\"params\":{\"window\":\"no-such-window\",\"viewID\":2}}"
                                 toEndpoint:endpoint];
    XCTAssertNotNil(reply);
    XCTAssertEqualObjects(reply[@"error"][@"code"], @1001,
                          @"an unknown window is 1001, per PROTOCOL.md");

    [self closeFormDialogWithUUID:uuid bundlePath:omcBundlePath];
}

@end

#endif // CURRENT_OMC_VERSION >= 50000

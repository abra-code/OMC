//
//  OMCURLInvocationTests.m
//  AbracodeTests
//
//  Tests for commands run by a URL sent to the applet (+runCommandForURL:forCommandFile:delegate:):
//  the URL_INVOCABLE opt-in, the commands a URL can never run, the file context rules
//  and the OMC_TRIGGER_URL variable.
//

#import "OMCTestCase.h"
#import "OMCCommandExecutor.h"
#import "OMCTestExecutionObserver.h"

// Prints the context a command received. ${VAR-unset} tells an absent variable from an empty one.
// It mentions OMC_OBJ_PATH, so each command using it turns the file dialog off: with it on,
// OMC cancels a run that has no file context and may not ask for one.
static NSString * const kReportContext = @"echo \"text=[${OMC_OBJ_TEXT}] path=[${OMC_OBJ_PATH}] trigger=[${OMC_TRIGGER_URL-unset}]\"";

@interface OMCURLInvocationTests : OMCTestCase
@end

@implementation OMCURLInvocationTests

- (NSString *)testName {
    return @"OMCURLInvocationTests";
}

- (NSDictionary *)lifecycleCommandWithID:(NSString *)commandID {
    return @{
        @"NAME": @"URL Test",
        @"COMMAND_ID": commandID,
        @"EXECUTION_MODE": @"exe_shell_script",
        @"URL_INVOCABLE": @YES, // set on purpose: the refusal must not depend on the key
        @"USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT": @NO,
        @"COMMAND": @[kReportContext]
    };
}

- (NSDictionary *)testCommandDescription {
    return @{
        @"VERSION": @2,
        @"COMMAND_LIST": @[
            // No URL_INVOCABLE key: the default
            @{
                @"NAME": @"Not Opted In",
                @"COMMAND_ID": @"url.not.opted.in",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT": @NO,
                @"COMMAND": @[kReportContext]
            },
            // URL_INVOCABLE explicitly false
            @{
                @"NAME": @"Opted Out",
                @"COMMAND_ID": @"url.opted.out",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"URL_INVOCABLE": @NO,
                @"USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT": @NO,
                @"COMMAND": @[kReportContext]
            },
            @{
                @"NAME": @"Opted In",
                @"COMMAND_ID": @"url.opted.in",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"URL_INVOCABLE": @YES,
                @"USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT": @NO,
                @"COMMAND": @[kReportContext]
            },
            // Opted in, and chains to a command that is not: the chain is the author's choice
            @{
                @"NAME": @"Opted In With Next",
                @"COMMAND_ID": @"url.opted.in.with.next",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"URL_INVOCABLE": @YES,
                @"NEXT_COMMAND_ID": @"url.next",
                @"COMMAND": @[@"echo first"]
            },
            @{
                @"NAME": @"Opted In With Next",
                @"COMMAND_ID": @"url.next",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"COMMAND": @[@"echo \"next trigger=[${OMC_TRIGGER_URL-unset}]\" > \"${TMPDIR}/OMCURLInvocationTests-next.txt\""]
            },
            // A dialog whose event handlers must stay out of reach
            @{
                @"NAME": @"Dialog",
                @"COMMAND_ID": @"url.dialog",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"COMMAND": @[@"echo dialog"],
                @"ACTIONUI_WINDOW": @{
                    @"JSON_NAME": @"does-not-matter",
                    @"INIT_SUBCOMMAND_ID": @"url.dialog.init",
                    @"END_OK_SUBCOMMAND_ID": @"url.dialog.ok",
                    @"END_CANCEL_SUBCOMMAND_ID": @"url.dialog.cancel",
                    @"WINDOW_DID_ACTIVATE_SUBCOMMAND_ID": @"url.dialog.activate"
                }
            },
            [self lifecycleCommandWithID:@"url.dialog.init"],
            [self lifecycleCommandWithID:@"url.dialog.ok"],
            [self lifecycleCommandWithID:@"url.dialog.cancel"],
            [self lifecycleCommandWithID:@"url.dialog.activate"],
            [self lifecycleCommandWithID:@"omc.dialog.initialize"],
            [self lifecycleCommandWithID:@"app.will.launch"],
            [self lifecycleCommandWithID:@"app.did.launch"],
            [self lifecycleCommandWithID:@"app.did.activate"],
            [self lifecycleCommandWithID:@"app.did.deactivate"],
            [self lifecycleCommandWithID:@"app.will.terminate"],
            // The applet's own URL handler: needs no key
            @{
                @"NAME": @"Handle URL",
                @"COMMAND_ID": @"omc.app.handle-url",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT": @NO,
                @"COMMAND": @[kReportContext]
            }
        ]
    };
}

#pragma mark - Helpers

- (OSStatus)runURL:(NSString *)url output:(NSString * _Nullable * _Nullable)outOutput {
    OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;
    OSStatus err = [OMCCommandExecutor runCommandForURL:url
                                         forCommandFile:[self.testPlistURL path]
                                               delegate:observer];
    if (err == noErr) {
        XCTAssertTrue([observer waitForCompletionWithTimeout:kDefaultExecutionTimeout], @"Task should complete for %@", url);
    }
    if (outOutput != NULL) {
        *outOutput = observer.capturedOutput;
    }
    return err;
}

- (void)assertRefused:(NSString *)url {
    NSString *output = nil;
    OSStatus err = [self runURL:url output:&output];
    XCTAssertEqual(err, errAEEventNotPermitted, @"Should refuse %@", url);
    XCTAssertEqual(output.length, 0, @"A refused URL must run nothing. Output: %@", output);
}

#pragma mark - Opt-in

- (void)testCommandWithoutKeyIsRefused {
    [self assertRefused:@"omctest://exe?commandID=url.not.opted.in"];
    [self assertRefused:@"omctest://exe?commandID=url.not.opted.in&text=hello"];
}

- (void)testCommandWithFalseKeyIsRefused {
    [self assertRefused:@"omctest://exe?commandID=url.opted.out"];
}

- (void)testCommandFoundByNameIsStillChecked {
    // commandID resolves by NAME as well; the check applies to whatever command it resolved to
    [self assertRefused:@"omctest://exe?commandID=Not%20Opted%20In"];
}

- (void)testUnknownCommandIsRefused {
    [self assertRefused:@"omctest://exe?commandID=no.such.command"];
}

- (void)testMissingCommandIDIsRefused {
    [self assertRefused:@"omctest://exe"];
    [self assertRefused:@"omctest://exe?text=hello"];
    [self assertRefused:@"omctest://exe?commandID="];
}

- (void)testLastCommandIDIsTheOneCheckedAndRun {
    // commandID given twice: the last one names the command, and the check is made on it
    [self assertRefused:@"omctest://exe?commandID=url.opted.in&commandID=url.not.opted.in"];

    NSString *output = nil;
    XCTAssertEqual([self runURL:@"omctest://exe?commandID=url.not.opted.in&commandID=url.opted.in&text=hello" output:&output], noErr);
    XCTAssertTrue([output containsString:@"text=[hello]"], @"Output: %@", output);
}

- (void)testOptedInCommandRunsWithText {
    NSString *url = @"omctest://exe?commandID=url.opted.in&text=hello%20world%26more";
    NSString *output = nil;
    XCTAssertEqual([self runURL:url output:&output], noErr);
    XCTAssertTrue([output containsString:@"text=[hello world&more]"], @"Output: %@", output);
}

- (void)testHostAndKeysAreCaseInsensitive {
    NSString *output = nil;
    XCTAssertEqual([self runURL:@"omctest://EXE?COMMANDID=url.opted.in&TEXT=hello" output:&output], noErr);
    XCTAssertTrue([output containsString:@"text=[hello]"], @"Output: %@", output);
}

- (void)testOptedInCommandRunsWithFile {
    NSURL *file = [self createTempFileWithName:@"url invocation test.txt" content:@"x"];
    NSURLComponents *components = [NSURLComponents componentsWithString:@"omctest://exe"];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"commandID" value:@"url.opted.in"],
        [NSURLQueryItem queryItemWithName:@"text" value:@"ignored when a file is given"],
        [NSURLQueryItem queryItemWithName:@"file" value:[file path]]
    ];

    NSString *output = nil;
    XCTAssertEqual([self runURL:[components string] output:&output], noErr);
    NSString *expected = [NSString stringWithFormat:@"path=[%@]", [file path]];
    XCTAssertTrue([output containsString:expected], @"Expected %@. Output: %@", expected, output);
}

#pragma mark - Never from a URL

- (void)testLifecycleCommandsAreRefusedEvenWithKey {
    for (NSString *commandID in @[@"app.will.launch", @"app.did.launch", @"app.did.activate", @"app.did.deactivate", @"app.will.terminate"]) {
        [self assertRefused:[@"omctest://exe?commandID=" stringByAppendingString:commandID]];
    }
}

- (void)testDialogSubcommandsAreRefusedEvenWithKey {
    for (NSString *commandID in @[@"url.dialog.init", @"url.dialog.ok", @"url.dialog.cancel", @"url.dialog.activate", @"omc.dialog.initialize"]) {
        [self assertRefused:[@"omctest://exe?commandID=" stringByAppendingString:commandID]];
    }
}

- (void)testRefusedCommandsStillRunWhenNotStartedByURL {
    // The refusals are about the URL entry point only
    OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;
    OSStatus err = [OMCCommandExecutor runCommand:@"app.will.terminate"
                                   forCommandFile:[self.testPlistURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:observer];
    XCTAssertEqual(err, noErr);
    XCTAssertTrue([observer waitForCompletionWithTimeout:kDefaultExecutionTimeout]);
    XCTAssertTrue([observer.capturedOutput containsString:@"trigger=[unset]"], @"Output: %@", observer.capturedOutput);
}

#pragma mark - File context

- (void)testRelativeFileIsRefused {
    [self assertRefused:@"omctest://exe?commandID=url.opted.in&file=relative.txt"];
    [self assertRefused:@"omctest://exe?commandID=url.opted.in&file=~/relative.txt"];
    [self assertRefused:@"omctest://exe?commandID=url.opted.in&file=../../etc/hosts"];
}

- (void)testMissingFileIsRefused {
    [self assertRefused:@"omctest://exe?commandID=url.opted.in&file=/no/such/file/for/omc/url/tests"];
}

- (void)testOneBadFileRefusesTheWholeURL {
    NSURL *file = [self createTempFileWithName:@"url-invocation-good.txt" content:@"x"];
    NSURLComponents *components = [NSURLComponents componentsWithString:@"omctest://exe"];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"commandID" value:@"url.opted.in"],
        [NSURLQueryItem queryItemWithName:@"file" value:[file path]],
        [NSURLQueryItem queryItemWithName:@"file" value:@"relative.txt"]
    ];
    [self assertRefused:[components string]];
}

#pragma mark - omc.app.handle-url

- (void)testOtherURLReachesHandleURLCommand {
    NSString *url = @"omctest://open/something?x=1";
    NSString *output = nil;
    XCTAssertEqual([self runURL:url output:&output], noErr);
    NSString *expectedText = [NSString stringWithFormat:@"text=[%@]", url];
    NSString *expectedTrigger = [NSString stringWithFormat:@"trigger=[%@]", url];
    XCTAssertTrue([output containsString:expectedText], @"Output: %@", output);
    XCTAssertTrue([output containsString:expectedTrigger], @"Output: %@", output);
}

- (void)testURLWithoutHostIsNotAnExeURL {
    // "omctest:exe?..." has no host. It must not be taken for the exe form.
    NSString *url = @"omctest:exe?commandID=url.not.opted.in";
    NSString *output = nil;
    XCTAssertEqual([self runURL:url output:&output], noErr);
    NSString *expectedText = [NSString stringWithFormat:@"text=[%@]", url];
    XCTAssertTrue([output containsString:expectedText], @"Should go to omc.app.handle-url. Output: %@", output);
}

#pragma mark - OMC_TRIGGER_URL

- (void)testTriggerVariableIsSetForURLRun {
    NSString *url = @"omctest://exe?commandID=url.opted.in&text=hello";
    NSString *output = nil;
    XCTAssertEqual([self runURL:url output:&output], noErr);
    NSString *expected = [NSString stringWithFormat:@"trigger=[%@]", url];
    XCTAssertTrue([output containsString:expected], @"Output: %@", output);
}

- (void)testTriggerVariableIsAbsentForOrdinaryRun {
    OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;
    OSStatus err = [OMCCommandExecutor runCommand:@"url.opted.in"
                                   forCommandFile:[self.testPlistURL path]
                                      withContext:@"hello"
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:observer];
    XCTAssertEqual(err, noErr);
    XCTAssertTrue([observer waitForCompletionWithTimeout:kDefaultExecutionTimeout]);
    XCTAssertTrue([observer.capturedOutput containsString:@"trigger=[unset]"], @"Output: %@", observer.capturedOutput);
}

- (void)testTriggerVariableReachesNextCommand {
    // The next command writes a file: the observer reports the first task's output only
    NSString *reportPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"OMCURLInvocationTests-next.txt"];
    [[NSFileManager defaultManager] removeItemAtPath:reportPath error:nil];

    NSString *url = @"omctest://exe?commandID=url.opted.in.with.next";
    XCTAssertEqual([self runURL:url output:NULL], noErr);

    NSString *report = nil;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:kDefaultExecutionTimeout];
    while (([report length] == 0) && ([deadline timeIntervalSinceNow] > 0)) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        report = [NSString stringWithContentsOfFile:reportPath encoding:NSUTF8StringEncoding error:nil];
    }
    [[NSFileManager defaultManager] removeItemAtPath:reportPath error:nil];

    NSString *expected = [NSString stringWithFormat:@"next trigger=[%@]", url];
    XCTAssertTrue([report containsString:expected], @"The next command should run and see the URL. Report: %@", report);
}

@end

#pragma mark -

// The lifecycle dispatch finds its command by id or by NAME, so a command NAMEd like a
// lifecycle id is a lifecycle command too. It needs its own command file: in the one above
// the lifecycle ids are taken by commands with those ids.
@interface OMCURLInvocationLifecycleNameTests : OMCTestCase
@end

@implementation OMCURLInvocationLifecycleNameTests

- (NSString *)testName {
    return @"OMCURLInvocationLifecycleNameTests";
}

- (NSDictionary *)testCommandDescription {
    return @{
        @"VERSION": @2,
        @"COMMAND_LIST": @[
            // A main command (no COMMAND_ID) named like a lifecycle id
            @{
                @"NAME": @"app.will.terminate",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"URL_INVOCABLE": @YES,
                @"COMMAND": @[@"echo ran"]
            },
            // A main command that a dialog names as its handler by the implicit "<NAME>.main" id
            @{
                @"NAME": @"Dlg",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"URL_INVOCABLE": @YES,
                @"COMMAND": @[@"echo ran"]
            },
            @{
                @"NAME": @"Dlg",
                @"COMMAND_ID": @"dlg.open",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"COMMAND": @[@"echo open"],
                @"ACTIONUI_WINDOW": @{ @"JSON_NAME": @"does-not-matter", @"INIT_SUBCOMMAND_ID": @"Dlg.main" }
            },
            // Named like a lifecycle id, with an id of its own
            @{
                @"NAME": @"app.did.launch",
                @"COMMAND_ID": @"named.like.lifecycle",
                @"EXECUTION_MODE": @"exe_shell_script",
                @"URL_INVOCABLE": @YES,
                @"COMMAND": @[@"echo ran"]
            }
        ]
    };
}

- (void)testCommandsNamedLikeLifecycleIDsAreRefusedEvenWithKey {
    for (NSString *commandID in @[@"app.will.terminate", @"app.will.terminate.main", @"main", @"app.did.launch", @"named.like.lifecycle"]) {
        OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;
        NSString *url = [@"omctest://exe?commandID=" stringByAppendingString:commandID];
        OSStatus err = [OMCCommandExecutor runCommandForURL:url forCommandFile:[self.testPlistURL path] delegate:observer];
        XCTAssertEqual(err, errAEEventNotPermitted, @"Should refuse %@", url);
        XCTAssertEqual(observer.capturedOutput.length, 0, @"A refused URL must run nothing. Output: %@", observer.capturedOutput);
    }
}

- (void)testMainCommandNamedAsDialogHandlerIsRefusedEvenWithKey {
    for (NSString *commandID in @[@"Dlg.main", @"Dlg"]) {
        OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;
        NSString *url = [@"omctest://exe?commandID=" stringByAppendingString:commandID];
        OSStatus err = [OMCCommandExecutor runCommandForURL:url forCommandFile:[self.testPlistURL path] delegate:observer];
        XCTAssertEqual(err, errAEEventNotPermitted, @"Should refuse %@", url);
        XCTAssertEqual(observer.capturedOutput.length, 0, @"A refused URL must run nothing. Output: %@", observer.capturedOutput);
    }
}

- (void)testLifecycleDispatchStillFindsCommandByName {
    OMCTestExecutionObserver *observer = OMCTestExecutionObserver.new;
    OSStatus err = [OMCCommandExecutor runCommand:@"app.will.terminate"
                                   forCommandFile:[self.testPlistURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:observer];
    XCTAssertEqual(err, noErr);
    XCTAssertTrue([observer waitForCompletionWithTimeout:kDefaultExecutionTimeout]);
    XCTAssertTrue([observer.capturedOutput containsString:@"ran"], @"Output: %@", observer.capturedOutput);
}

@end

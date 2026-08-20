//
//  OMCSyntheticCommandTests.m
//  AbracodeTests
//
//  Black-box integration tests for automatic synthesis of command description entries from
//  undeclared script files.
//
//  Scripts and the Command.plist are packaged inside a temporary .omc bundle
//  created by OMCBundleTestHelper. Passing the .omc bundle path to
//  runCommand:forCommandFile: causes the OMC engine to create a CFBundleRef for
//  it, so CreateAugmentedCommandArray() searches that bundle, never the
//  host process bundle (xctest / Xcode Agents directory).
//
//  NOTE on OMCScriptsManager caching:
//  CreateAugmentedCommandArray() delegates to OMCScriptsManager::GetAllScriptPaths(),
//  which builds and caches the per-bundle script dictionary on first access. Scripts
//  placed in the bundle before any cache entry is built are always visible. Because
//  OMCBundleTestHelper writes all files before returning the bundle URL, this is
//  guaranteed automatically.
//

#import "OMCTestCase.h"
#import "OMCBundleTestHelper.h"
#import "OMCCommandExecutor.h"
#import "OMCTestExecutionObserver.h"
#import "OMC.h"

// ---------------------------------------------------------------------------
// Test class
// ---------------------------------------------------------------------------

@interface OMCSyntheticCommandTests : XCTestCase
@end

/// URL of the shared .omc bundle created in +setUp; removed in +tearDown.
static NSURL *sBundleURL = nil;

@implementation OMCSyntheticCommandTests

// +setUp runs ONCE before the first test in this class.
// The bundle (including all script files) must exist before any
// OMCScriptsManager cache entry is populated for it.
+ (void)setUp
{
    [super setUp];

    // Only "OMCSynth.declared" has an explicit plist entry.
    // All other OMCSynth.* and Unrelated.* IDs are intentionally absent so
    // that the synthesis path is exercised.
    NSArray *commands = @[
        @{
            @"NAME": @"OMCSynth",
            @"EXECUTION_MODE": @"exe_script_file"
        },
        @{
            @"NAME": @"OMCSynth",
            @"COMMAND_ID": @"OMCSynth.declared",
            @"EXECUTION_MODE": @"exe_script_file"
        }
    ];

    NSDictionary *scripts = @{
        // Undeclared - must be synthesized and dispatchable:
        @"OMCSynth.action_one.sh":    @"#!/bin/bash\necho 'synth_output_action_one'\n",
        @"OMCSynth_action_two.sh":    @"#!/bin/bash\necho 'synth_output_action_two'\n",
        // Unrecognized prefix - synthesis falls back to the first command group:
        @"Unrelated.thing.sh":        @"#!/bin/bash\necho 'synth_output_unrelated'\n",
        // Declared - both a plist entry and a script file exist for this ID:
        @"OMCSynth.declared.sh":      @"#!/bin/bash\necho 'synth_output_declared'\n",
        // Must NOT be synthesized (filtered by synthesis rules):
        @"lib_omc_synth_helper.sh":   @"#!/bin/bash\necho 'lib_helper'\n",
        @"lib.dot_helper.sh":         @"#!/bin/bash\necho 'lib_dot_helper'\n",
        @"main.sh":                   @"#!/bin/bash\necho 'synth_output_bare_main'\n",
        @"OMCSynth.main.sh":          @"#!/bin/bash\necho 'synth_output_group_main'\n",
    };

    sBundleURL = [OMCBundleTestHelper createTestBundle:@"OMCSyntheticCommandTests"
                                          withCommands:commands
                                               scripts:scripts];
    NSAssert(sBundleURL != nil, @"OMCSyntheticCommandTests: failed to create test .omc bundle");
}

+ (void)tearDown
{
    if (sBundleURL != nil) {
        [OMCBundleTestHelper removeTestBundle:sBundleURL];
        sBundleURL = nil;
    }
    [super tearDown];
}

/// Create an executor over the shared test bundle the same way OMCCommandExecutor
/// does for a ".omc" path, so command lookups here see the identical command list.
static OMCExecutorRef CreateExecutorForTestBundle(void)
{
    NSURL *bundleDirURL = [NSURL fileURLWithPath:[sBundleURL path] isDirectory:YES];
    return OMCCreateExecutor((__bridge CFURLRef)bundleDirURL);
}

// ---------------------------------------------------------------------------
#pragma mark - Positive: undeclared scripts must be synthesized and dispatchable
// ---------------------------------------------------------------------------

/// A script present in the Scripts directory but absent from Command.plist
/// must be synthesized so OMCCommandExecutor can dispatch it.
- (void)testUndeclaredScriptGetsSynthesized
{
    OMCTestExecutionObserver *obs = [OMCTestExecutionObserver new];
    OSStatus err = [OMCCommandExecutor runCommand:@"OMCSynth.action_one"
                                   forCommandFile:[sBundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:obs];

    XCTAssertEqual(err, noErr,
        @"Undeclared script commandID must be dispatched via synthesis (OSStatus %d)", (int)err);
    BOOL done = [obs waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(done, @"Script must complete within timeout");
    XCTAssertTrue([obs.capturedOutput containsString:@"synth_output_action_one"],
        @"Expected script output. Got: %@", obs.capturedOutput);
}

/// Underscore-separated script names must also be synthesized and dispatched.
- (void)testUndeclaredScriptWithUnderscoreSeparatorGetsSynthesized
{
    OMCTestExecutionObserver *obs = [OMCTestExecutionObserver new];
    OSStatus err = [OMCCommandExecutor runCommand:@"OMCSynth_action_two"
                                   forCommandFile:[sBundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:obs];

    XCTAssertEqual(err, noErr,
        @"Underscore-named undeclared script must be synthesized (OSStatus %d)", (int)err);
    BOOL done = [obs waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(done, @"Script must complete within timeout");
    XCTAssertTrue([obs.capturedOutput containsString:@"synth_output_action_two"],
        @"Expected script output. Got: %@", obs.capturedOutput);
}

/// When no declared group name matches the commandID prefix, the synthetic command
/// is assigned to the first command group and must still be dispatched successfully.
- (void)testUnrelatedPrefixScriptFallsBackToFirstGroup
{
    OMCTestExecutionObserver *obs = [OMCTestExecutionObserver new];
    OSStatus err = [OMCCommandExecutor runCommand:@"Unrelated.thing"
                                   forCommandFile:[sBundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:obs];

    XCTAssertEqual(err, noErr,
        @"Script with unrecognized prefix must fall back to first group and dispatch (OSStatus %d)", (int)err);
    BOOL done = [obs waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(done, @"Script must complete within timeout");
    XCTAssertTrue([obs.capturedOutput containsString:@"synth_output_unrelated"],
        @"Expected script output. Got: %@", obs.capturedOutput);
}

/// A command that IS declared in the plist must still execute correctly
/// even when a matching script file also exists (synthesis must not interfere).
- (void)testDeclaredCommandStillExecutes
{
    OMCTestExecutionObserver *obs = [OMCTestExecutionObserver new];
    OSStatus err = [OMCCommandExecutor runCommand:@"OMCSynth.declared"
                                   forCommandFile:[sBundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:obs];

    XCTAssertEqual(err, noErr,
        @"Declared command with matching script file must still execute (OSStatus %d)", (int)err);
    BOOL done = [obs waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(done, @"Script must complete within timeout");
    XCTAssertTrue([obs.capturedOutput containsString:@"synth_output_declared"],
        @"Expected declared script output. Got: %@", obs.capturedOutput);
}

// ---------------------------------------------------------------------------
#pragma mark - Reserved and filtered names
// ---------------------------------------------------------------------------
//
// NOTE on the two main-command cases below.
// "main" and "<CommandName>.main" are filtered out of synthesis, but unlike the
// "lib" cases that is NOT observable as a failed dispatch: they are the main
// command's implicit IDs. GetOneCommandParams normalizes an explicit COMMAND_ID of
// "main"/"<NAME>.main" to the internal 'top!' sentinel, and FindCommandIndex falls
// back to FindMainCommandByImplicitID, so both IDs resolve to the declared main
// command by design. Asserting a failed lookup here (runCommand: leaves its status
// at userCanceledErr when the ID does not resolve) would contradict the implicit-ID
// feature that NEXT_COMMAND_ID and ActionUI action IDs rely on.
//
// Consequence for coverage: when the bundle DOES declare a main command, the
// synthesis filter is invisible from here. An unfiltered main.sh would be normalized
// to 'top!' too and appended last, and every resolver takes the FIRST 'top!' entry,
// so nothing about dispatch changes. The two tests below therefore pin the
// resolution contract - which ID lands on which command, and which script that
// command runs - as their names say. The filter itself is
// covered by the two ...FilterIsNotSynthesized tests further down, which use a bundle
// with no declared main command so a leaked synthetic entry is the only possible 'top!'.

/// Scripts whose names start with "lib_" must not be synthesized as commands.
/// If synthesis incorrectly included them, OMCCommandExecutor would return noErr.
- (void)testLibUnderscorePrefixIsNotSynthesized
{
    OSStatus err = [OMCCommandExecutor runCommand:@"lib_omc_synth_helper"
                                   forCommandFile:[sBundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:nil];

    XCTAssertNotEqual(err, noErr,
        @"'lib_' prefixed script must not be synthesized as a dispatchable command");
}

/// Scripts whose names start with "lib." must not be synthesized as commands.
- (void)testLibDotPrefixIsNotSynthesized
{
    OSStatus err = [OMCCommandExecutor runCommand:@"lib.dot_helper"
                                   forCommandFile:[sBundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:nil];

    XCTAssertNotEqual(err, noErr,
        @"'lib.' prefixed script must not be synthesized as a dispatchable command");
}

/// The reserved ID "main" must resolve to the group's declared main command.
///
/// "main" is not an unknown ID: FindMainCommandByImplicitID() treats it as an implicit
/// ID of the first group's main command (the entry carrying the internal 'top!'
/// sentinel), so the lookup succeeds by design. The assertion is therefore about WHICH
/// command the ID resolves to, not about the lookup failing.
///
/// See testBareMainFilterIsNotSynthesized for the check that main.sh does not get a
/// synthetic entry at all; that cannot be observed here (see the section NOTE above).
- (void)testMainResolvesToDeclaredMainCommand
{
    OMCExecutorRef executor = CreateExecutorForTestBundle();
    XCTAssertTrue(executor != NULL, @"Should create an executor for the test bundle");

    OMCCommandRef mainCommandRef = OMCFindCommand(executor, NULL); // NULL -> first group's main command
    OMCCommandRef bareMainRef = OMCFindCommand(executor, CFSTR("main"));
    OMCReleaseExecutor(executor);

    XCTAssertTrue(OMCIsValidCommandRef(mainCommandRef),
        @"Test bundle must declare a main command");
    XCTAssertEqual(bareMainRef, mainCommandRef,
        @"'main' must resolve to the declared main command");

    // End to end: dispatching "main" must run the main command's script, which is
    // OMCSynth.main.sh - CreateScriptPathAndShell prefers "<NAME>.main" over "main"
    // for a 'top!' command, so main.sh must not be what runs.
    OMCTestExecutionObserver *obs = [OMCTestExecutionObserver new];
    OSStatus err = [OMCCommandExecutor runCommand:@"main"
                                   forCommandFile:[sBundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:obs];

    XCTAssertEqual(err, noErr,
        @"'main' is the main command's implicit ID and must dispatch (OSStatus %d)", (int)err);
    BOOL done = [obs waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(done, @"Script must complete within timeout");
    XCTAssertTrue([obs.capturedOutput containsString:@"synth_output_group_main"],
        @"Expected the main command's script. Got: %@", obs.capturedOutput);
    XCTAssertFalse([obs.capturedOutput containsString:@"synth_output_bare_main"],
        @"main.sh must not run for a group that has a <NAME>.main script. Got: %@", obs.capturedOutput);
}

/// The implicit ID "<CommandName>.main" must resolve to that group's declared main
/// command. "<CommandName>.main.sh" is the main-command script for its group
/// (analogous to the legacy "main.sh").
///
/// As with bare "main", "<CommandName>.main" is that main command's implicit ID and
/// resolves on purpose, so the check is that it lands on the declared main command.
///
/// See testDotMainFilterIsNotSynthesized for the check that <NAME>.main.sh does not get
/// a synthetic entry at all; that cannot be observed here (see the section NOTE above).
- (void)testDotMainResolvesToDeclaredMainCommand
{
    OMCExecutorRef executor = CreateExecutorForTestBundle();
    XCTAssertTrue(executor != NULL, @"Should create an executor for the test bundle");

    OMCCommandRef mainCommandRef = OMCFindCommand(executor, NULL); // NULL -> first group's main command
    OMCCommandRef dotMainRef = OMCFindCommand(executor, CFSTR("OMCSynth.main"));
    OMCReleaseExecutor(executor);

    XCTAssertTrue(OMCIsValidCommandRef(mainCommandRef),
        @"Test bundle must declare a main command");
    XCTAssertEqual(dotMainRef, mainCommandRef,
        @"'<CommandName>.main' must resolve to the declared main command");

    OMCTestExecutionObserver *obs = [OMCTestExecutionObserver new];
    OSStatus err = [OMCCommandExecutor runCommand:@"OMCSynth.main"
                                   forCommandFile:[sBundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:obs];

    XCTAssertEqual(err, noErr,
        @"'<CommandName>.main' is the main command's implicit ID and must dispatch (OSStatus %d)", (int)err);
    BOOL done = [obs waitForCompletionWithTimeout:kDefaultExecutionTimeout];
    XCTAssertTrue(done, @"Script must complete within timeout");
    XCTAssertTrue([obs.capturedOutput containsString:@"synth_output_group_main"],
        @"Expected the main command's script. Got: %@", obs.capturedOutput);
}

/// Direct coverage for the "main" rule in the synthesis filter.
///
/// The bundle below declares exactly one command and it carries an explicit,
/// non-main COMMAND_ID, so nothing in the plist normalizes to the 'top!' sentinel:
/// the bundle has NO main command. main.sh is present but must be filtered out of
/// synthesis. Drop that filter and main.sh is synthesized with COMMAND_ID "main",
/// GetOneCommandParams normalizes it to 'top!', and the bundle suddenly HAS a main
/// command - which is what this asserts against.
///
/// This is the deterministic complement to testMainResolvesToDeclaredMainCommand: a
/// leaked entry is the only possible 'top!' here, so detection does not depend on
/// where among the appended synthetic entries it happens to land.
///
/// Fixture assumption: the script filenames' case must match what GetOneCommandParams
/// normalizes, which compares case-SENSITIVELY ("main", "<NAME>.main"), even though the
/// synthesis filter itself works on a lowercased key. Spelling these "Main.sh" or
/// "nomain.main.sh" would leave the tests passing while detecting nothing.
- (void)testBareMainFilterIsNotSynthesized
{
    NSArray *commands = @[
        @{
            @"NAME": @"NoMain",
            @"COMMAND_ID": @"NoMain.action",
            @"EXECUTION_MODE": @"exe_script_file"
        }
    ];
    NSDictionary *scripts = @{
        // Undeclared: must be synthesized, and is the control proving synthesis ran.
        // The declared NoMain.action deliberately has no script - it is only ever
        // looked up, never dispatched, so a script for it would be dead fixture data.
        @"NoMain.probe.sh":  @"#!/bin/bash\necho 'filter_probe_synthesis'\n",
        @"main.sh":          @"#!/bin/bash\necho 'filter_leak_bare_main'\n",
    };

    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"OMCSynth_BareMainFilter_Test"
                                                withCommands:commands
                                                     scripts:scripts];
    XCTAssertNotNil(bundleURL, @"Should create the no-main test bundle");

    NSURL *bundleDirURL = [NSURL fileURLWithPath:[bundleURL path] isDirectory:YES];
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFURLRef)bundleDirURL);
    XCTAssertTrue(executor != NULL, @"Should create an executor for the no-main test bundle");

    // Two positive controls, because the negative assertions below are absences and
    // would otherwise hold on a bundle that never got off the ground.
    // declaredRef proves the plist parsed; it resolves from COMMAND_LIST alone.
    // probeRef proves the Scripts scan ran, which declaredRef cannot show:
    // createTestBundle logs and continues when a script write fails, so a fixture
    // with no scripts at all still returns a usable bundle URL, and with nothing to
    // synthesize the "no 'top!' entry" assertion would pass having tested nothing.
    OMCCommandRef declaredRef = OMCFindCommand(executor, CFSTR("NoMain.action"));
    OMCCommandRef probeRef = OMCFindCommand(executor, CFSTR("NoMain.probe"));
    OMCCommandRef mainCommandRef = OMCFindCommand(executor, NULL);
    OMCReleaseExecutor(executor);

    XCTAssertTrue(OMCIsValidCommandRef(declaredRef),
        @"The bundle's declared command must resolve - otherwise the checks below prove nothing");
    XCTAssertTrue(OMCIsValidCommandRef(probeRef),
        @"NoMain.probe.sh must be synthesized - otherwise the script scan never ran and the check below proves nothing");
    XCTAssertFalse(OMCIsValidCommandRef(mainCommandRef),
        @"main.sh must not be synthesized: this bundle declares no main command, so no entry may carry 'top!'");

    OSStatus err = [OMCCommandExecutor runCommand:@"main"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:nil];

    XCTAssertNotEqual(err, noErr,
        @"'main' must not resolve when the only declared command has an explicit non-main COMMAND_ID");

    [OMCBundleTestHelper removeTestBundle:bundleURL];
}

/// Direct coverage for the "<CommandName>.main" rule in the synthesis filter, using
/// the same no-declared-main bundle shape as testBareMainFilterIsNotSynthesized.
///
/// NoMain.main.sh matches the declared group's NAME, so if the filter were dropped it
/// would be synthesized as COMMAND_ID "NoMain.main", which GetOneCommandParams
/// normalizes to 'top!' - again turning a bundle with no main command into one that
/// has one.
- (void)testDotMainFilterIsNotSynthesized
{
    NSArray *commands = @[
        @{
            @"NAME": @"NoMain",
            @"COMMAND_ID": @"NoMain.action",
            @"EXECUTION_MODE": @"exe_script_file"
        }
    ];
    NSDictionary *scripts = @{
        // Undeclared: must be synthesized, and is the control proving synthesis ran.
        // The declared NoMain.action deliberately has no script - it is only ever
        // looked up, never dispatched, so a script for it would be dead fixture data.
        @"NoMain.probe.sh":  @"#!/bin/bash\necho 'filter_probe_synthesis'\n",
        @"NoMain.main.sh":   @"#!/bin/bash\necho 'filter_leak_dot_main'\n",
    };

    NSURL *bundleURL = [OMCBundleTestHelper createTestBundle:@"OMCSynth_DotMainFilter_Test"
                                                withCommands:commands
                                                     scripts:scripts];
    XCTAssertNotNil(bundleURL, @"Should create the no-main test bundle");

    NSURL *bundleDirURL = [NSURL fileURLWithPath:[bundleURL path] isDirectory:YES];
    OMCExecutorRef executor = OMCCreateExecutor((__bridge CFURLRef)bundleDirURL);
    XCTAssertTrue(executor != NULL, @"Should create an executor for the no-main test bundle");

    // Positive controls: see testBareMainFilterIsNotSynthesized for why both are needed.
    OMCCommandRef declaredRef = OMCFindCommand(executor, CFSTR("NoMain.action"));
    OMCCommandRef probeRef = OMCFindCommand(executor, CFSTR("NoMain.probe"));
    OMCCommandRef mainCommandRef = OMCFindCommand(executor, NULL);
    OMCReleaseExecutor(executor);

    XCTAssertTrue(OMCIsValidCommandRef(declaredRef),
        @"The bundle's declared command must resolve - otherwise the checks below prove nothing");
    XCTAssertTrue(OMCIsValidCommandRef(probeRef),
        @"NoMain.probe.sh must be synthesized - otherwise the script scan never ran and the check below proves nothing");
    XCTAssertFalse(OMCIsValidCommandRef(mainCommandRef),
        @"NoMain.main.sh must not be synthesized: this bundle declares no main command");

    OSStatus err = [OMCCommandExecutor runCommand:@"NoMain.main"
                                   forCommandFile:[bundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:nil];

    XCTAssertNotEqual(err, noErr,
        @"'<CommandName>.main' must not resolve when the group declares no main command");

    [OMCBundleTestHelper removeTestBundle:bundleURL];
}

// ---------------------------------------------------------------------------
#pragma mark - Edge cases
// ---------------------------------------------------------------------------

/// An empty COMMAND_LIST must not crash during synthesis; the command is simply not found.
- (void)testEmptyCommandListDoesNotCrash
{
    NSURL *emptyBundleURL = [OMCBundleTestHelper createTestBundle:@"OMCSynth_Empty_Test"
                                                     withCommands:@[]
                                                          scripts:@{}];
    XCTAssertNotNil(emptyBundleURL, @"Should create empty test bundle");

    OSStatus err = [OMCCommandExecutor runCommand:@"OMCSynth.action_one"
                                   forCommandFile:[emptyBundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:nil];

    // mCommandList is null/empty - synthesis returns early - the command is not found.
    XCTAssertNotEqual(err, noErr, @"Command must not be found in an empty command list");

    [OMCBundleTestHelper removeTestBundle:emptyBundleURL];
}

@end

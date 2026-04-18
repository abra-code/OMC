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
//  it, so SynthesizeCommandsFromScripts() searches that bundle — never the
//  host process bundle (xctest / Xcode Agents directory).
//
//  NOTE on OMCScriptsManager caching:
//  SynthesizeCommandsFromScripts() delegates to OMCScriptsManager::GetAllScriptPaths(),
//  which builds and caches the per-bundle script dictionary on first access. Scripts
//  placed in the bundle before any cache entry is built are always visible. Because
//  OMCBundleTestHelper writes all files before returning the bundle URL, this is
//  guaranteed automatically.
//

#import "OMCTestCase.h"
#import "OMCBundleTestHelper.h"
#import "OMCCommandExecutor.h"
#import "OMCTestExecutionObserver.h"

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
        // Undeclared — must be synthesized and dispatchable:
        @"OMCSynth.action_one.sh":    @"#!/bin/bash\necho 'synth_output_action_one'\n",
        @"OMCSynth_action_two.sh":    @"#!/bin/bash\necho 'synth_output_action_two'\n",
        // Unrecognized prefix — synthesis falls back to the first command group:
        @"Unrelated.thing.sh":        @"#!/bin/bash\necho 'synth_output_unrelated'\n",
        // Declared — both a plist entry and a script file exist for this ID:
        @"OMCSynth.declared.sh":      @"#!/bin/bash\necho 'synth_output_declared'\n",
        // Must NOT be synthesized (filtered by synthesis rules):
        @"lib_omc_synth_helper.sh":   @"#!/bin/bash\necho 'lib_helper'\n",
        @"lib.dot_helper.sh":         @"#!/bin/bash\necho 'lib_dot_helper'\n",
        @"main.sh":                   @"#!/bin/bash\necho 'main_script'\n",
        @"OMCSynth.main.sh":          @"#!/bin/bash\necho 'group_main_script'\n",
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
#pragma mark - Negative: filtered names must not be synthesized
// ---------------------------------------------------------------------------

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

/// A script named "main" must not be synthesized (reserved internal ID).
/// If synthesis incorrectly included it, dispatching "main" would return noErr.
- (void)testMainReservedNameIsNotSynthesized
{
    OSStatus err = [OMCCommandExecutor runCommand:@"main"
                                   forCommandFile:[sBundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:nil];

    XCTAssertNotEqual(err, noErr,
        @"The reserved name 'main' must not be synthesized as a command entry");
}

/// A script named "<CommandName>.main.sh" is the main-command script for its group
/// (analogous to the legacy "main.sh"). It must NOT receive a synthetic command entry
/// because the plist already declares a matching group command without a COMMAND_ID.
- (void)testDotMainSuffixIsNotSynthesized
{
    OSStatus err = [OMCCommandExecutor runCommand:@"OMCSynth.main"
                                   forCommandFile:[sBundleURL path]
                                      withContext:nil
                                     useNavDialog:NO
                         allowKeyWindowSubcommand:NO
                                         delegate:nil];

    XCTAssertNotEqual(err, noErr,
        @"'<CommandName>.main' script must not be synthesized as a separate command entry");
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

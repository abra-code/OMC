//
//  OMCTestHost.h
//  Abracode
//
//  The integration-test surface: what lets `appletbuilder itest` drive a real applet through the
//  real engine (Private/applet-integration-testing-design.md). Dormant unless the applet is
//  launched for a test, which means both of these in its environment:
//
//    OMC_TEST_TOKEN_FD     a descriptor (3 or above) to read the test's bridge token from: up to
//                          128 characters of [A-Za-z0-9_-], ended by a newline or end of file
//    OMC_TEST_BRIDGE_PATH  where to bind the ActionUI remote bridge, in a private directory of
//                          the harness's
//
//  Then, before app.will.launch runs, the engine reads and closes the descriptor, removes both
//  variables (so no handler inherits them), checks OMCGetTestSurfaceStatus (Platform/OMCTestability.h),
//  starts the bridge at that path at once instead of with the first window, registers the token
//  under the label "omc.test" and adds these methods next to the bridge's own actionui.* ones:
//
//    omc.test.status      {} -> {idle, activeCommands, scheduledRuns, activity}
//                         idle: no command at work and no runCommand waiting to start. activity
//                         changes with every start or end of work, so a client that reads the same
//                         activity twice, some time apart, knows the applet has settled.
//    omc.test.runCommand  {commandID, text?, files?, keyWindow?} -> {run}
//                         Runs a command as its menu item would, on the next main-thread turn, so
//                         the reply never waits for the command. text is the text context, files
//                         (absolute paths) the file context; files win. keyWindow (default false)
//                         lets an OMC key window take it as its subcommand, as the menu does; the
//                         window then runs it and the run observes nothing (dispatchedToWindow). To
//                         act in a window, perform a control's action instead (below). A command
//                         that needs files and gets none does not run (no open panel).
//    omc.test.log         {run?} -> {runs: [{run, commandID, started, finished, status, canceled,
//                         dispatchedToWindow, output}]}
//                         What each runCommand run did: status is the start's OSStatus; output is
//                         the text its tasks reported to observers; finished turns true when all its
//                         tasks ended, or at once when it started none. A command whose tasks are
//                         torn down before they finish (a dialog canceled first) may never report
//                         finished: wait on omc.test.status, which is the engine's own count.
//    omc.test.quit        {} -> {quitting: true}
//                         Terminates the applet normally, so app.will.terminate runs.
//
//  and turns on the bridge's actionui.performAction {window, viewID, viewPartID?, property?, context?},
//  which fires a control's action as a click does: through ActionUI's action handler into the
//  engine's, so the control's actionID reaches its command exactly as it would for a user.
//
//  A test launch that cannot be honored (the build or signature refuses the surface, the token or
//  the path is unusable, the bridge does not start) prints the reason to stderr and exits with
//  status 78 (EX_CONFIG), rather than running as an applet the harness cannot reach.
//
//  Main thread only.
//

#pragma once

#ifdef __cplusplus
extern "C" {
#endif //__cplusplus

// Called once, early in launch (OMCAppLifetimeEvents, before app.will.launch). Does nothing for a
// normal launch.
void OMCTestHostStartIfRequested(void);

// True after a test launch set the surface up.
bool OMCTestHostIsActive(void);

#ifdef __cplusplus
}
#endif //__cplusplus

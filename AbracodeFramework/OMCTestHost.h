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
//    omc.test.runCommand  {commandID, text?, files?, keyWindow?, openPanel?} -> {run}
//                         Runs a command as its menu item would, on the next main-thread turn, so
//                         the reply never waits for the command. text is the text context, files
//                         (absolute paths) the file context; files win. keyWindow (default false)
//                         lets an OMC key window take it as its subcommand, as the menu does; the
//                         window then runs it and the run observes nothing (dispatchedToWindow). To
//                         act in a window, perform a control's action instead (below). A command
//                         that needs files and gets none does not run, unless openPanel is true
//                         (default false): then it asks for them in the open panel, as the menu
//                         does, and the panel takes a queued answer (omc.test.answer).
//    omc.test.answer      {kind: "save", path} | {kind: "open", paths} | {kind: "cancel"} -> {pending}
//                         Queues the answer to the next save or open panel the engine shows (a
//                         Command.json SAVE_AS_DIALOG, CHOOSE_FILE_DIALOG, CHOOSE_FOLDER_DIALOG,
//                         CHOOSE_OBJECT_DIALOG or OPEN_OBJECT_DIALOG); panels take answers in the
//                         order queued. Paths are absolute. An answer that the panel could not have
//                         given (the wrong kind of panel, an open path that does not exist, a folder
//                         where the panel takes only files or the other way round, several paths
//                         where it takes one, a save path that names a folder or whose folder
//                         does not exist) cancels the panel and is reported in its record. The
//                         panel's allowed content types are recorded but not checked against the
//                         answer. pending: answers not yet taken.
//    omc.test.panels      {clear?} -> {panels: [{kind, title, message, prompt, defaultName,
//                         defaultDirectory, identifier, allowedContentTypes, canChooseFiles,
//                         canChooseDirectories, allowsMultiple, paths, canceled, problem}], pending}
//                         Every panel the engine asked for, in order, with what it was answered:
//                         paths when it was given an answer, canceled true otherwise; problem says
//                         why an answer was refused, or "no answer was queued". Fields the panel
//                         did not set are left out. clear true forgets the records and drops the
//                         answers not yet taken, after this reply is made.
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
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif //__cplusplus

// Called once, early in launch (OMCAppLifetimeEvents, before app.will.launch). Does nothing for a
// normal launch.
void OMCTestHostStartIfRequested(void);

// True after a test launch set the surface up.
bool OMCTestHostIsActive(void);

// A save or open panel in a test launch (OMCFilePanels.cpp): records it and answers it from the
// queue instead of showing it. Same arguments and results as Platform/OMCFilePanels.h: the chosen
// URL(s), retained, or NULL for canceled. Call only when OMCTestHostIsActive().
CFURLRef OMCTestHostAnswerSavePanel(CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inFlags);
CFArrayRef OMCTestHostAnswerOpenPanel(CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inFlags);

#ifdef __cplusplus
}
#endif //__cplusplus

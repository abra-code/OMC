//
//  OMCAppleScriptRunner.h
//  Abracode
//
//  EXECUTION_MODE exe_applescript (and with an output window): running an AppleScript and getting
//  its result as text. macOS: the Open Scripting Architecture (Platform/Apple/OMCAppleScriptRunner.cp).
//  Linux (later): not available; the run fails with an error.
//
//  Main thread only. The run is synchronous.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

// Called now and then while the script runs (to keep a progress window alive)
typedef void (*OMCAppleScriptStillRunningProc)(void *inContext);

// Compiles and runs inScript. outResult receives the result as text (retained; NULL when there is
// none) even when the script fails. Returns the scripting error, or userCanceledErr (-128) when the
// user pressed Command-period. inStillRunning may be NULL.
OSStatus OMCRunAppleScript(CFStringRef inScript, OMCAppleScriptStillRunningProc inStillRunning, void *inContext, CFStringRef *outResult);

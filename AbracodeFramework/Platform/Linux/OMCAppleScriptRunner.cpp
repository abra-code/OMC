//
//  OMCAppleScriptRunner.cpp (Linux)
//  Abracode
//
//  The Linux implementation of Platform/OMCAppleScriptRunner.h: Linux has no AppleScript, so
//  EXECUTION_MODE exe_applescript fails with unimpErr and says so in the log. Not built yet: the
//  Linux port has no build.
//

#include "OMCAppleScriptRunner.h"
#include "OMCPlatformTypes.h"
#include "OMCLog.h"

OSStatus OMCRunAppleScript(CFStringRef inScript, OMCAppleScriptStillRunningProc inStillRunning, void *inContext, CFStringRef *outResult)
{
	(void)inScript;
	(void)inStillRunning;
	(void)inContext;
	if(outResult != nullptr)
		*outResult = nullptr;
	OMCLogMessage("OMC: a command asks for AppleScript (EXECUTION_MODE exe_applescript), which this system does not have");
	return unimpErr;
}

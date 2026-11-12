//
//  OMCPlatformStubs.cpp
//  Abracode
//
//  Every platform function the portable engine calls that has no Linux implementation yet (OMC 6.0
//  Phase 6, Private/phase6-linux-build-design.md). Each logs once that it is missing and gives the
//  answer that means "not available": no window, no clipboard text. With them libAbracode.so links
//  with -z defs, so a function that Linux lacks is a link error rather than a surprise when an
//  applet runs.
//
//  This file is Phase 7's work list: a function that gets a real Linux implementation moves to its
//  own file in Platform/Linux (named as its Platform/Apple counterpart, or OMCPlatform<name> when the
//  portable engine has a file of that name) and leaves this one.
//

#include "OMCTerminalLauncher.h"
#include "OMCTestPlatform.h"
#include "OMCLog.h"
#include <atomic>
#include <unistd.h>

// Logs the first call of each missing function, so a run shows what it needed and did not get
#define OMC_LINUX_NOT_YET(inName) \
	do \
	{ \
		static std::atomic<bool> sLogged { false }; \
		if(!sLogged.exchange(true)) \
			OMCLogMessage("%s is not implemented on Linux yet", inName); \
	} while(0)

#pragma mark - Terminal (Platform/OMCTerminalLauncher.h)

void
OMCExecuteInTerminal(CFStringRef inCommand, bool openInNewWindow, bool bringToFront)
{
	(void)inCommand;
	(void)openInNewWindow;
	(void)bringToFront;
	OMC_LINUX_NOT_YET("OMCExecuteInTerminal");
}

void
OMCExecuteInITerm(CFStringRef inCommand, CFStringRef inShellPath, bool openInNewWindow, bool bringToFront)
{
	(void)inCommand;
	(void)inShellPath;
	(void)openInNewWindow;
	(void)bringToFront;
	OMC_LINUX_NOT_YET("OMCExecuteInITerm");
}

bool OMCIsShDefaultInTerminal() { return false; }
bool OMCIsShDefaultInITerm() { return false; }

#pragma mark - Test host's window access (Platform/OMCTestPlatform.h)

bool OMCTestPlatformDispatchToKeyWindow(CFStringRef inCommandNameOrId, CFTypeRef inContext) { (void)inCommandNameOrId; (void)inContext; OMC_LINUX_NOT_YET("OMCTestPlatformDispatchToKeyWindow"); return false; }
bool OMCTestPlatformHasWindow(CFStringRef inWindowUUID) { (void)inWindowUUID; OMC_LINUX_NOT_YET("OMCTestPlatformHasWindow"); return false; }
bool OMCTestPlatformDispatchToWindow(CFStringRef inWindowUUID, CFStringRef inCommandNameOrId, CFTypeRef inContext) { (void)inWindowUUID; (void)inCommandNameOrId; (void)inContext; OMC_LINUX_NOT_YET("OMCTestPlatformDispatchToWindow"); return false; }
bool OMCTestPlatformCloseWindow(CFStringRef inWindowUUID) { (void)inWindowUUID; OMC_LINUX_NOT_YET("OMCTestPlatformCloseWindow"); return false; }
void OMCTestPlatformRequestQuit(void) { OMC_LINUX_NOT_YET("OMCTestPlatformRequestQuit"); }

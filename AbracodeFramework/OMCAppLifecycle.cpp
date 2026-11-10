//
//  OMCAppLifecycle.cpp
//  Abracode
//
//  See OMCAppLifecycle.h. Was the body of OMCAppLifetimeEvents.mm's notification handlers.
//

#include "OMCAppLifecycle.h"
#include "OMCCommandRunner.h"
#include "OMCPrivateConstants.h"
#include "OMCTestHost.h"
#include "OMCActionUIAddOns.h"
#include "OMCActionUIRemoteHost.h"
#include "DebugSettings.h"
#include "CFObj.h"
#include <cstdlib>
#include <climits>
#include <unistd.h>
#include "OMCAppletSupportURL.h"

namespace
{

// Python writes bytecode caches next to the source by default, which for an embedded interpreter
// means INSIDE the app bundle - files we did not sign, breaking the code signature seal.
// OmcExecutor exports PYTHONPYCACHEPREFIX (OmcExecutor.cp) for the script handlers IT spawns, but
// that only covers its own children. Anything spawned from inside the app process inherits the
// APP's environment, which never carried the variable - most visibly ActionUIChat's ACP agent,
// which in turn spawns MCP stdio servers off the bundled python and had them cache into the
// bundle. Setting it on our own process is what makes the variable actually inheritable, so every
// descendant gets it without each spawn site having to know about it.
//
// Guarded on the embedded interpreter for the same reason OmcExecutor guards its export: with no
// bundled Python there is nothing of ours to redirect, and we must not silently relocate the
// caches of a system python a handler happens to call.
//
// Not overwritten if already present (setenv overwrite=0), mirroring the add-if-absent semantics
// of CFDictionaryAddValue in OmcExecutor: a deliberately set external value is honored, and any
// prefix keeps the caches out of the bundle, which is the point. The honoring reaches this process
// only - CreateEnviron (omc_popen.c) merges the per-command dictionary OVER the real environ key
// by key, so a spawned handler sees OmcExecutor's value rather than an inherited one.
//
// The interpreter only has to exist (access F_OK follows a symbolic link, as the
// -[NSFileManager fileExistsAtPath:] check this replaces did).
//
// An eager "python3 -m compileall" of the handler scripts used to run here too; it was disabled
// on 2026-08-23 (CPython never reads a bytecode cache for __main__, and the call cost 23.7 ms of
// every launch to save 2.1 ms once). The measurements and the test that established it are kept
// with OMCGetPythonPycachePrefix in Platform/Apple/OMCAppLifecycleObserver.mm.
void SetPythonPycachePrefixIfEmbedded()
{
	CFObj<CFURLRef> pythonURL( OMCCopyAppletSupportURL(CFSTR("Library/Python/bin/python3"), false) );
	char pythonPath[PATH_MAX];
	if( (pythonURL == nullptr) || !::CFURLGetFileSystemRepresentation(pythonURL, true, (UInt8 *)pythonPath, sizeof(pythonPath)) )
		return;
	if(::access(pythonPath, F_OK) != 0)
		return;
	const char *pycachePrefix = OMCGetPythonPycachePrefix();
	if(pycachePrefix != nullptr)
		::setenv("PYTHONPYCACHEPREFIX", pycachePrefix, 0);
}

// The applet's command for the event, with no context: no open panel for a command that needs
// files, and no key-window routing
void RunLifecycleCommand(CFStringRef inCommandID)
{
	OMCRunHooks hooks = {};
	(void)OMCRunCommandFromFile(inCommandID, CFSTR("Command.plist"), nullptr, false, false, nullptr, false, &hooks);
}

} // namespace

void
OMCHandleAppLifecycleEvent(OMCAppLifecycleEvent inEvent) noexcept
{
	switch(inEvent)
	{
		case OMCAppLifecycleEvent::WillLaunch:
			TRACE_CSTR("App will finish launching\n");
			// Before anything can spawn a child: this is what every descendant inherits from.
			SetPythonPycachePrefixIfEmbedded();
			// A launch for an integration test (OMCTestHost.h) sets up its bridge here, before any
			// command runs, so the test sees app.will.launch too; a normal launch is untouched.
			OMCTestHostStartIfRequested();
			// Register optional ActionUI add-on element types before any dialog window is built.
			OMCRegisterActionUIAddOns();
			RunLifecycleCommand(CFSTR("app.will.launch"));
			break;

		case OMCAppLifecycleEvent::DidLaunch:
			TRACE_CSTR("App did finish launching");
			RunLifecycleCommand(CFSTR("app.did.launch"));
			break;

		case OMCAppLifecycleEvent::DidActivate:
			TRACE_CSTR("App did become active");
			RunLifecycleCommand(CFSTR("app.did.activate"));
			break;

		case OMCAppLifecycleEvent::DidDeactivate:
			TRACE_CSTR("App did resign active");
			RunLifecycleCommand(CFSTR("app.did.deactivate"));
			break;

		case OMCAppLifecycleEvent::WillTerminate:
			TRACE_CSTR("App will terminate");
			RunLifecycleCommand(CFSTR("app.will.terminate"));
			// Last chance to unlink the socket: NSApplication's terminate ends in libc exit(), so
			// nothing that runs after the run loop would ever fire. ActionUIRemote keeps an atexit
			// backstop for hosts that skip this event entirely, but doing it here is the orderly path.
			OMCStopActionUIRemoteBridge();
			break;
	}
}

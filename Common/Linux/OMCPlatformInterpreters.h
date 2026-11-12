//
//  OMCPlatformInterpreters.h (Linux)
//
//  Which interpreter runs a command's script file, by the file's extension, and where an
//  installed Python may be: the platform half of the lookup in AbracodeFramework/OmcExecutor.cpp.
//  Header-only C++, as the macOS file of the same name in Common/Apple.
//
//  C++, not C: the tables are function-local statics of CFSTR strings, and on Linux CFSTR is a
//  statement expression, not a constant, which C cannot use to initialize a static (C++ makes
//  the table on the first call).
//
//  The shells keep their /bin paths: where /bin is merged into /usr/bin (Debian 12 and later,
//  Fedora, Ubuntu, Arch) both work, and Debian put them in /bin before. No AppleScript
//  (osascript) and no JavaScriptCore shell (jsc): Linux has neither, so .applescript, .scpt, .js
//  and .mjs scripts run with the platform's shell (bash, OMCPlatformShell.h), as any extension not
//  listed does, and .sh ones too. JavaScript is not supported on Linux: OMC never ran node, and
//  complete JavaScript applets can be built with ActionUI's Node.js language adapter, without OMC.
//

#pragma once

#ifndef __cplusplus
#error "OMCPlatformInterpreters.h is C++: on Linux CFSTR cannot initialize a static in C"
#endif

#include <CoreFoundation/CoreFoundation.h>
#include "OMCPlatformShell.h"
#include <stddef.h>

typedef struct OMCExtensionAndInterpreter
{
	CFStringRef extension; // compared case-insensitively
	CFStringRef interpreter;
} OMCExtensionAndInterpreter;

// The interpreters by script extension. Python ("py") is not here: the engine runs the applet's
// own Python when it has one, else an installed one (OMCPlatformInstalledPythonCandidates). An
// extension not listed runs with the platform's shell (OMCPlatformShell.h). In a function: on Linux CFSTR cannot initialize
// anything outside one.
static inline const OMCExtensionAndInterpreter *OMCPlatformInterpreters(size_t *outCount)
{
	static const OMCExtensionAndInterpreter sInterpreters[] =
	{
		{ CFSTR("sh"), CFSTR(OMC_PLATFORM_SHELL_PATH) }, // bash: OMCPlatformShell.h
		{ CFSTR("pl"), CFSTR("/usr/bin/perl") },
		{ CFSTR("zsh"), CFSTR("/bin/zsh") },
		{ CFSTR("bash"), CFSTR("/bin/bash") },
		{ CFSTR("csh"), CFSTR("/bin/csh") },
		{ CFSTR("tcsh"), CFSTR("/bin/tcsh") },
		{ CFSTR("dash"), CFSTR("/bin/dash") },
		{ CFSTR("rb"), CFSTR("/usr/bin/ruby") }
	};
	if(outCount != NULL)
		*outCount = sizeof(sInterpreters) / sizeof(sInterpreters[0]);
	return sInterpreters;
}

// Where an installed python3 may be, in the order tried (the first executable one wins),
// NULL-terminated: one built and installed by the user's administrator (the default prefix of
// Python's own build) ahead of the distribution's.
static inline const char * const *OMCPlatformInstalledPythonCandidates(void)
{
	static const char * const sCandidates[] =
	{
		"/usr/local/bin/python3",
		NULL
	};
	return sCandidates;
}

// The python3 used when none of the candidates is there: the distribution's.
static inline const char *OMCPlatformDefaultPython(void)
{
	return "/usr/bin/python3";
}

//
//  OMCPlatformInterpreters.h (Apple)
//
//  Which interpreter runs a command's script file, by the file's extension, and where an
//  installed Python may be: the platform half of the lookup in AbracodeFramework/OmcExecutor.cp.
//  Header-only C++, chosen by the header search path (Common/Apple or Common/Linux), as
//  OMCUserTempDirPlatform.h is.
//
//  C++, not C: the tables are function-local statics of CFSTR strings, and on Linux CFSTR is a
//  statement expression, not a constant, which C cannot use to initialize a static (C++ makes
//  the table on the first call).
//

#pragma once

#ifndef __cplusplus
#error "OMCPlatformInterpreters.h is C++: on Linux CFSTR cannot initialize a static in C"
#endif

#include <CoreFoundation/CoreFoundation.h>
#include <stddef.h>

typedef struct OMCExtensionAndInterpreter
{
	CFStringRef extension; // compared case-insensitively
	CFStringRef interpreter;
} OMCExtensionAndInterpreter;

// The interpreters by script extension. Python ("py") is not here: the engine runs the applet's
// own Python when it has one, else an installed one (OMCPlatformInstalledPythonCandidates). An
// extension not listed runs with /bin/sh. In a function: on Linux CFSTR cannot initialize
// anything outside one.
static inline const OMCExtensionAndInterpreter *OMCPlatformInterpreters(size_t *outCount)
{
	static const OMCExtensionAndInterpreter sInterpreters[] =
	{
		{ CFSTR("sh"), CFSTR("/bin/sh") },
		{ CFSTR("pl"), CFSTR("/usr/bin/perl") },
		{ CFSTR("applescript"), CFSTR("/usr/bin/osascript") },
		{ CFSTR("scpt"), CFSTR("/usr/bin/osascript") },
		{ CFSTR("zsh"), CFSTR("/bin/zsh") }, // the default shell since macOS 10.15
		{ CFSTR("bash"), CFSTR("/bin/bash") },
		{ CFSTR("csh"), CFSTR("/bin/csh") },
		{ CFSTR("tcsh"), CFSTR("/bin/tcsh") },
		{ CFSTR("dash"), CFSTR("/bin/dash") },
		{ CFSTR("rb"), CFSTR("/usr/bin/ruby") },
		{ CFSTR("js"), CFSTR("/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc") }, // macOS 10.15 and later; OMC needs 11
		{ CFSTR("mjs"), CFSTR("/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc") }
	};
	if(outCount != NULL)
		*outCount = sizeof(sInterpreters) / sizeof(sInterpreters[0]);
	return sInterpreters;
}

// Where an installed python3 may be, in the order tried (the first executable one wins),
// NULL-terminated. pyenv or conda Pythons need their shell setup first, so a GUI app cannot use
// them.
static inline const char * const *OMCPlatformInstalledPythonCandidates(void)
{
	static const char * const sCandidates[] =
	{
		"/Library/Frameworks/Python.framework/Versions/Current/bin/python3", // the python.org installer
		"/opt/homebrew/bin/python3", // Homebrew on Apple silicon (a link)
		"/usr/local/bin/python3", // Homebrew on Intel, or the python.org installer (a link)
		"/opt/local/bin/python3", // MacPorts
		NULL
	};
	return sCandidates;
}

// The python3 used when none of the candidates is there: the system's stub, which runs the
// Python 3 of Xcode or its command line tools.
static inline const char *OMCPlatformDefaultPython(void)
{
	return "/usr/bin/python3";
}

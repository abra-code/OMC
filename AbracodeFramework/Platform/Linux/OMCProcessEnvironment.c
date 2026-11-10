//
//  OMCProcessEnvironment.c
//  Abracode
//
//  Linux implementation of Platform/OMCProcessEnvironment.h. Not built yet: the Linux port has no
//  build. glibc and musl both export environ to shared libraries.
//

#include "OMCProcessEnvironment.h"

extern char **environ;

char **
OMCGetProcessEnviron(void)
{
	return environ;
}

// SWIFT_BACKTRACE=enable=no: on kernels with 16 KiB pages (Raspberry Pi 5, the agent-vm box) every
// process that loads the Swift runtime prints two lines on standard error when its crash backtracer
// starts ("unable to protect path to swift-backtrace ... disabling backtracing"), and on Linux OMC's
// helper tools load it (through CoreFoundation), so $(plister ... 2>&1) in a script would get them
// in its result. replay's tests set the same. A user who wants Swift backtraces in a child sets the
// variable, which then wins.
static const OMCChildEnvironmentDefault sChildEnvironmentDefaults[] =
{
	{ "SWIFT_BACKTRACE", "enable=no" }
};

const OMCChildEnvironmentDefault *
OMCGetChildEnvironmentDefaults(size_t *outCount)
{
	if(outCount != NULL)
		*outCount = sizeof(sChildEnvironmentDefaults) / sizeof(sChildEnvironmentDefaults[0]);
	return sChildEnvironmentDefaults;
}

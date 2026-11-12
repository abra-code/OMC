//
//  OMCPlatformShell.h (Apple)
//
//  The shell that runs a command line (omc_popen.c, when the command names no POPEN_SHELL) and a
//  script file with no extension, or one with no interpreter of its own (OmcExecutor.cpp,
//  OMCPlatformInterpreters.h). C, so that omc_popen.c can use it. On macOS /bin/sh is bash in
//  POSIX mode, which the commands and scripts of every applet so far were written for.
//

#pragma once

#define OMC_PLATFORM_SHELL_PATH "/bin/sh"

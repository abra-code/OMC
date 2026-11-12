//
//  OMCPlatformShell.h (Linux)
//
//  The shell that runs a command line (omc_popen.c, when the command names no POPEN_SHELL) and a
//  script file with no extension, or one with no interpreter of its own, or a .sh one (OmcExecutor.cpp,
//  OMCPlatformInterpreters.h). C, so that omc_popen.c can use it.
//
//  bash, not /bin/sh: on macOS /bin/sh is bash in POSIX mode, and the commands and scripts of
//  applets written there use bash's features ([[ ]], arrays, ${var//x/y}, local, source), as does
//  the ActionUI shell client a handler sources. Debian's and Ubuntu's /bin/sh is dash, which runs
//  none of it. bash is installed on every distribution OMC runs on (Debian makes it essential).
//  A command line still runs with "sh" as its argv[0], which puts bash in POSIX mode as on macOS.
//  /bin rather than /usr/bin, as the other shells in OMCPlatformInterpreters.h.
//

#pragma once

#define OMC_PLATFORM_SHELL_PATH "/bin/bash"

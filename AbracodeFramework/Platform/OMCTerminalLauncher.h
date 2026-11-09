//
//  OMCTerminalLauncher.h
//  Abracode
//
//  EXECUTION_MODE exe_terminal and exe_iterm: running a command line in a terminal app, and which
//  shell syntax that terminal's default shell takes (the engine writes the environment setup in
//  it). macOS: Terminal and iTerm through Apple events and their preferences
//  (Platform/Apple/OMCTerminalExecutor.cp, OMCiTermExecutor.cp). Linux (later): a terminal program
//  found on the system, or the modes refuse with an error.
//
//  Main thread only.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

void ExecuteInTerminal(CFStringRef inCommand, bool openInNewWindow, bool bringToFront);
void ExecuteInITerm(CFStringRef inCommand, CFStringRef inShellPath, bool openInNewWindow, bool bringToFront);

// Whether the terminal's default shell takes sh syntax (export), not csh or tcsh (setenv). Read once
// per process.
bool IsShDefaultInTerminal();
bool IsShDefaultInITerm();

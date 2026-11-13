//
//  OMCLinuxTerminal.h
//  Abracode
//
//  The terminal program OMCExecuteInTerminal starts on Linux (OMCTerminalLauncher.cpp), apart from
//  starting it, for tests (Linux/Tests/OMCLinuxPortTests).
//

#pragma once
#include <string>
#include <vector>

// The terminal's command line (the program's absolute path first) that runs inCommand in the shell
// inShell and then leaves that shell open, interactive; empty when no terminal program is on PATH.
std::vector<std::string> OMCLinuxTerminalArguments(const std::string &inCommand, const std::string &inShell);

// The terminal programs looked for, in order, for messages
const char *OMCLinuxTerminalNames();

/*
 *  OMCEnvironmentExportScript.h
 */

#pragma once
#include <CoreFoundation/CoreFoundation.h>

//if isSh = true use export
//if isSh = false use setenv

bool WriteEnvironmentSetupScriptToTmp(CFDictionaryRef inEnvironmentDict, CFStringRef inCommandGUID, bool isSh);
CFStringRef CreateEnvironmentSetupCommandForShell(CFStringRef inCommandGUID, bool isSh);
// Whether the user's login shell takes sh syntax (not csh or tcsh); the terminals' fallback
bool IsShDefaultLoginShell();


//
//  OMCAppletMain.h
//  Abracode
//
//  The Linux applet's entry: the applet executable's main is one call of this, as the macOS
//  stub (CommandApplet/main.m) is one call into the framework's app shell. Linux only.
//

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Runs the applet in the bundle the executable is in, until it quits; returns the exit status
int OMCAppletMain(int argc, char *argv[]);

#ifdef __cplusplus
}
#endif

//
//  OMCModalLoop.h
//  Abracode
//
//  The nested GLib main loops of the Linux platform code: a blocking window's modal run
//  (OMCWindowHost.cpp), an alert waiting for its answer (OMCPlatformAlerts.cpp). Each runs through
//  OMCRunModalLoop, so a quit can end them all: GApplication's quit stops only the application's own
//  loop, and a nested loop on the stack would otherwise keep the applet running. Linux only; main
//  thread only.
//

#pragma once

#include <glib.h>

// Runs inLoop until it is quit, by its owner or by OMCEndModalLoops
void OMCRunModalLoop(GMainLoop *inLoop);

// Quits every loop OMCRunModalLoop is running (each returns once control gets back to it)
void OMCEndModalLoops();

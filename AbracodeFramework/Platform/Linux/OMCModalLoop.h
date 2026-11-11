//
//  OMCModalLoop.h
//  Abracode
//
//  The nested GLib main loops of the Linux platform code: a blocking window's modal run
//  (OMCWindowHost.cpp), an alert or a file panel waiting for its answer (OMCPlatformAlerts.cpp,
//  OMCPlatformFilePanels.cpp). Each runs through OMCRunModalLoop, so a quit can end them all:
//  GApplication's quit stops only the application's own loop, and a nested loop on the stack would
//  otherwise keep the applet running. And the window such a dialog shows over. Linux only; main
//  thread only.
//

#pragma once

#include <gtk/gtk.h>

// Runs inLoop until it is quit, by its owner or by OMCEndModalLoops
void OMCRunModalLoop(GMainLoop *inLoop);

// Quits every loop OMCRunModalLoop is running (each returns once control gets back to it)
void OMCEndModalLoops();

// The window an alert, a notice or a file panel shows over: the application's active window when
// it is visible, else its first visible one (a window opened from a script is mapped but may not be active); nullptr
// when there is none, and the dialog is then a window of its own. The engine's calls name no window.
GtkWindow *OMCModalParentWindow();

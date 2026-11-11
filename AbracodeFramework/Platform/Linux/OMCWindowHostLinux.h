//
//  OMCWindowHostLinux.h
//  Abracode
//
//  What the Linux app shell asks of the Linux window host (Platform/Linux/OMCWindowHost.cpp) beyond
//  Platform/OMCWindowHost.h. Linux only.
//

#pragma once

// Ends every running modal run of a hosted window (RunModal's nested GLib main loop), so a quit
// reaches the application's own loop: GApplication's quit stops only that loop, and a modal run
// on the stack would otherwise keep the applet running. Main thread only.
void OMCEndHostedWindowModalRuns();

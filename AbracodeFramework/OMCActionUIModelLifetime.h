//
//  OMCActionUIModelLifetime.h
//  Abracode
//
//  When OMC forgets a closed ActionUI window's model. ActionUI keeps a window's model until its host
//  removes it, so without this every window an applet ever showed would stay for the life of the
//  process. But a command started for a window may read it through the ActionUI remote bridge while
//  it runs (actionui_remote's Window.from_environment(), omc_runtime_context_reference.md), the
//  window's end command above all: it starts as the window closes, before its process connects. So
//  every task of a command started for a window holds the window's model, and the model goes once
//  the window has closed and its last task has ended.
//
//  What a closed window offers such a command is a read of its last values. Nothing changes them
//  any more: the engine's own reads (special words, environment variables) and omc_dialog_control
//  end with the window's controller, as for nib windows. A process a handler leaves running in the
//  background is no task of the engine's, so it can lose the window once the window's tasks end.
//
//  Portable. Main thread only, like the task manager that calls it. The removal itself is platform
//  code (Platform/OMCActionUIModels.h).
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

// A task of a command started for the window was created (OmcTask). Holds the window's model.
void OMCActionUIModelHoldForTask(CFStringRef inWindowUUID);

// That task was destroyed. When the window has closed and this was its last task, the model goes.
void OMCActionUIModelReleaseForTask(CFStringRef inWindowUUID);

// The window closed and its controller went away. The model goes on the next main-thread turn if
// no task holds it by then, else with the window's last task. The next turn, not now: a blocking
// window's command starts its tasks after the window closed, in the turn that closed it.
void OMCActionUIModelWindowClosed(CFStringRef inWindowUUID);

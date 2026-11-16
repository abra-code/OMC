//
//  OMCInvoke.h
//  Abracode
//
//  omc_dialog_control's INVOKE: messages sent to a dialog's window, to the application or to the
//  shared workspace, each a selector and its arguments as strings
//  (`omc_dialog_control <window> omc_window omc_invoke setTitle: "A Title"`).
//
//  macOS: Objective-C messages through NSInvocation (Platform/Apple/OMCObjCInvoke.mm). Linux: not
//  supported, as documented; the call only logs (Platform/Linux/OMCInvoke.cpp). Main thread only.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

enum class OMCInvokeTarget
{
	window,			// the dialog's window: inNativeWindow (OMCHostedWindow::GetNativeWindow(), an NSWindow on macOS)
	application,	// the application (NSApp)
	workspace		// the shared workspace (NSWorkspace)
};

// inMessages: an array of messages, each an array of strings: the selector, then its arguments
void OMCInvokeMessages(OMCInvokeTarget inTarget, void *inNativeWindow, CFArrayRef inMessages) noexcept;

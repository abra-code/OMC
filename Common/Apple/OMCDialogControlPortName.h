//
//  OMCDialogControlPortName.h (Apple)
//
//  The name of the port a dialog receives omc_dialog_control's messages on, for the dialog
//  (OMCDialog.cpp) and the tool (omc_dialog_control/main.c) alike. One header per platform, chosen
//  by the header search path (Common/Apple or Common/Linux). Plain C: the tool is C.
//
//  Apple: a Mach port name under the app group (a sandboxed app may use only names under its
//  group), the group generated from DEVELOPMENT_TEAM into AppGroupIdentifier.h.
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include "AppGroupIdentifier.h"

// The port name for the dialog with inDialogUUID; inForListener is true for the dialog's own port
// (unused here). NULL when it cannot be made. The caller releases it.
static inline CFStringRef OMCCreateDialogControlPortName(const char *inDialogUUID, bool inForListener)
{
	(void)inForListener;
	if(inDialogUUID == NULL)
		return NULL;
	return CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%s.OMCDialogControlPort-%s"), GetAppGroupIdentifier(), inDialogUUID);
}

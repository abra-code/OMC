//
//  OMCDialogControlPortName.h (Linux)
//
//  The name of the port a dialog receives omc_dialog_control's messages on, the counterpart of the
//  Apple header of this name. Linux: the path of a Unix domain socket in the engine's private
//  per-user folder (OMCEngineTempDir.h), which the dialog and the tool find the same way; no app
//  group. This path can exceed the 107-byte limit on a socket's path when the folder is under a long
//  home path (no $XDG_RUNTIME_DIR), so both ends reach the socket through the folder's descriptor
//  (OMCUnixSocketAddress.h).
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stdio.h>
#include "OMCEngineTempDir.h"

// The port name for the dialog with inDialogUUID: the socket's path. inForListener is true for the
// dialog's own port, which makes the private folder when there is none; a sender only looks.
// NULL when it cannot be made. The caller releases it.
static inline CFStringRef OMCCreateDialogControlPortName(const char *inDialogUUID, bool inForListener)
{
	if(inDialogUUID == NULL)
		return NULL;
	char leafName[128];
	int n = snprintf(leafName, sizeof(leafName), "OMCDialogControlPort-%s", inDialogUUID);
	if((n < 0) || ((size_t)n >= sizeof(leafName)))
		return NULL;
	char path[PATH_MAX];
	if(!OMCGetEngineTempFilePath(leafName, inForListener, path, sizeof(path)))
		return NULL;
	return CFStringCreateWithCString(kCFAllocatorDefault, path, kCFStringEncodingUTF8);
}

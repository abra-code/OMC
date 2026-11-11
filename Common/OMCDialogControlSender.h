//
//  OMCDialogControlSender.h
//  Abracode
//
//  omc_dialog_control's side of a dialog's port: one message, sent to the dialog whose UUID the
//  script passed. The dialog's side is Platform/OMCMessagePortListener.h in the engine; the port's
//  name is OMCDialogControlPortName.h. One implementation per platform, chosen by the include path
//  like the port name: Common/Apple/OMCDialogControlSender.c (a CFMessagePort) and
//  Common/Linux/OMCDialogControlSender.c (a Unix domain socket in the engine's private folder).
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct OMCDialogControlSender OMCDialogControlSender;

// Reaches the port of the dialog with inDialogUUID. NULL in two cases, told apart by *outError:
// - 0: no dialog with that UUID is listening (not opened yet, or already closed); omc_dialog_control
//   then writes the message to the dialog's file, which a dialog reads when it opens;
// - nonzero: the dialog's port is there but could not be reached (Linux: its backlog stayed full for
//   the 5-second timeout while the dialog's main thread was busy); the message is not delivered, as a
//   send that timed out, and omc_dialog_control reports it.
OMCDialogControlSender *OMCDialogControlSenderOpen(const char *inDialogUUID, int *outError);

// Sends inMessage (a property list's data) and waits at most 5 seconds for the port to take it; no
// reply. 0 when sent; otherwise a nonzero code for the error message.
int OMCDialogControlSenderSend(OMCDialogControlSender *inSender, CFDataRef inMessage);

// Ends the connection; NULL does nothing.
void OMCDialogControlSenderClose(OMCDialogControlSender *inSender);

#ifdef __cplusplus
}
#endif

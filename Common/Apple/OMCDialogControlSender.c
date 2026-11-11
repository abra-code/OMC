//
//  OMCDialogControlSender.c (Apple)
//  Abracode
//
//  See Common/OMCDialogControlSender.h. macOS: the dialog's port is a CFMessagePort named after the
//  app group and the dialog's UUID (OMCDialogControlPortName.h). Moved from omc_dialog_control/main.c.
//

#include "OMCDialogControlSender.h"
#include "OMCDialogControlPortName.h"
#include <stdlib.h>

struct OMCDialogControlSender
{
	CFMessagePortRef remotePort;
};

OMCDialogControlSender *
OMCDialogControlSenderOpen(const char *inDialogUUID, int *outError)
{
	if(outError != NULL)
		*outError = 0; // a remote port is made only when the dialog listens; a slow one fails at the send
	CFStringRef portName = OMCCreateDialogControlPortName(inDialogUUID, false /*sender*/);
	if(portName == NULL)
		return NULL;
	CFMessagePortRef remotePort = CFMessagePortCreateRemote(kCFAllocatorDefault, portName); // non-null when the dialog listens
	CFRelease(portName);
	if(remotePort == NULL)
		return NULL;

	OMCDialogControlSender *sender = (OMCDialogControlSender *)calloc(1, sizeof(OMCDialogControlSender));
	if(sender == NULL)
	{
		CFRelease(remotePort);
		return NULL;
	}
	sender->remotePort = remotePort;
	return sender;
}

int
OMCDialogControlSenderSend(OMCDialogControlSender *inSender, CFDataRef inMessage)
{
	if((inSender == NULL) || (inMessage == NULL))
		return kCFMessagePortTransportError;
	return CFMessagePortSendRequest(inSender->remotePort, 0 /*msgid*/, inMessage, 5 /*send timeout*/, 0 /*rcv timeout*/, NULL /*kCFRunLoopDefaultMode*/, NULL /*replyData*/);
}

void
OMCDialogControlSenderClose(OMCDialogControlSender *inSender)
{
	if(inSender == NULL)
		return;
	if(inSender->remotePort != NULL)
		CFRelease(inSender->remotePort);
	free(inSender);
}

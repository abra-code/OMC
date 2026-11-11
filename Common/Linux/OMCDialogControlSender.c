//
//  OMCDialogControlSender.c (Linux)
//  Abracode
//
//  See Common/OMCDialogControlSender.h. Linux: the dialog's port is a Unix domain socket in the
//  engine's private folder (OMCDialogControlPortName.h, OMCUnixSocketAddress.h). One connection per
//  message: a 4-byte length in this machine's byte order, then the message; the dialog reads it and
//  closes, with no reply (Platform/Linux/OMCMessagePortListener.cpp is the other end).
//

#ifndef _GNU_SOURCE
#define _GNU_SOURCE // O_PATH (OMCUnixSocketAddress.h); C++ defines it on Linux already, C does not
#endif

#include "OMCDialogControlSender.h"
#include "OMCDialogControlPortName.h"
#include "OMCUnixSocketAddress.h"
#include <stdint.h>
#include <stdlib.h>
#include <sys/time.h>

struct OMCDialogControlSender
{
	int socketFD;
};

OMCDialogControlSender *
OMCDialogControlSenderOpen(const char *inDialogUUID, int *outError)
{
	if(outError != NULL)
		*outError = 0;
	CFStringRef portName = OMCCreateDialogControlPortName(inDialogUUID, false /*sender*/);
	if(portName == NULL)
		return NULL; // no private folder: no dialog has made a port in it
	char socketPath[4096];
	bool havePath = CFStringGetCString(portName, socketPath, sizeof(socketPath), kCFStringEncodingUTF8);
	CFRelease(portName);
	if(!havePath)
		return NULL;

	struct sockaddr_un address;
	int folderFD = OMCMakeUnixSocketAddress(socketPath, &address, NULL);
	if(folderFD < 0)
		return NULL;

	int socketFD = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if(socketFD < 0)
	{
		close(folderFD);
		return NULL;
	}
	// The 5-second send timeout of CFMessagePortSendRequest on macOS: a dialog whose main thread is
	// busy takes the connection into its backlog and reads it later
	struct timeval timeout = { 5, 0 };
	(void)setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

	int connected = connect(socketFD, (struct sockaddr *)&address, sizeof(address));
	close(folderFD); // the connection no longer needs the folder's descriptor
	if(connected != 0)
	{
		// ENOENT: no such dialog listens; ECONNREFUSED: a socket file left without a listener. Anything
		// else (EAGAIN: the backlog stayed full for the send timeout) means the dialog is there and
		// the message would be lost in the file it no longer reads: an error for the caller.
		int connectErrno = errno;
		close(socketFD);
		if( (outError != NULL) && (connectErrno != ENOENT) && (connectErrno != ECONNREFUSED) )
			*outError = connectErrno;
		return NULL;
	}

	OMCDialogControlSender *sender = (OMCDialogControlSender *)calloc(1, sizeof(OMCDialogControlSender));
	if(sender == NULL)
	{
		close(socketFD);
		return NULL;
	}
	sender->socketFD = socketFD;
	return sender;
}

static int
WriteAll(int inFD, const UInt8 *inBytes, size_t inLength)
{
	size_t written = 0;
	while(written < inLength)
	{
		// MSG_NOSIGNAL: a dialog that closes meanwhile gives EPIPE here rather than SIGPIPE killing the tool
		ssize_t n = send(inFD, inBytes + written, inLength - written, MSG_NOSIGNAL);
		if(n < 0)
		{
			if(errno == EINTR)
				continue;
			return errno; // EAGAIN: the send timeout passed; EPIPE or ECONNRESET: the dialog closed
		}
		if(n == 0)
			return EPIPE;
		written += (size_t)n;
	}
	return 0;
}

int
OMCDialogControlSenderSend(OMCDialogControlSender *inSender, CFDataRef inMessage)
{
	if((inSender == NULL) || (inMessage == NULL))
		return EINVAL;
	CFIndex length = CFDataGetLength(inMessage);
	if((length < 0) || ((uint64_t)length > UINT32_MAX))
		return EMSGSIZE;
	uint32_t header = (uint32_t)length;
	int result = WriteAll(inSender->socketFD, (const UInt8 *)&header, sizeof(header));
	if(result == 0)
		result = WriteAll(inSender->socketFD, CFDataGetBytePtr(inMessage), (size_t)length);
	return result;
}

void
OMCDialogControlSenderClose(OMCDialogControlSender *inSender)
{
	if(inSender == NULL)
		return;
	if(inSender->socketFD >= 0)
		close(inSender->socketFD);
	free(inSender);
}

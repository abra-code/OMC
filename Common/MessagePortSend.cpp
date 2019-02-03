/*
 *  MessagePortSend.cpp
 *  OnMyCommandCM
 *
 *  Created by Tomasz Kukielka on 11/25/06.
 *  Copyright 2006 Abracode. All rights reserved.
 *
 */

#include "MessagePortSend.h"
#include "CFObj.h"

SInt32
SendMessageToRemotePortWithoutResponse(CFStringRef inPort, SInt32 inMsgId, CFDataRef dataToSend)
{
	CFObj<CFMessagePortRef> remotePort( ::CFMessagePortCreateRemote(kCFAllocatorDefault, inPort) );
	if(remotePort != NULL)
	{
		return ::CFMessagePortSendRequest(
						remotePort,
						inMsgId,
						dataToSend, 
						10,//send timeout
						0,//rcv timout
						NULL, //kCFRunLoopDefaultMode
						NULL//replyData
						);		
	}
	return kCFMessagePortIsInvalid;
}

CFDataRef
SendMessageToRemotePortWithResponse(CFStringRef inPort, SInt32 inMsgId, CFDataRef dataToSend)
{
	CFDataRef outReplyData = NULL;
	CFObj<CFMessagePortRef> remotePort( ::CFMessagePortCreateRemote(kCFAllocatorDefault, inPort) );
	if(remotePort != NULL)
	{
		SInt32 result = ::CFMessagePortSendRequest(
						remotePort,
						inMsgId,
						dataToSend, 
						10,//send timeout
						10,//rcv timout
						kCFRunLoopDefaultMode,
						&outReplyData );
		if( (result != kCFMessagePortSuccess) && (outReplyData != NULL) )
		{
			::CFRelease(outReplyData);
			outReplyData = NULL;
		}
	}
	return outReplyData;
}

/*
 *  MessagePortListener.h
 *  Contextual Menu Workshop
 *
 *  Created by Tomasz Kukielka on 11/25/06.
 *  Copyright 2006 Abracode. All rights reserved.
 *
 */

#pragma once

#include <Carbon/Carbon.h>
#include "CFObj.h"

// "Receiver" class must implement ReceivePortMessage method as follows:
// CFDataRef	ReceivePortMessage( SInt32 msgid, CFDataRef inData );

template <class Receiver>
class MessagePortListener
{
public:
						MessagePortListener()
						{
						}

	virtual				~MessagePortListener()
						{
							StopListening();
						}

	OSStatus			StartListening(Receiver *inReceiver, CFStringRef inPortName)
						{
							StopListening();

#if _DEBUG_
							//::CFShow( ::CFRunLoopGetCurrent() );
							//CFStringRef outStr = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("MessagePortListener cfRunLoop=0x%x"), (void *) CFRunLoopGetCurrent() );
							//CFShow( outStr );
							//CFRelease(outStr);
#endif

							CFMessagePortContext messagePortContext = { 0, NULL, NULL, NULL, NULL };
							messagePortContext.info = (void *)inReceiver;

							if(inPortName != NULL)
							{
								mMessagePort.Adopt( ::CFMessagePortCreateLocal(kCFAllocatorDefault, inPortName,
														MessagePortCallback, &messagePortContext, NULL), kCFObjDontRetain );
							
								if(mMessagePort == NULL)
									return -1;

								mRunLoopSource.Adopt( ::CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, mMessagePort, 0), kCFObjDontRetain);
								if(mRunLoopSource == NULL)
								{
									mMessagePort.Release();
									return -1;
								}

								::CFRunLoopAddSource( ::CFRunLoopGetCurrent(), mRunLoopSource, kCFRunLoopCommonModes/*kCFRunLoopDefaultMode*/);
							}
							return noErr;
						}

	void				StopListening()
						{
							if(mMessagePort != NULL)
							{
								::CFMessagePortInvalidate(mMessagePort);
								mMessagePort.Release();
							}
							
							if( mRunLoopSource != NULL )
							{
								::CFRunLoopRemoveSource( ::CFRunLoopGetCurrent(), mRunLoopSource, kCFRunLoopCommonModes/*kCFRunLoopDefaultMode*/);
								mRunLoopSource.Release();
							}
						}

	bool				IsListening() { return (mMessagePort != NULL); }

//The Apple doc says:
//	If you want the message data to persist beyond this callback, you must explicitly create a copy of data rather than merely retain it;
//	the contents of data will be deallocated after the callback exits.
// BOth input and output data is released by system, we should not worry about it here, unless we want to keep the input data

	static CFDataRef	MessagePortCallback(CFMessagePortRef local, SInt32 msgid, CFDataRef inData, void *info)
						{
							#pragma unused (local)

							if(info == NULL)
								return NULL;

							Receiver *theReceiver = reinterpret_cast<Receiver *> (info);
							//get info from inData
							//inData will be released for us after callback returns
							return theReceiver->ReceivePortMessage(msgid, inData);
						}

protected:
	CFObj<CFMessagePortRef>		mMessagePort;
    CFObj<CFRunLoopSourceRef>	mRunLoopSource;
};
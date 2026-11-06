/*
 *  MessagePortListener.h
 *  Contextual Menu Workshop
 *
 *  Created by Tomasz Kukielka on 11/25/06.
 *  Copyright 2006 Abracode. All rights reserved.
 *
 */

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include "CFObj.h"
#include <mach/mach.h>

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
								// also in a mode of its own, for ServicePending()
								::CFRunLoopAddSource( ::CFRunLoopGetCurrent(), mRunLoopSource, ServicePendingMode());
								mRunLoop.Adopt( ::CFRunLoopGetCurrent(), kCFObjRetain );
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
								::CFRunLoopRemoveSource( ::CFRunLoopGetCurrent(), mRunLoopSource, ServicePendingMode());
								mRunLoopSource.Release();
							}
							mRunLoop.Release();
						}

	// Handles the messages already queued on the port before returning, and runs no other source.
	// Looping until a zero-timeout CFRunLoopRunInMode reports "timed out" is not enough: each pass
	// receives one Mach message from the mode's port set, and when that message is the run loop's
	// own wake-up or a timer firing, the pass reports "timed out" while the port still holds
	// messages. So this loops on the port's queue length, in a mode that holds only listener sources.
	// Must be called on the thread that started listening; elsewhere it does nothing.
	void				ServicePending()
						{
							if( (mRunLoopSource == NULL) || (mRunLoop == NULL) || (::CFRunLoopGetCurrent() != mRunLoop) )
								return;

							// Each pass handles a message or consumes a wake-up or timer message; the bound only
							// stops a sender that keeps the queue full from holding the caller here.
							const int kMaxPasses = 64;
							for(int pass = 0; (pass < kMaxPasses) && (PendingMessageCount() > 0); pass++)
								(void)::CFRunLoopRunInMode(ServicePendingMode(), 0, true /*returnAfterSourceHandled*/);
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
	static CFStringRef	ServicePendingMode()
						{
							return CFSTR("com.abracode.MessagePortListener.ServicePending");
						}

	// The number of messages waiting on the port's Mach receive right.
	mach_port_msgcount_t PendingMessageCount() const
						{
							if(mRunLoopSource == NULL)
								return 0;

							// Ask for a version 0 context, the larger one, so the copy fits whatever the source is;
							// the version copied back says which one it is.
							union
							{
								CFRunLoopSourceContext	version0;
								CFRunLoopSourceContext1	version1;
							} sourceContext = {};
							::CFRunLoopSourceGetContext(mRunLoopSource.Get(), &sourceContext.version0);
							if( (sourceContext.version1.version != 1) || (sourceContext.version1.getPort == NULL) )
								return 0;

							mach_port_t port = sourceContext.version1.getPort(sourceContext.version1.info);
							if(port == MACH_PORT_NULL)
								return 0;

							mach_port_status_t portStatus = {};
							mach_msg_type_number_t statusCount = MACH_PORT_RECEIVE_STATUS_COUNT;
							kern_return_t result = ::mach_port_get_attributes(mach_task_self(), port, MACH_PORT_RECEIVE_STATUS,
																			(mach_port_info_t)&portStatus, &statusCount);
							return (result == KERN_SUCCESS) ? portStatus.mps_msgcount : 0;
						}

	CFObj<CFMessagePortRef>		mMessagePort;
    CFObj<CFRunLoopSourceRef>	mRunLoopSource;
	CFObj<CFRunLoopRef>			mRunLoop; // the run loop the source was added to, for ServicePending()
};

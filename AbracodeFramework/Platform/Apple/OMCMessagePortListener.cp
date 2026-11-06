//
//  OMCMessagePortListener.cp
//  Abracode
//
//  macOS: a CFMessagePort. Its run loop source is in the common modes of the main run loop, and also in
//  a private mode that holds only listener sources, for ServicePending().
//

#include "OMCMessagePortListener.h"
#include "CFObj.h"
#include <mach/mach.h>

namespace
{

CFStringRef ServicePendingMode()
{
	return CFSTR("com.abracode.MessagePortListener.ServicePending");
}

struct ReceiveContext
{
	OMCMessagePortListener::Receive	receive;
	void *							context;
};

// The Apple doc says: if you want the message data to persist beyond this callback, you must explicitly
// create a copy of data rather than merely retain it; the contents of data will be deallocated after the
// callback exits.
CFDataRef MessagePortCallback(CFMessagePortRef, SInt32, CFDataRef inData, void *inInfo)
{
	const ReceiveContext *receiveContext = static_cast<const ReceiveContext *>(inInfo);
	if( (receiveContext != nullptr) && (inData != nullptr) )
		receiveContext->receive(receiveContext->context, inData);
	return nullptr; // omc_dialog_control does not wait for a reply
}

class CFMessagePortListener : public OMCMessagePortListener
{
public:
							CFMessagePortListener(Receive inReceive, void *inContext)
								: mReceiveContext{ inReceive, inContext }
							{
							}

							~CFMessagePortListener() override
							{
								if(mMessagePort != nullptr)
									::CFMessagePortInvalidate(mMessagePort); // also takes the source out of every mode
								if( (mRunLoopSource != nullptr) && (mRunLoop != nullptr) )
								{
									::CFRunLoopRemoveSource(mRunLoop, mRunLoopSource, kCFRunLoopCommonModes);
									::CFRunLoopRemoveSource(mRunLoop, mRunLoopSource, ServicePendingMode());
								}
							}

	bool					Start(CFStringRef inPortName)
							{
								CFMessagePortContext portContext = { 0, &mReceiveContext, nullptr, nullptr, nullptr };
								mMessagePort.Adopt( ::CFMessagePortCreateLocal(kCFAllocatorDefault, inPortName,
																				MessagePortCallback, &portContext, nullptr), kCFObjDontRetain );
								if(mMessagePort == nullptr)
									return false;

								mRunLoopSource.Adopt( ::CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, mMessagePort, 0), kCFObjDontRetain );
								if(mRunLoopSource == nullptr)
									return false;

								mRunLoop.Adopt( ::CFRunLoopGetCurrent(), kCFObjRetain );
								::CFRunLoopAddSource(mRunLoop, mRunLoopSource, kCFRunLoopCommonModes);
								::CFRunLoopAddSource(mRunLoop, mRunLoopSource, ServicePendingMode());
								return true;
							}

	// Looping until a zero-timeout CFRunLoopRunInMode reports "timed out" is not enough: each pass
	// receives one Mach message from the mode's port set, and when that message is the run loop's
	// own wake-up or a timer firing, the pass reports "timed out" while the port still holds
	// messages. So this loops on the port's queue length, in a mode that holds only listener sources.
	void					ServicePending() override
							{
								if( (mRunLoopSource == nullptr) || (mRunLoop == nullptr) || (::CFRunLoopGetCurrent() != mRunLoop) )
									return;

								// Each pass handles a message or consumes a wake-up or timer message; the bound only
								// stops a sender that keeps the queue full from holding the caller here.
								const int kMaxPasses = 64;
								for(int pass = 0; (pass < kMaxPasses) && (PendingMessageCount() > 0); pass++)
									(void)::CFRunLoopRunInMode(ServicePendingMode(), 0, true /*returnAfterSourceHandled*/);
							}

private:
	// The number of messages waiting on the port's Mach receive right
	mach_port_msgcount_t	PendingMessageCount() const
							{
								// Ask for a version 0 context, the larger one, so the copy fits whatever the source is;
								// the version copied back says which one it is.
								union
								{
									CFRunLoopSourceContext	version0;
									CFRunLoopSourceContext1	version1;
								} sourceContext = {};
								::CFRunLoopSourceGetContext(mRunLoopSource.Get(), &sourceContext.version0);
								if( (sourceContext.version1.version != 1) || (sourceContext.version1.getPort == nullptr) )
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

	ReceiveContext				mReceiveContext;	// the port's info points here, so it lives as long as the port
	CFObj<CFMessagePortRef>		mMessagePort;
	CFObj<CFRunLoopSourceRef>	mRunLoopSource;
	CFObj<CFRunLoopRef>			mRunLoop;
};

} // namespace

std::unique_ptr<OMCMessagePortListener>
OMCMessagePortListener::Create(CFStringRef inPortName, Receive inReceive, void *inContext)
{
	if( (inPortName == nullptr) || (inReceive == nullptr) )
		return nullptr;

	std::unique_ptr<CFMessagePortListener> listener( new CFMessagePortListener(inReceive, inContext) );
	if( !listener->Start(inPortName) )
		return nullptr;
	return listener;
}

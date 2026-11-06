//
//  OMCMessagePortListener.h
//  Abracode
//
//  A named local port that receives omc_dialog_control's messages for one dialog. Platform code:
//  - macOS: a CFMessagePort, whose run loop source is in the common modes of the main run loop;
//  - Linux: to be written with the Linux port (a Unix domain socket; see the port plan).
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <memory>

class OMCMessagePortListener
{
public:
	// Called on the main thread with each message; the data is valid only during the call
	typedef void (*Receive)(void *inContext, CFDataRef inMessage);

	// Main thread. Returns nullptr when the port cannot be created (for example, the name is taken).
	static std::unique_ptr<OMCMessagePortListener> Create(CFStringRef inPortName, Receive inReceive, void *inContext);

	// Main thread. Stops listening; no call starts afterwards.
	virtual					~OMCMessagePortListener() = default;

							OMCMessagePortListener(const OMCMessagePortListener &) = delete; // the port refers to its listener
	OMCMessagePortListener &	operator=(const OMCMessagePortListener &) = delete;

	// Main thread. Handles the messages already queued on the port before returning, and runs nothing else.
	virtual void			ServicePending() = 0;

protected:
							OMCMessagePortListener() = default;
};

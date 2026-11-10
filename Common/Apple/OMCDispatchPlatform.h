//
//  OMCDispatchPlatform.h (Apple)
//
//  The libdispatch calls that differ between the platforms. Header-only, one file per platform,
//  chosen by the header search path (Common/Apple or Common/Linux), as OMCUserTempDirPlatform.h is.
//

#pragma once

#include <dispatch/dispatch.h>

// A serial queue whose work the main thread waits for (StopPipeIO waits for its cancel handlers):
// user-interactive, the main thread's class, so the wait is not a priority inversion.
// NULL when it cannot be made.
static inline dispatch_queue_t OMCCreateSerialQueueForMainThreadWaits(const char *inLabel)
{
	dispatch_queue_attr_t attributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
	return dispatch_queue_create(inLabel, attributes);
}

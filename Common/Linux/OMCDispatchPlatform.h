//
//  OMCDispatchPlatform.h (Linux)
//
//  The libdispatch calls that differ between the platforms, the counterpart of the Apple header of
//  this name. Swift's corelibs libdispatch has no quality-of-service classes (no QOS_CLASS_* names,
//  and no priority inheritance), only the global queues' priorities.
//

#pragma once

#include <dispatch/dispatch.h>

// A serial queue whose work the main thread waits for (StopPipeIO waits for its cancel handlers):
// its work runs on the high-priority global queue, the nearest to Apple's user-interactive class.
// NULL when it cannot be made.
static inline dispatch_queue_t OMCCreateSerialQueueForMainThreadWaits(const char *inLabel)
{
	dispatch_queue_t queue = dispatch_queue_create(inLabel, DISPATCH_QUEUE_SERIAL);
	if(queue != NULL)
		dispatch_set_target_queue(queue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
	return queue;
}

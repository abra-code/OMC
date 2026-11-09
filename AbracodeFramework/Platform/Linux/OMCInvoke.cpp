//
//  OMCInvoke.cpp
//  Abracode
//
//  Linux implementation of Platform/OMCInvoke.h. Not built yet: the Linux port has no build.
//  INVOKE sends Objective-C messages, which have no counterpart on Linux: it is documented as
//  macOS-only (Phase 5 design note, decision 3), and a script that uses it gets a log line here.
//

#include "OMCInvoke.h"
#include "OMCLog.h"

void
OMCInvokeMessages(OMCInvokeTarget inTarget, void *inNativeWindow, CFArrayRef inMessages) noexcept
{
	(void)inTarget;
	(void)inNativeWindow;
	(void)inMessages;
	OMCLogMessage("omc_dialog_control omc_invoke is supported only on macOS; the messages were not sent");
}

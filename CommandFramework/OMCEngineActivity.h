//
//  OMCEngineActivity.h
//  Abracode
//
//  How busy the engine is, for the integration-test surface's omc.test.status (OMCTestHost.h).
//  Kept by OmcTaskManager.cpp: a command's task manager counts from its construction until it
//  finalizes, which is after its last task ended and after any NEXT_COMMAND_ID it started has
//  constructed its own task manager, so a chain of commands never reads as idle in between.
//

#pragma once

#ifdef __cplusplus
extern "C" {
#endif //__cplusplus

// Task managers constructed and not yet finalized. Any thread.
long OMCGetUnfinishedTaskManagerCount(void);

// A counter that changes whenever the engine starts or finishes a piece of work, so a client that
// sees the same value twice, some time apart, knows nothing happened in between. Any thread.
unsigned long OMCGetEngineActivityCount(void);

// Bumps that counter. Any thread.
void OMCNoteEngineActivity(void);

#ifdef __cplusplus
}
#endif //__cplusplus

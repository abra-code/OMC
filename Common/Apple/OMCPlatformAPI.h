//
//  OMCPlatformAPI.h (Apple)
//
//  The entry points of OMC.h that exist on one platform only, chosen by the header search path
//  (Common/Apple or Common/Linux). Included at the end of OMC.h, after the types they use; include
//  OMC.h, not this. Here: the Apple event forms of OMCRunCommand, OMCExamineContext and
//  OMCExecuteCommand (EntryPoints/Apple/OnMyCommandAE.cp), for the contextual menu host and
//  Apple event callers.
//

#pragma once

#include <CoreServices/CoreServices.h>

#ifdef __cplusplus
extern "C" {
#endif //__cplusplus

// ******** Simple command execution with AE context ********

//the same as OMCRunCommand() but takes AEDesc which may be text, file/alias or a list of files/aliases
//inContext should be treated as const (currently not modified by OMC)
//for some reason Carbon Menu Manager headers for CM plugins defined HandleSelection() with non-const AEDesc
//as if a return value was allowed (text selection replacement?). Not sure if there are apps using the return value though

OSStatus OMCRunCommandAE(CFTypeRef inPlistRef, CFStringRef inCommandNameOrID, AEDesc *inAEContext);

//pass kOmcUnspecifiedCommand in inCommandRef for all commands or valid command Ref for one command
//outCommandPairs may be NULL
//proceed only when this function returns noErr
OSStatus		OMCExamineContextAE( OMCExecutorRef inOMCExecutor, OMCCommandRef inCommandRef, const AEDesc *inAEContext, AEDescList *outCommandPairs );

//OMCExamineContextAE() must be called before calling OMCExecuteCommandAE()
OSStatus		OMCExecuteCommandAE( OMCExecutorRef inOMCExecutor, AEDesc *inAEContext, OMCCommandRef inCommandRef );

#ifdef __cplusplus
}
#endif //__cplusplus

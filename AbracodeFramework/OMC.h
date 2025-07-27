/*
 *  OMC.h
 *  Abracode.framework
 *
 *  Copyright 2002-2008 Abracode. All rights reserved.
 *
 */

#ifndef _OMC_H_
#define _OMC_H_ 

#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>

#ifdef __cplusplus
extern "C" {
#endif //__cplusplus

//Version information returned as integer number with 2 decimal places for each version field: MMmmbb (Major, minor, bugfix)
//It is calculated as follows: MM * 100 * 100 + mm * 100 + bb, for example:
//version 2.0.0 = 20000
//version 2.3.1 = 20301
//version 12.2.34 = 120234
UInt32 OMCGetCurrentVersion(void);

	
// ******** Simple command execution with CF context ******** 
	
//inPlistRef can either be:
//	1. A CFURLRef pointing to command description plist or .omc external bundle. If NULL, the default
//		plist file is used:	~/Library/Preferences/com.abracode.OnMyCommandCMPrefs.plist 
//	2. A CFDictionaryRef with content of command description plist already loaded
//inCommandNameOrID should be command name in plist or unique command ID. If NULL, the first command is executed
//inContext should be CFStringRef for text context, CFURLRef for one file or CFArrayRef for a list of files.
//		If CFArray is used it should contain CFURLRef items or CFStringRef items which will be interpreted as paths and translated into CFURLRefs

OSStatus OMCRunCommand(CFTypeRef inPlistRef, CFStringRef inCommandNameOrID, CFTypeRef inContext);



// ******** Simple command execution with AE context ******** 

//the same as OMCRunCommand() but takes AEDesc which may be text, file/alias or a list of files/aliases
//inContext should be treated as const (currently not modified by OMC)
//for some reason Carbon Menu Manager headers for CM plugins defined HandleSelection() with non-const AEDesc
//as if a return value was allowed (text selection replacement?). Not sure if there are apps using the return value though

OSStatus OMCRunCommandAE(CFTypeRef inPlistRef, CFStringRef inCommandNameOrID, AEDesc *inAEContext);



// ******** Lower level API for command execution ******** 

//contextual menu-like API for OMC as described in "Menu Manager Reference":
// http://developer.apple.com/cgi-bin/search.pl?&q=CMPluginExamineContext


typedef struct OnMyCommandCM * OMCExecutorRef;

typedef SInt32 OMCCommandRef;
extern const OMCCommandRef kOmcUnspecifiedCommand;

typedef struct OMCObserver * OMCObserverRef;

OMCExecutorRef	OMCCreateExecutor( CFTypeRef inPlistRef );
void			OMCReleaseExecutor( OMCExecutorRef inOMCExecutor );
void			OMCRetainExecutor( OMCExecutorRef inOMCExecutor );

OMCCommandRef	OMCFindCommand( OMCExecutorRef inOMCExecutor, CFStringRef inNameOrId );


#ifdef __cplusplus
	inline bool OMCIsValidCommandRef( OMCCommandRef inCommandRef ) { return (inCommandRef >= 0); }
#else
	#define OMCIsValidCommandRef(inCommandRef) ((inCommandRef) >= 0)
#endif //!__cplusplus

//pass kOmcUnspecifiedCommand in inCommandRef for all commands or valid command Ref for one command
//outCommandPairs may be NULL
//proceed only when this function returns noErr
OSStatus		OMCExamineContextAE( OMCExecutorRef inOMCExecutor, OMCCommandRef inCommandRef, const AEDesc *inAEContext, AEDescList *outCommandPairs );
OSStatus		OMCExamineContext( OMCExecutorRef inOMCExecutor, OMCCommandRef inCommandRef, CFTypeRef inContext );

	
//Querying for information about the command:
	
typedef enum OMCInfoType
{
	kOmcInfo_CommandObjects, //sizeof(UInt32)
	kOmcInfo_ActivationType, //sizeof(UInt32)
	kOmcInfo_ExecutionOptions //sizeof(UInt32)
} OMCInfoType;

	
//information for kOmcInfo_CommandObjects passed back as UInt32
enum
{
	kOmcCommandNoSpecialObjects				= 0x00000000,

	kOmcCommandContainsTextObject			= 0x00000001,
	kOmcCommandContainsFileObject			= 0x00000002,
	kOmcCommandContainsInputText			= 0x00000004,

	kOmcCommandContainsSaveAsDialog			= 0x00000010,
	kOmcCommandContainsChooseFileDialog		= 0x00000020,
	kOmcCommandContainsChooseFolderDialog	= 0x00000040,
	kOmcCommandContainsChooseObjectDialog	= 0x00000080
};

//information for kOmcInfo_ActivationType passed back as UInt32
enum
{
	kActiveAlways = 0,
	kActiveFile,
	kActiveFolder,
	kActiveFileOrFolder,
	kActiveFinderWindow,
	kActiveSelectedText,
	kActiveClipboardText,
	kActiveSelectedOrClipboardText,
	kActiveFolderExcludeFinderWindow,
	kActiveFileOrFolderExcludeFinderWindow
};
	
//information for kOmcInfo_ExecutionOptions passed back as UInt32
enum
{
	kExecutionOption_None = 0x00,
	kExecutionOption_UseNavDialogForMissingFileContext = 0x01
};

	
//Must call FindCommandIndex() to obtain valid OMCCommandRef before calling OMCGetCommandInfo()
OSStatus		OMCGetCommandInfo(OMCExecutorRef inOMCExecutor, OMCCommandRef inCommandRef, OMCInfoType infoType, void *outInfo);
	
//OMCExamineContext[AE]() must be called before calling OMCExecuteCommand[AE]()
OSStatus		OMCExecuteCommandAE( OMCExecutorRef inOMCExecutor, AEDesc *inAEContext, OMCCommandRef inCommandRef );
OSStatus		OMCExecuteCommand( OMCExecutorRef inOMCExecutor, OMCCommandRef inCommandRef );

typedef enum OmcObserverMessage
{
	kOmcObserverMessageNone			= 0x0000,
	kOmcObserverTaskFinished		= 0x0001, //tasks notifies its observers that it ended, data is NULL
	kOmcObserverTaskProgress		= 0x0002, //task notifies its observes about progress and may provide data for observer to process (CFStringRef for output text)
	kOmcObserverTaskCanceled		= 0x0004, //cancel message can be sent to task or to task manager
	kOmcObserverAllTasksFinished	= 0x0008, //data is NULL
	kOmcObserverAllMessages			= kOmcObserverTaskFinished | kOmcObserverTaskProgress | kOmcObserverTaskCanceled | kOmcObserverAllTasksFinished
} OmcObserverMessage;

typedef void (*OMCObserverCallback)( OmcObserverMessage inMessage, CFIndex inTaskID, CFTypeRef inResult, void *userData );

OMCObserverRef	OMCCreateObserver( UInt32 messagesOfInterest, OMCObserverCallback inCallback, void *userData );
void			OMCReleaseObserver( OMCObserverRef inObserver );
void			OMCRetainObserver( OMCObserverRef inObserver );
void			OMCAddObserver( OMCExecutorRef inOMCExecutor, OMCObserverRef inObserver );
void			OMCUnregisterObserver( OMCObserverRef inObserver );


#ifdef __cplusplus
}
#endif //__cplusplus

#endif //_OMC_H_

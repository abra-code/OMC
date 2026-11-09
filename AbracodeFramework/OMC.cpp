/*
 *  OMC.cpp
 *  Abracode
 *
 *  Created by Tomasz Kukielka on 12/18/07.
 *  Copyright 2007 Abracode. All rights reserved.
 *
 */

#include "OMC.h"
#include "CFObj.h"
#include "ACFType.h"
#include "OnMyCommand.h"

extern "C" UInt32 OMCGetCurrentVersion(void)
{
	return CURRENT_OMC_VERSION;
}

//inPlistRef can either be:
//	1. A CFURLRef pointing to command description plist or .omc external bundle. If NULL, the default
//		plist file is used:	~/Library/Preferences/com.abracode.OnMyCommandCMPrefs.plist 
//	2. A CFDictionaryRef with content of command description plist already loaded
//inCommandName should be command name in plist or unique command ID. If NULL first command is executed
//inContext should be CFStringRef for text context, CFURLRef for one file or CFArrayRef for a list of files.
//		If CFArray is used it should contain CFURLRef items or CFStringRef items which will be interpreted as paths and translated into CFURLRefs

extern "C" OSStatus OMCRunCommand(CFTypeRef inPlistRef, CFStringRef inCommandNameOrID, CFTypeRef inContext)
{
	OSStatus err = noErr;

	try
	{
		ARefCountedObj<OnMyCommand> omcPlugin(new OnMyCommand(inPlistRef), kARefCountDontRetain);
		omcPlugin->Init();
		SInt32 commandIndex = omcPlugin->FindCommandIndex(inCommandNameOrID);
		if(commandIndex < 0)
        {
            return fnfErr;
        }
        
		err = omcPlugin->ExamineContext(inContext, kCMCommandStart+commandIndex);
		if(err == noErr)
		{
			err = omcPlugin->ExecuteCommandRef(kCMCommandStart+commandIndex);
			omcPlugin->PostMenuCleanup();//currently doing nothing, just for completeness
		}
	}
	catch(...)
	{
		err = -1;
	}

#if _DEBUG_
	if(err != noErr)
	{
		CFObj<CFStringRef> debugStr(::CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("OMCRunCommand error = %d"), (int)err));
		::CFShow((CFStringRef)debugStr);
	}
#endif

	return err;
}

// OMC.h's Apple event functions (OMCRunCommandAE, OMCExamineContextAE, OMCExecuteCommandAE) are in
// EntryPoints/Apple/OnMyCommandAE.cp

extern "C" OMCExecutorRef OMCCreateExecutor(CFTypeRef inPlistRef)
{
	OMCExecutorRef omcPlugin = nullptr;
	try
	{
		omcPlugin = new OnMyCommand(inPlistRef);
		omcPlugin->Init();
	}
	catch(...)
	{
	
	}

	return omcPlugin;
}

extern "C" OSStatus OMCExamineContext(OMCExecutorRef inOMCExecutor, OMCCommandRef inCmdRef, CFTypeRef inContext, UInt32 inOptions)
{
	try
	{
		if(inOMCExecutor != nullptr)
        {
            // kOMCAllowContextMismatch (explicit applet execution) examines the context and prepares
            // runtime data but does not reject the command on an ACTIVATION_MODE mismatch. Without it
            // (contextual menu / service) a mismatch is gated with errAEWrongDataType.
            bool enforceActivationMatch = ((inOptions & kOMCAllowContextMismatch) == 0);
            return inOMCExecutor->ExamineContext(inContext, inCmdRef, enforceActivationMatch);
        }
	}
	catch(...)
	{

	}
	return paramErr;
}


extern "C" void OMCSetTriggerURL(OMCExecutorRef inOMCExecutor, CFStringRef inURL)
{
	try
	{
		if(inOMCExecutor != nullptr)
        {
            inOMCExecutor->SetTriggerURL(inURL);
        }
	}
	catch(...)
	{

	}
}

extern "C" OMCCommandRef OMCFindCommand(OMCExecutorRef inOMCExecutor, CFStringRef inNameOrId)
{
	OMCCommandRef outCommandRef = -1;

	try
	{
		if(inOMCExecutor != nullptr)
        {
            outCommandRef = inOMCExecutor->FindCommandIndex(inNameOrId);
        }

		if(outCommandRef >= 0)
        {
            return (kCMCommandStart+outCommandRef);
        }
	}
	catch(...)
	{
	
	}

	return -1;
}

extern "C" OSStatus OMCGetCommandInfo(OMCExecutorRef inOMCExecutor, OMCCommandRef inCommandRef, OMCInfoType infoType, void *outInfo)
{
	OSStatus err = paramErr;
	
	try
	{
		if(inOMCExecutor != nullptr)
		{
			if(OMCIsValidCommandRef(inCommandRef))
            {
                err = inOMCExecutor->GetCommandInfo(inCommandRef, infoType, outInfo);
            }
		}
	}
	catch(...)
	{
		err = -1;
	}
	
	return err;
}

extern "C" OSStatus OMCExecuteCommand(OMCExecutorRef inOMCExecutor, OMCCommandRef inCommandRef)
{
	OSStatus err = paramErr;

	try
	{
		if(inOMCExecutor != nullptr)
		{
			if(OMCIsValidCommandRef(inCommandRef))
            {
                err = inOMCExecutor->ExecuteCommandRef(inCommandRef);
            }
			inOMCExecutor->PostMenuCleanup();//currently does nothing
		}
	}
	catch(...)
	{
		err = -1;
	}

	return err;
}


extern "C" void OMCReleaseExecutor(OMCExecutorRef inOMCExecutor)
{
	try
	{
		if(inOMCExecutor != nullptr)
        {
            inOMCExecutor->Release();
        }
	}
	catch(...)
	{
	}
}

extern "C" void OMCRetainExecutor(OMCExecutorRef inOMCExecutor)
{
	try
	{
		if(inOMCExecutor != nullptr)
        {
            inOMCExecutor->Retain();
        }
	}
	catch(...)
	{
	}
}

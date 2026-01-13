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
#include "StAEDesc.h"
#include "CMUtils.h"
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
		ARefCountedObj<OnMyCommandCM> omcPlugin(new OnMyCommandCM(inPlistRef), kARefCountDontRetain);
		omcPlugin->Init();
		SInt32 commandIndex = omcPlugin->FindCommandIndex(inCommandNameOrID);
		if(commandIndex < 0)
        {
            return fnfErr;
        }
        
		err = omcPlugin->ExamineContext(inContext, kCMCommandStart+commandIndex);
		if(err == noErr)
		{
			err = omcPlugin->HandleSelection(nullptr, kCMCommandStart+commandIndex);
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

//the same as OMCRunCommand() but takes AEDesc which may be text, file or a list of files

extern "C" OSStatus OMCRunCommandAE(CFTypeRef inPlistRef, CFStringRef inCommandNameOrID, AEDesc *inAEContext)
{
	OSStatus err = noErr;

	try
	{
		ARefCountedObj<OnMyCommandCM> omcPlugin(new OnMyCommandCM(inPlistRef), kARefCountDontRetain);
		omcPlugin->Init();
		SInt32 commandIndex = omcPlugin->FindCommandIndex(inCommandNameOrID);
		if(commandIndex < 0)
        {
            return fnfErr;
        }

		StAEDesc replacementContext;
		if((inAEContext != nullptr) && (inAEContext->dataHandle != nullptr))
		{
			if((inAEContext->descriptorType != typeAEList) &&
				(inAEContext->descriptorType != typeUnicodeText) &&
				(inAEContext->descriptorType != typeChar) &&
				(inAEContext->descriptorType != typeCString) &&
				(inAEContext->descriptorType != typePString) &&
				(inAEContext->descriptorType != typeUTF16ExternalRepresentation) &&
				(inAEContext->descriptorType != typeUTF8Text))
			{//try to coerce to see if it might be a single file ref
			//make a list even if single file. preferrable because Finder in 10.3 or higher does that
				StAEDesc coercedRef;
				err = ::AECoerceDesc(inAEContext, typeFileURL, coercedRef);
				if(err == noErr)
				{
					err = ::AECreateList(nullptr, 0, false, replacementContext);
					if(err == noErr)
					{
						err = ::AEPutDesc(replacementContext, // the list
											0, // put at the end of our list
											coercedRef);
						inAEContext = replacementContext;
					}				
				}
			}
		}

		err = omcPlugin->ExamineContext(inAEContext, nullptr);
		if(err == noErr)
		{
			err = omcPlugin->HandleSelection(inAEContext, kCMCommandStart+commandIndex);
			omcPlugin->PostMenuCleanup();//currently doing nothing, just for completeness
		}
	}
	catch(...)
	{
		err = -1;
	}

	return err;
}


extern "C" OMCExecutorRef OMCCreateExecutor(CFTypeRef inPlistRef)
{
	OMCExecutorRef omcPlugin = nullptr;
	try
	{
		omcPlugin = new OnMyCommandCM(inPlistRef);
		omcPlugin->Init();
	}
	catch(...)
	{
	
	}

	return omcPlugin;
}

extern "C" OSStatus OMCExamineContextAE(OMCExecutorRef inOMCExecutor, OMCCommandRef inCmdRef, const AEDesc *inAEContext, AEDescList *outCommandPairs)
{
	try
	{
		if(inOMCExecutor != nullptr)
        {
            return inOMCExecutor->ExamineContext(inAEContext, inCmdRef, outCommandPairs);
        }
	}
	catch(...)
	{
	
	}
	return paramErr;
}

extern "C" OSStatus OMCExamineContext(OMCExecutorRef inOMCExecutor, OMCCommandRef inCmdRef, CFTypeRef inContext)
{
	try
	{
		if(inOMCExecutor != nullptr)
        {
            return inOMCExecutor->ExamineContext(inContext, inCmdRef);
        }
	}
	catch(...)
	{
	
	}
	return paramErr;
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

extern "C" OSStatus OMCExecuteCommandAE(OMCExecutorRef inOMCExecutor, AEDesc *inAEContext, OMCCommandRef inCommandRef)
{
	OSStatus err = paramErr;

	try
	{
		if(inOMCExecutor != NULL)
		{
			if(OMCIsValidCommandRef(inCommandRef))
            {
                err = inOMCExecutor->HandleSelection(inAEContext, inCommandRef);
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

extern "C" OSStatus OMCExecuteCommand(OMCExecutorRef inOMCExecutor, OMCCommandRef inCommandRef)
{
	OSStatus err = paramErr;

	try
	{
		if(inOMCExecutor != nullptr)
		{
			if(OMCIsValidCommandRef(inCommandRef))
            {
                err = inOMCExecutor->HandleSelection(nullptr, inCommandRef);
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

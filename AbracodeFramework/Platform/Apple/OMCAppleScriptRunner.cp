//
//  OMCAppleScriptRunner.cp
//  Abracode
//
//  The macOS implementation of Platform/OMCAppleScriptRunner.h: the default OSA scripting component,
//  as AppleScriptExecutor used it (moved from OmcExecutor.cp).
//

#include "OMCAppleScriptRunner.h"
#include "StAEDesc.h"
#include "CMUtils.h"
#include "OMCConstants.h"
#include "CFObj.h"
#include "DebugSettings.h"
#include <Carbon/Carbon.h>

namespace
{
	struct StillRunning
	{
		OMCAppleScriptStillRunningProc proc;
		void *context;
	};
}

// Called by the scripting component while the script runs: reports progress, and cancels on
// Command-period
static OSErr
OSAActiveProc(SRefCon refCon)
{
	StillRunning *stillRunning = (StillRunning *)refCon;
	if( (stillRunning != nullptr) && (stillRunning->proc != nullptr) )
		stillRunning->proc(stillRunning->context);

	Boolean isCanceled = ::CheckEventQueueForUserCancel();
	if(isCanceled)
		return userCanceledErr;

	return noErr;
}

OSStatus
OMCRunAppleScript(CFStringRef inScript, OMCAppleScriptStillRunningProc inStillRunning, void *inContext, CFStringRef *outResult)
{
	if(outResult != nullptr)
		*outResult = nullptr;
	if(inScript == nullptr)
		return noErr;

	ComponentInstance osaComponent = OpenDefaultComponent( kOSAComponentType, kOSAGenericScriptingComponentSubtype );
	if(osaComponent == nullptr)
		return noErr; // as before: no scripting component means nothing runs, without an error

	StillRunning stillRunning { inStillRunning, inContext };
	OSAActiveUPP activeUPP = ::NewOSAActiveUPP( OSAActiveProc );
	if(activeUPP != nullptr)
		/*OSAError err =*/ ::OSASetActiveProc( osaComponent, activeUPP, (SRefCon)&stillRunning );

	OSStatus err = noErr;
	{
		StAEDesc scriptDesc;
		err = CMUtils::CreateUniTextDescFromCFString(inScript, scriptDesc);
		if(err == noErr)
		{
			StAEDesc resultDesc;
			OSAError osaErr = ::OSADoScript(
								osaComponent,
								scriptDesc,
								kOSANullScript,
								typeUnicodeText,
								kOSAModeCompileIntoContext | kOSAModeCanInteract | kOSAModeDisplayForHumans,
								resultDesc);
			if(osaErr != noErr)
			{
				LOG_CSTR("OMC->OMCRunAppleScript. OSADoScript returned error: %d\n", (int)osaErr);
			}
			if(outResult != nullptr)
				*outResult = CMUtils::CreateCFStringFromAEDesc(resultDesc, kTextReplaceNothing);
			err = osaErr;
		}
	}

	::CloseComponent(osaComponent);
	if(activeUPP != nullptr)
		::DisposeOSAActiveUPP( activeUPP );
	return err;
}

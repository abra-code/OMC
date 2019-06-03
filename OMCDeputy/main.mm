#import <Cocoa/Cocoa.h>
#include <CoreFoundation/CoreFoundation.h>
#include "OmcExecutor.h"
#include "OmcTaskManager.h"
#include <unistd.h>
#include "ACFDict.h"
#include "ACFType.h"
#include "OnMyCommand.h"

typedef struct
{
	CFStringRef		command;//command text, we are responsible for releasing it
	CFStringRef		inputPipe;//input text, we are responsible for releasing it
	UInt16			executionMode;//as defined by OMC
	CFArrayRef		name;
	CFStringRef		dynamicName;
	CFDictionaryRef	outputWindowOptions;
	CFBundleRef		bundleRef;
	CFBundleRef		externBundle;
	CFStringRef		localizationTableName;
	CFArrayRef		popenShell;
	CFDictionaryRef environmentList;
	CFStringRef		taskManagerID;
	CFIndex			taskIndex;
} DeputyCommandDescription;

void GetCommandDescription(DeputyCommandDescription *outDesc, CFDictionaryRef inOneCommand);
void ExecuteCommand(DeputyCommandDescription *inDesc);
void ReleaseCommand(DeputyCommandDescription *inDesc);

CFDataRef OMCDeputyListenerProc(CFMessagePortRef local, SInt32 msgid, CFDataRef inData, void *info);

extern "C" int main (int argc, const char * argv[])
{
	int error = -1;
	CFObj<CFStringRef>	portName;

	TRACE_CFSTR(CFSTR("OMCDeputy starting up"));

	if(argc > 1)
	{
		const char *portStr = argv[1];
		if(portStr != nullptr)
		{
			int portNameLen = strlen(portStr);
			if(portNameLen > 0)
			{
				portName.Adopt( ::CFStringCreateWithCString( kCFAllocatorDefault, portStr, kCFStringEncodingUTF8 ) );
			}
		}
	}
    
    if( portName == nullptr)
        return -1;
	
    TRACE_CFSTR(CFSTR("OMCDeputy creating port:"));
	TRACE_CFSTR( (CFStringRef)portName );

    CFMessagePortContext messagePortContext = { 0, NULL, NULL, NULL, NULL };
	CFObj<CFMessagePortRef> localPort(CFMessagePortCreateLocal(kCFAllocatorDefault, portName, OMCDeputyListenerProc, &messagePortContext, nullptr));

	portName.Release();

	if(localPort != nullptr)
	{
        CFObj<CFRunLoopSourceRef> runLoopSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, localPort, 0);
        if(runLoopSource != nullptr)
        {
            CFRunLoopRef runLoopRef = CFRunLoopGetCurrent();
            CFRunLoopAddSource(runLoopRef, runLoopSource, kCFRunLoopCommonModes/*kCFRunLoopDefaultMode*/);
        
            error = NSApplicationMain(argc,  (const char **) argv);

            CFMessagePortInvalidate(localPort);
            CFRunLoopRemoveSource(runLoopRef, runLoopSource, kCFRunLoopDefaultMode);
        }
    }
    return error;
}


CFDataRef
OMCDeputyListenerProc(CFMessagePortRef local, SInt32 msgid, CFDataRef inData, void *info)
{
	DeputyCommandDescription theCommand;
	memset(&theCommand, 0, sizeof(theCommand));

	TRACE_CFSTR(CFSTR("OMCDeputy received message"));

    if(inData == nullptr)
		return nullptr;

    CFObj<CFPropertyListRef> theList = CFPropertyListCreateWithData( kCFAllocatorDefault, inData,
                                           kCFPropertyListImmutable, nullptr, nullptr);
	if(theList == nullptr)
		return nullptr;

    CFDictionaryRef resultDict = ACFType<CFDictionaryRef>::DynamicCast(theList);
	if( resultDict == nullptr )
        return nullptr;

	GetCommandDescription(&theCommand, resultDict);

	TRACE_CFSTR(CFSTR("OMCDeputy about to execute command"));

	try
	{
		ExecuteCommand(&theCommand);
	}
	catch(...)
	{
	
	}

	ReleaseCommand(&theCommand);

	TRACE_CFSTR(CFSTR("OMCDeputy finished executing command"));
    
    return nullptr;
//	sprintf(reply, "OK");
//    return CFDataCreate(kCFAllocatorDefault, reply, strlen(reply)+1);// inData and replyData will be released for us after callback returns
}


//we get a preprocessed command description with very few options

void
GetCommandDescription(DeputyCommandDescription *outDesc, CFDictionaryRef inOneCommand)
{
	CFStringRef theStr;
	ACFDict command(inOneCommand);

	command.CopyValue( CFSTR("NAME"), outDesc->name );
	command.CopyValue( CFSTR("DYNAMIC_NAME"), outDesc->dynamicName );
	command.CopyValue( CFSTR("COMMAND"), outDesc->command );
	command.CopyValue( CFSTR("STANDARD_INPUT_PIPE"), outDesc->inputPipe );

//execution
	if( command.GetValue( CFSTR("EXECUTION_MODE"), theStr ) )
	{
		if( (kCFCompareEqualTo == CFStringCompare( theStr, CFSTR("exe_silent"), 0)) ||
			(kCFCompareEqualTo == CFStringCompare( theStr, CFSTR("exe_silent_popen"), 0)) )
		{
			outDesc->executionMode = kExecSilentPOpen;
		}
		else if( kCFCompareEqualTo == CFStringCompare( theStr, CFSTR("exe_silent_system"), 0 ) )
		{
			outDesc->executionMode = kExecSilentSystem;
		}
		else if( kCFCompareEqualTo == CFStringCompare( theStr, CFSTR("exe_terminal"), 0 ) )
		{
			outDesc->executionMode = kExecTerminal;
		}
		else if( kCFCompareEqualTo == CFStringCompare( theStr, CFSTR("exe_iterm"), 0 ) )
		{
			outDesc->executionMode = kExecITerm;
		}
		else if( kCFCompareEqualTo == CFStringCompare( theStr, CFSTR("exe_popen_with_output_window"), 0 ) )
		{
			outDesc->executionMode = kExecPOpenWithOutputWindow;
		}
		else if( kCFCompareEqualTo == CFStringCompare( theStr, CFSTR("exe_applescript"), 0 ) )
		{
			outDesc->executionMode = kExecAppleScript;
		}
		else if( kCFCompareEqualTo == CFStringCompare( theStr, CFSTR("exe_applescript_with_output_window"), 0 ) )
		{
			outDesc->executionMode = kExecAppleScriptWithOutputWindow;
		}
		else if( kCFCompareEqualTo == CFStringCompare( theStr, CFSTR("exe_shell_script"), 0 ) )
		{
			outDesc->executionMode = kExecShellScript;
		}
		else if( kCFCompareEqualTo == CFStringCompare( theStr, CFSTR("exe_shell_script_with_output_window"), 0 ) )
		{
			outDesc->executionMode = kExecShellScriptWithOutputWindow;
		}
	}

//output window settings
	command.CopyValue( CFSTR("OUTPUT_WINDOW_SETTINGS"), outDesc->outputWindowOptions );//keep options. do not resolve now

//make bundles out of bundle paths

//	bundlePath
	if( command.GetValue(CFSTR("BUNDLE_PATH"), theStr) )
	{
		CFObj<CFURLRef> bundleURL( CFURLCreateWithFileSystemPath(kCFAllocatorDefault, theStr, kCFURLPOSIXPathStyle, true) );
		if(bundleURL != NULL)
			outDesc->bundleRef = CFBundleCreate(kCFAllocatorDefault, bundleURL);
	}

//	externalBundlePath
	if( command.GetValue(CFSTR("EXTERNAL_BUNDLE_PATH"), theStr) )
	{
		CFObj<CFURLRef> bundleURL( CFURLCreateWithFileSystemPath(kCFAllocatorDefault, theStr, kCFURLPOSIXPathStyle, true) );
		if(bundleURL != NULL)
			outDesc->externBundle = CFBundleCreate(kCFAllocatorDefault, bundleURL);
	}

	command.CopyValue( CFSTR("LOCALIZATION_TABLE_NAME"), outDesc->localizationTableName);

	command.CopyValue( CFSTR("POPEN_SHELL"), outDesc->popenShell );

	command.CopyValue( CFSTR("ENVIRONMENT_VARIABLES"), outDesc->environmentList );

	command.CopyValue( CFSTR("TASK_MANAGER_ID"), outDesc->taskManagerID );
	command.GetValue( CFSTR("TASK_INDEX"), outDesc->taskIndex );
}

void
ExecuteCommand(DeputyCommandDescription *inDesc)
{
	ARefCountedObj<OmcExecutor> theExec;
	Boolean isFinished = false;

	OmcDeputyTaskManager *taskManager = new OmcDeputyTaskManager();
	taskManager->SetHostMangerID(inDesc->taskManagerID);
	taskManager->SetTaskIndex(inDesc->taskIndex );

	CommandDescription commandDescription;//temporary command description, just to pass the params to executors - no retain-release here
	memset(&commandDescription, 0, sizeof(commandDescription));

	commandDescription.name = inDesc->name;
	commandDescription.outputWindowOptions = inDesc->outputWindowOptions;
	commandDescription.popenShell = inDesc->popenShell;
	commandDescription.localizationTableName = inDesc->localizationTableName;
	commandDescription.useDeputy = false;

	switch(inDesc->executionMode)
	{
		case kExecTerminal:
			//terminal execution not supported in delegate
		break;
		
		case kExecITerm:
			//terminal execution not supported in delegate
		break;

		case kExecSilentPOpen:
			theExec.Adopt( new POpenExecutor(commandDescription, inDesc->bundleRef, inDesc->environmentList) );
		break;
		
		case kExecSilentSystem:
			theExec.Adopt( new SystemExecutor(inDesc->bundleRef, false) );
		break;
		
		case kExecPOpenWithOutputWindow:
			theExec.Adopt( new POpenWithOutputExecutor(commandDescription, inDesc->dynamicName, inDesc->bundleRef, inDesc->externBundle, 
														inDesc->environmentList) );
		break;

		case kExecAppleScript:
			theExec.Adopt( new AppleScriptExecutor(commandDescription, NULL, inDesc->bundleRef, inDesc->externBundle, false) );
		break;
		
		case kExecAppleScriptWithOutputWindow:
			theExec.Adopt( new AppleScriptExecutor(commandDescription, inDesc->dynamicName, inDesc->bundleRef, inDesc->externBundle, true) );
		break;
		
		case kExecShellScript:
			theExec.Adopt( new ShellScriptExecutor(commandDescription, inDesc->bundleRef, inDesc->environmentList) );
		break;
		
		case kExecShellScriptWithOutputWindow:
			theExec.Adopt( new ShellScriptWithOutputExecutor(commandDescription, inDesc->dynamicName, inDesc->bundleRef, inDesc->externBundle,
															inDesc->environmentList) );
		break;
	}

	CFStringRef objName = NULL;
	if(theExec != NULL)
	{
		taskManager->AddTask( theExec, inDesc->command, inDesc->inputPipe, objName );
	}
	
	taskManager->Start();
}

void
ReleaseCommand(DeputyCommandDescription *inDesc)
{
	if(inDesc->command != NULL)
	{
		CFRelease(inDesc->command);
		inDesc->command = NULL;
	}

	if(inDesc->inputPipe != NULL)
	{
		CFRelease(inDesc->inputPipe);
		inDesc->inputPipe = NULL;
	}

	if(inDesc->name != NULL)
	{
		CFRelease(inDesc->name);
		inDesc->name = NULL;
	}

	if(inDesc->outputWindowOptions != NULL)
	{
		CFRelease(inDesc->outputWindowOptions);
		inDesc->outputWindowOptions = NULL;
	}

	if(inDesc->bundleRef != NULL)
	{
		CFRelease(inDesc->bundleRef);
		inDesc->bundleRef = NULL;
	}

	if(inDesc->externBundle != NULL)
	{
		CFRelease(inDesc->externBundle);
		inDesc->externBundle = NULL;
	}

	if(inDesc->popenShell != NULL)
	{
		CFRelease(inDesc->popenShell);
		inDesc->popenShell = NULL;
	}

	if(inDesc->environmentList != NULL)
	{
		CFRelease(inDesc->environmentList);
		inDesc->environmentList = NULL;
	}

	if(inDesc->taskManagerID != NULL)
	{
		CFRelease(inDesc->taskManagerID);
		inDesc->taskManagerID = NULL;
	}
}


void TerminateApplicationCallback(CFRunLoopTimerRef timer, void* info)
{
	if(timer != NULL)
	{
		CFRunLoopTimerInvalidate(timer);
		CFRelease(timer);
	}

	NSApplication *myApp = [NSApplication sharedApplication];
	if(myApp != NULL)
	{
		[myApp terminate:NULL];
	}
}


void TerminateApplication(CFTimeInterval inDelay)
{
	if(inDelay > 0.0)
	{
		CFRunLoopTimerContext timerContext = {0, NULL, NULL, NULL, NULL};
		CFRunLoopTimerRef autoCloseTimer = CFRunLoopTimerCreate(
											   kCFAllocatorDefault,
											   CFAbsoluteTimeGetCurrent() + inDelay,
											   0,		// interval
											   0,		// flags
											   0,		// order
											   TerminateApplicationCallback,
											   &timerContext);
		
		if(autoCloseTimer != NULL)
		{
			CFRunLoopAddTimer(CFRunLoopGetCurrent(), autoCloseTimer, kCFRunLoopCommonModes);
		}		
	}
	else
	{
		TerminateApplicationCallback(NULL, NULL);
	}
}


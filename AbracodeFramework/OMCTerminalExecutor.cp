/*
 *  OMCTerminalExecutor.cp
 *
 */

#include "StAEDesc.h"
#include "CMUtils.h"
#include "CFObj.h"
#include "ACFType.h"
#include "MoreAppleEvents.h"


#define kTerminalAppBundleID "com.apple.Terminal"

static OSErr SendEventToTerminal(const AEDesc &inCommandDesc, bool openInNewWindow, bool bringToFront);

void
ExecuteInTerminal(CFStringRef inCommand, bool openInNewWindow, bool bringToFront)
{
	if(inCommand == nullptr)
		return;
	
	OSStatus err = noErr;
	StAEDesc theCommandDesc;

	//Send UTF-16 text
	err = CMUtils::CreateUniTextDescFromCFString(inCommand, theCommandDesc);

	if(err != noErr)
		return;

	err = SendEventToTerminal(theCommandDesc, openInNewWindow, bringToFront);

	if(err == noErr)
		return;//sucess situation - we may exit now

	//terminal not running probably
	TRACE_CSTR("\tExecuteInTerminal. Trying to launch the application with LS\n" );
    CFObj<CFArrayRef> appList(LSCopyApplicationURLsForBundleIdentifier(CFSTR(kTerminalAppBundleID), nullptr));

	if((appList == nullptr) || CFArrayGetCount(appList) == 0)
	{
		LOG_CSTR( "OMC->ExecuteInTerminal. Could not find Terminal application. We give up now.\n" );
		return;
	}

    err = fnfErr;
    CFTypeRef oneItem = CFArrayGetValueAtIndex(appList, 0);
    CFURLRef oneURL = ACFType<CFURLRef>::DynamicCast(oneItem);
    if(oneURL != nullptr)
        err = LSOpenCFURLRef(oneURL, nullptr);

	if(err == noErr)
	{//Terminal is launching right now.
	//We cannot send an event to it right away because it is not ready yet
	//We cannot install a launch notify handler because we do not know if our host will be happy about this
	//Installing a deferred task is too much work :-) so we go the easy way:
	//we will wait one second and send event. We will try 10 times every one second to give plenty of time for the app to launch

		for(int i = 1; i <= 10; i++)
		{//we only try 10 times and then give up
			sleep(1); //wait 1 second before trying to send the event

			err = SendEventToTerminal(theCommandDesc, false, bringToFront);//after terminal launch a new window is open so never open another one
			
			if( (err == connectionInvalid) || (err == procNotFound) )
			{
				TRACE_CSTR("\tExecuteInTerminal. App still launching. Waiting...\n" );
				continue;
			}
			else 
				break;//either err == noErr (success), or some other error so we exit anyway
		}
		
		if(err != noErr)
		{
			LOG_CSTR( "OMC->ExecuteInTerminal. Event could not be sent to launched application, err = %d\n", (int)err );
		}
	}
	else
	{
		LOG_CSTR( "OMC->ExecuteInTerminal. LSOpenFromRefSpec failed, err = %d\n", (int)err );
	}
	
}

OSErr
SendEventToTerminal(const AEDesc &inCommandDesc, bool openInNewWindow, bool bringToFront)
{
	OSErr err = noErr;

	if( openInNewWindow )
	{
        err = CMUtils::SendAEWithObjToRunningApp( kTerminalAppBundleID, kAECoreSuite, kAEDoScript, keyDirectObject, inCommandDesc );
	}
	else
	{
		//find front window
		StAEDesc theFrontWindow;
        err = MoreAETellBundledAppToGetElementAt(
										kTerminalAppBundleID,
										cWindow,
										kAEFirst,
										typeWildCard,
										theFrontWindow);
		if(err == noErr)
		{
            err = CMUtils::SendAEWithTwoObjToRunningApp( kTerminalAppBundleID, kAECoreSuite, kAEDoScript, keyDirectObject, inCommandDesc, keyAEFile, theFrontWindow/*Desc*/ );
		}
			
		if( (err != noErr) && (err != connectionInvalid) && (err != procNotFound) )
		{//if for any reason the event cannot be sent to topmost window, try opening new window
            err = CMUtils::SendAEWithObjToRunningApp( kTerminalAppBundleID, kAECoreSuite, kAEDoScript, keyDirectObject, inCommandDesc );
		}
	}

	if( (err == noErr) && bringToFront)
	{
		StAEDesc fakeDesc;
        err = CMUtils::SendAEWithObjToRunningApp( kTerminalAppBundleID, kAEMiscStandards, kAEActivate, 0, fakeDesc);
	}

	return err;
}

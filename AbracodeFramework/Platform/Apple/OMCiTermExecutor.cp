/*
 *  OMCTerminalExecutor.cp
 *
 */

#include "OMCTerminalLauncher.h"
#include "OMCEnvironmentExportScript.h" // IsShDefaultLoginShell
#include "StAEDesc.h"
#include "CMUtils.h"
#include "CFObj.h"
#include "MoreAppleEvents.h"
#include "ACFType.h"

static const FourCharCode kITermAppSig = 'ITRM';
static const AEEventClass kITermSuite = 'Itrm';

#define kITermAppBundleID "com.googlecode.iterm2"


static OSErr SendCommandToiTermWindow(AEDesc &windowDesc, AEDesc &commandDesc)
{
    StAEDesc sessionDesc;
    OSErr err = MoreAETellAppObjectToGetAEDesc( kITermAppSig,
                                        &windowDesc,
                                        'Wcsn', //The current session in a window
                                        typeWildCard,
                                        &sessionDesc);

    // No support for custom shell path in iTerm2 AppleScript
    // StAEDesc shellDesc;
    // if(inShellPath == NULL)
    // inShellPath = CFSTR("/bin/bash");
    // err = CMUtils::CreateUniTextDescFromCFString( inShellPath, shellDesc );

    if(err == noErr)
    {
        //err = CMUtils::SendAEWithTwoObjToRunningApp( kITermAppSig, kITermSuite, 'Exec', keyDirectObject, sessionDesc, 'Cmnd', shellDesc );
        err = CMUtils::SendAEWithTwoObjToRunningApp( kITermAppSig, kITermSuite, 'sntx', keyDirectObject, sessionDesc, 'Text', commandDesc );
    }

    return err;
}

static OSErr SendEventToITerm(AEDesc &inCommandDesc, CFStringRef inShellPath, bool openInNewWindow, bool bringToFront)
{
    OSErr err = -1;

    if(openInNewWindow)
    {
        StAEDesc fakeDesc;
        //create window with default profile
        err = CMUtils::SendAEWithObjToRunningApp( kITermAppSig, kITermSuite, 'nwwn', 0, fakeDesc, true);
        if(err != noErr)
            return err; //can't continue if can't create window
    }
    
    //find front window
    StAEDesc theFrontWindow;
    err = MoreAETellBundledAppToGetElementAt(
                                    kITermAppBundleID,
                                    cWindow,
                                    kAEFirst,
                                    typeWildCard,
                                    theFrontWindow);

    if(err == noErr)
    {
        err = SendCommandToiTermWindow(theFrontWindow, inCommandDesc);
    }

    if((err == noErr) && bringToFront)
    {
        StAEDesc fakeDesc;
        err = CMUtils::SendAEWithObjToRunningApp( kITermAppSig, kAEMiscStandards, kAEActivate, 0, fakeDesc);
    }

    return err;
}

void
OMCExecuteInITerm(CFStringRef inCommand, CFStringRef inShellPath, bool openInNewWindow, bool bringToFront)
{
	if(inCommand == NULL)
		return;
	
	OSStatus err = noErr;
	StAEDesc theCommandDesc;

	err = CMUtils::CreateUniTextDescFromCFString(inCommand, theCommandDesc);

	if(err != noErr)
		return;

	err = SendEventToITerm(theCommandDesc, inShellPath, openInNewWindow, bringToFront);

	if(err == noErr)
		return;//sucess situation - we may exit now

	//iTerm not running probably
	TRACE_CSTR("\tExecuteInITerm. Trying to launch the application with LS\n" );
    CFObj<CFArrayRef> appList(LSCopyApplicationURLsForBundleIdentifier(CFSTR(kITermAppBundleID), nullptr));

    if((appList == nullptr) || CFArrayGetCount(appList) == 0)
    {
        LOG_CSTR( "OMC->ExecuteInITerm. Could not find iTerm application. We give up now.\n" );
        return;
    }

    err = fnfErr;
    CFTypeRef oneItem = CFArrayGetValueAtIndex(appList, 0);
    CFURLRef oneURL = ACFType<CFURLRef>::DynamicCast(oneItem);
    if(oneURL != nullptr)
        err = LSOpenCFURLRef(oneURL, nullptr);

	if(err == noErr)
	{//iTerm is launching right now.
	//We cannot send an event to it right away because it is not ready yet
	//We cannot install a launch notify handler because we do not know if our host will be happy about this
	//Installing a deferred task is too much work :-) so we go the easy way:
	//we will wait one second and send event. We will try 10 times every one second to give plenty of time for the app to launch

		for(int i = 1; i <= 10; i++)
		{//we only try 10 times and then give up
			sleep(1); //wait 1 second before trying to send the event

			StAEDesc fakeDesc;
			err = CMUtils::SendAEWithObjToRunningApp( kITermAppSig, kAEMiscStandards, kAEActivate, 0, fakeDesc);
			
			if( (err == connectionInvalid) || (err == procNotFound) )
			{
				TRACE_CSTR("\tExecuteInITerm. App still launching. Waiting...\n" );
				continue;
			}
			else if(err == noErr)
			{
				err = SendEventToITerm(theCommandDesc, inShellPath, false, false);//after terminal launch a new window is open so never open another one
				break;//either err == noErr (success), or some other error so we exit anyway
			}
		}
		
		if(err != noErr)
		{
			LOG_CSTR( "OMC->ExecuteInITerm. Event could not be sent to launched application, err = %d\n", (int)err );
		}
	}
	else
	{
		LOG_CSTR( "OMC->ExecuteInITerm. LSOpenFromRefSpec failed, err = %d\n", (int)err );
	}
	
}

/*
   Looking at  com.googlecode.iterm2.plist:

   more complex structure with multiple profiles named "bookmarks"
   the default one is identified by GUID in root level
   the shell is named "command"
   even if "command" is set, its activation is controlled by "Custom Command" string
   
<key>Default Bookmark Guid</key>
<string>6777374D-5516-4559-907C-F1A309BA889D</string>

<key>New Bookmarks</key>
<array>
	<dict>

		<key>Command</key>
		<string>/bin/tcsh</string>

		<key>Custom Command</key>
		<string>No</string>

		<key>Guid</key>
		<string>6777374D-5516-4559-907C-F1A309BA889D</string>

*/

bool OMCIsShDefaultInITerm()
{
	static bool sIsShDefault = true;
	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		CFObj<CFTypeRef> profileArrayRef = CFPreferencesCopyAppValue(CFSTR("New Bookmarks"), CFSTR("com.googlecode.iterm2"));
		CFArrayRef profileArray = ACFType<CFArrayRef>::DynamicCast(profileArrayRef);
		CFDictionaryRef foundDefaultProfile = nullptr;
		CFIndex profileCount = 0;

		if(profileArray != nullptr)
			profileCount = CFArrayGetCount(profileArray);

		if(profileCount == 1)
		{
			foundDefaultProfile = ACFType<CFDictionaryRef>::DynamicCast(CFArrayGetValueAtIndex(profileArray, 0));
		}
		else if(profileCount > 1)
		{
			CFObj<CFTypeRef> defaultProfileGuidRef = CFPreferencesCopyAppValue(CFSTR("Default Bookmark Guid"), CFSTR("com.googlecode.iterm2"));
			CFStringRef defaultProfileGuid = ACFType<CFStringRef>::DynamicCast(defaultProfileGuidRef);
			for(CFIndex i = 0; i < profileCount; i++)
			{
				CFDictionaryRef oneProfile = ACFType<CFDictionaryRef>::DynamicCast(CFArrayGetValueAtIndex(profileArray, i));
				if(oneProfile != nullptr)
				{
					CFStringRef oneGuid = ACFType<CFStringRef>::DynamicCast(CFDictionaryGetValue(oneProfile, CFSTR("Guid")));
					if((oneGuid != nullptr) && (kCFCompareEqualTo == CFStringCompare(oneGuid, defaultProfileGuid, kCFCompareCaseInsensitive)))
					{
						foundDefaultProfile = oneProfile;
					}
				}
			}
		}
		
		bool customShellFound = false;
		if(foundDefaultProfile != nullptr)
		{
			CFStringRef isCustomStr = ACFType<CFStringRef>::DynamicCast(CFDictionaryGetValue(foundDefaultProfile, CFSTR("Custom Command")));
			if((isCustomStr != nullptr) && (kCFCompareEqualTo == CFStringCompare(isCustomStr, CFSTR("Yes"), kCFCompareCaseInsensitive)))
			{
				CFStringRef shellPath = ACFType<CFStringRef>::DynamicCast(CFDictionaryGetValue(foundDefaultProfile, CFSTR("Command")));
				if((shellPath != nullptr) && (CFStringGetLength(shellPath) > 0))
				{
					//all shells but csh or tcsh are behaving the same for OMC environment export purposes
					CFRange foundRange = ::CFStringFind(shellPath, CFSTR("csh"), 0);
					sIsShDefault = (foundRange.location == kCFNotFound);
					customShellFound = true;
				}
			}
		}
		
		if(!customShellFound)
			sIsShDefault = IsShDefaultLoginShell();
	});

	return sIsShDefault;
}

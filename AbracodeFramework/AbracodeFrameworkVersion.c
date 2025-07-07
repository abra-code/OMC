/*
 *  AbracodeFrameworkVersion.c
 *  
 *  Weak linking support for Abracode.framework
 *	Compile this file in your project and then call GetAbracodeFrameworkVersion to find out if the framework is installed
 *  
 *
 */

#include <CoreFoundation/CoreFoundation.h>

extern UInt32 OMCGetCurrentVersion(void) __attribute__((weak_import));

UInt32 GetAbracodeFrameworkVersion(void)
{
	if(OMCGetCurrentVersion != NULL)
		return OMCGetCurrentVersion();

	CFOptionFlags responseFlags = 0;
	/*SInt32 isSuccessfull = */(void)CFUserNotificationDisplayAlert (
										0.0, //timeout
										kCFUserNotificationStopAlertLevel,
										NULL, //iconURL
										NULL, //soundURL
										NULL, //localizationURL
										CFSTR("Missing Abracode.framework"), //alertHeader
										CFSTR("This app requires Abracode.framework installed by OnMyCommand. Please go to abracode.com to download it."),
										CFSTR("Go"),
										CFSTR("Cancel"),
										NULL, //otherButtonTitle,
										&responseFlags );

	if( (responseFlags & 0x03) == kCFUserNotificationDefaultResponse )//Go online button
	{
		system("/usr/bin/open 'http://www.abracode.com/free/cmworkshop/on_my_command.html'");
	}

	return 0;
}

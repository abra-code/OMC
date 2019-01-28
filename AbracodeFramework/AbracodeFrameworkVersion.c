/*
 *  AbracodeFrameworkVersion.c
 *  
 *  Weak linking support for Abracode.framework
 *	Compile this file in your project and then call GetAbracodeFrameworkVersion to find out if the framework is installed
 *  
 *
 *  Copyright 2011-2014 Abracode. All rights reserved.
 *
 */

#include <CoreFoundation/CoreFoundation.h>

extern UInt32 OMCGetCurrentVersion() __attribute__((weak_import));

UInt32 GetAbracodeFrameworkVersion()
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
										CFSTR("This application requires Abracode.framework installed by OnMyCommand. Please go online to abracode.com to download it."),
										CFSTR("Go Online"),
										CFSTR("Cancel"),
										NULL, //otherButtonTitle,
										&responseFlags );

	if( (responseFlags & 0x03) == kCFUserNotificationDefaultResponse )//Go online button
	{
		system("open 'http://www.abracode.com/free/cmworkshop/on_my_command.html'");
	}

	return 0;
}

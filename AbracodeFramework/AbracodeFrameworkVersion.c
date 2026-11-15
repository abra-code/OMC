/*
 *  AbracodeFrameworkVersion.c
 *  
 *  Weak linking support for Command.framework
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

	// The framework travels inside the applet: the fix is a rebuild, not a download
	CFOptionFlags responseFlags = 0;
	/*SInt32 isSuccessfull = */(void)CFUserNotificationDisplayAlert (
										0.0, //timeout
										kCFUserNotificationStopAlertLevel,
										NULL, //iconURL
										NULL, //soundURL
										NULL, //localizationURL
										CFSTR("Missing Command.framework"), //alertHeader
										CFSTR("This applet requires Command.framework, the Command Engine. Rebuild it with AppletBuilder."),
										CFSTR("OK"),
										NULL, //alternateButtonTitle
										NULL, //otherButtonTitle,
										&responseFlags );

	return 0;
}

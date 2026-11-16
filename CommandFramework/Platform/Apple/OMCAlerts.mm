//
//  OMCAlerts.mm
//  Abracode
//
//  macOS implementation of OMCPlatformShowAlert (Platform/OMCAlerts.h).
//

#include "OMCAlerts.h"

OMCAlertResponse
OMCPlatformShowAlert(OMCAlertLevel inLevel, CFStringRef inHeader, CFStringRef inMessage,
					CFStringRef inDefaultButton, CFStringRef inAlternateButton, CFStringRef inOtherButton)
{
	CFOptionFlags level = kCFUserNotificationStopAlertLevel;
	if(inLevel == kOMCAlertLevelCaution)
		level = kCFUserNotificationCautionAlertLevel;
	else if(inLevel == kOMCAlertLevelNote)
		level = kCFUserNotificationNoteAlertLevel;

	CFOptionFlags responseFlags = 0;
	SInt32 result = ::CFUserNotificationDisplayAlert(0.0, //timeout
													level,
													nullptr, //iconURL
													nullptr, //soundURL
													nullptr, //localizationURL
													inHeader,
													inMessage,
													inDefaultButton,
													inAlternateButton,
													inOtherButton,
													&responseFlags);
	if(result != 0)
		return kOMCAlertNoResponse;

	switch(responseFlags & 0x03)
	{
		case kCFUserNotificationDefaultResponse:	return kOMCAlertDefaultResponse;
		case kCFUserNotificationAlternateResponse:	return kOMCAlertAlternateResponse;
		case kCFUserNotificationOtherResponse:		return kOMCAlertOtherResponse;
		default:									return kOMCAlertNoResponse;
	}
}

void
OMCPlatformShowNotice(CFStringRef inHeader, CFStringRef inMessage, CFStringRef inButton, CFURLRef inIconURL)
{
	(void)::CFUserNotificationDisplayNotice(0.0, //no timeout
											kCFUserNotificationNoteAlertLevel,
											inIconURL,
											nullptr, //soundURL
											nullptr, //localizationURL
											inHeader,
											inMessage,
											inButton);
}

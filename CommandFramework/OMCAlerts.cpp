//
//  OMCAlerts.cpp
//  Abracode
//
//  The engine's own alerts (Platform/OMCAlerts.h). Portable: a test launch answers them from the
//  test's queued answers (OMCTestHost.h); otherwise the platform shows its own.
//

#include "OMCAlerts.h"
#include "OMCTestHost.h"

OMCAlertResponse
OMCShowAlert(OMCAlertLevel inLevel, CFStringRef inHeader, CFStringRef inMessage,
			CFStringRef inDefaultButton, CFStringRef inAlternateButton, CFStringRef inOtherButton)
{
	if(OMCTestHostIsActive())
		return OMCTestHostAnswerAlert(inLevel, inHeader, inMessage, inDefaultButton, inAlternateButton, inOtherButton);
	return OMCPlatformShowAlert(inLevel, inHeader, inMessage, inDefaultButton, inAlternateButton, inOtherButton);
}

void
OMCShowNotice(CFStringRef inHeader, CFStringRef inMessage, CFStringRef inButton, CFURLRef inIconURL)
{
	if(OMCTestHostIsActive())
	{
		OMCTestHostRecordNotice(inHeader, inMessage, inButton);
		return;
	}
	OMCPlatformShowNotice(inHeader, inMessage, inButton, inIconURL);
}

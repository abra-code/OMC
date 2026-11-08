//
//  OMCAlerts.h
//  Abracode
//
//  The engine's own alerts: a command's WARNING confirmation, the version warnings and error alerts
//  (OnMyCommand.cp), and the END_NOTIFICATION notice (OmcTaskManager.cpp). The engine calls
//  OMCShowAlert and OMCShowNotice (OMCAlerts.cpp, portable): in a test launch the test host answers
//  an alert from the answers a test queued (OMCTestHost.h), so it never waits for a person who is
//  not there, and only records a notice; otherwise the platform shows them through
//  OMCPlatformShowAlert and OMCPlatformShowNotice, implemented per platform:
//  Platform/Apple/OMCAlerts.mm (CFUserNotification); a Linux implementation can use ActionUI's
//  alert. An alert blocks until it is answered; a notice does not wait.
//
//  Not these: the alert tool a handler runs (Support/alert), which a test launch replaces with a
//  stand-in of its own, and the panels (OMCFilePanels.h).
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif //__cplusplus

typedef enum
{
	kOMCAlertLevelStop,
	kOMCAlertLevelCaution,
	kOMCAlertLevelNote
} OMCAlertLevel;

typedef enum
{
	kOMCAlertDefaultResponse	= 0, // the default button (OK, Execute, Try Anyway)
	kOMCAlertAlternateResponse	= 1, // the alternate button (Cancel)
	kOMCAlertOtherResponse		= 2, // the third button
	kOMCAlertNoResponse			= 3  // dismissed without a button (it could not be shown, or timed out)
} OMCAlertResponse;

// inHeader is the alert's title, inMessage its text, inDefaultButton the title of its default button
// (required); inAlternateButton and inOtherButton are NULL for an alert without them. The titles are
// shown as given (already localized). Returns the button that answered.
OMCAlertResponse OMCShowAlert(OMCAlertLevel inLevel, CFStringRef inHeader, CFStringRef inMessage,
								CFStringRef inDefaultButton, CFStringRef inAlternateButton, CFStringRef inOtherButton);

// The platform's alert, with the same arguments and result. Called only by OMCShowAlert.
OMCAlertResponse OMCPlatformShowAlert(OMCAlertLevel inLevel, CFStringRef inHeader, CFStringRef inMessage,
										CFStringRef inDefaultButton, CFStringRef inAlternateButton, CFStringRef inOtherButton);

// A notice that does not wait for its button (a command's END_NOTIFICATION): shown and left. In a
// test launch the test host only records it. inIconURL may be NULL.
void OMCShowNotice(CFStringRef inHeader, CFStringRef inMessage, CFStringRef inButton, CFURLRef inIconURL);

// The platform's notice. Called only by OMCShowNotice.
void OMCPlatformShowNotice(CFStringRef inHeader, CFStringRef inMessage, CFStringRef inButton, CFURLRef inIconURL);

#ifdef __cplusplus
}
#endif //__cplusplus

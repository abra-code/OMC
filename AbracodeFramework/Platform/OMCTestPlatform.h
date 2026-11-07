//
//  OMCTestPlatform.h
//  Abracode
//
//  The platform's part of the integration-test surface (OMCTestHost.h): the few operations that
//  differ between platforms. Platform/Apple/OMCTestPlatform.mm; Linux to come with its build.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif //__cplusplus

// What a menu item does with a command when an OMC window is key: runs it as that window's
// subcommand and returns true; false when no OMC window is key. Main thread.
bool OMCTestPlatformDispatchToKeyWindow(CFStringRef inCommandNameOrId, CFTypeRef inContext);

// Asks the application to terminate the normal way, so its termination events run. Main thread.
void OMCTestPlatformRequestQuit(void);

#ifdef __cplusplus
}
#endif //__cplusplus

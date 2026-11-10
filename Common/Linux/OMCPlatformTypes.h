//
//  OMCPlatformTypes.h (Linux)
//
//  What OMC's portable code takes from the platform beyond CoreFoundation, the counterpart of the
//  Apple header of this name, which includes CoreServices (see there). On Linux CoreFoundation
//  already declares the types (OSStatus, OSErr, OSType, the sized integers); the error codes the
//  portable code names are here, with Apple's values, so a status means the same on both platforms.
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>

enum
{
	noErr = 0,
	unimpErr = -4,		// not available on this platform (AppleScript on Linux)
	readErr = -19,
	ioErr = -36,
	fnfErr = -43,
	paramErr = -50,
	memFullErr = -108,
	userCanceledErr = -128,
	errAEWrongDataType = -1703,
	eventNotHandledErr = -9874,
	errAEEventNotPermitted = -1743,
	badPasteboardSyncErr = -25130
};

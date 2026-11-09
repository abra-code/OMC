//**************************************************************************************
// Filename:	OutputWindowHandler.h
// Copyright (c) 2004 Abracode, Inc.  All rights reserved.
//
// Description:	A command's OUTPUT window (EXECUTION_MODE *_with_output_window,
//				OUTPUT_WINDOW_SETTINGS): a built-in ActionUI document
//				(BuiltInDocuments/omc_output.json, a read-only text view) in a window of the
//				window host (Platform/OMCWindowHost.h). Portable: the text and the look go to the
//				document through ActionUI's C interface.
//
//				The handler owns itself: it is deleted when its window closes, by the user or
//				AUTO_CLOSE_TIMEOUT after the command ends, and right away (from the run loop)
//				when the window cannot be made.
//
//**************************************************************************************
// Revision History:
// Wednesday, July 9, 2003 - Original
// 2026-11-09 - The window is a built-in ActionUI document (OMC 5.6)
//**************************************************************************************

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <memory>
#include <string>
#include "AObserver.h"
#include "CFObj.h"

class OMCHostedWindow;

typedef enum
{
	kOMCWindowRegular,
	kOMCWindowFloating,
	kOMCWindowGlobalFloating
} OMCWindowType;

typedef enum
{
    kOMCWindowAbsolutePosition = 0,
    kOMCWindowAlertPositionOnMainScreen,
    kOMCWindowCenterOnMainScreen,
    kOMCWindowCascadeOnMainScreen
} OMCWindowPosition;

struct OutputWindowSettings
{
	CFObj<CFStringRef>	title;
	OMCWindowType		windowType {kOMCWindowFloating};
	OMCWindowPosition	positionMethod {kOMCWindowAlertPositionOnMainScreen};
	double				absoluteLeft {50.0};	// absolute position only
	double				absoluteTop {50.0};
	double				fractionLeft {-1.0};	// 0 to 1 of the screen, for the window's middle; negative: not used
	double				fractionTop {-1.0};
	double				width {400.0};			// content size
	double				height {200.0};
	CFObj<CFStringRef>	textColor;				// "#RRGGBB"; NULL: the system's text color
	CFObj<CFStringRef>	backgroundColor;		// "#RRGGBB"; NULL: the system's text background
	CFObj<CFStringRef>	fontName;
	double				fontSize {12.0};
};

class OutputWindowHandler
{
public:
							OutputWindowHandler( CFDictionaryRef inSettingsDict, CFArrayRef inCommandName, CFStringRef inDynamicName,
												CFBundleRef inExternBundleRef, CFStringRef inLocalizationTableName);
							OutputWindowHandler(CFArrayRef inCommandName, CFStringRef inDynamicName, CFStringRef inTextToDisplay, CFDictionaryRef inSettingsDict,
												CFBundleRef inExternBundleRef, CFStringRef inLocalizationTableName);
	virtual					~OutputWindowHandler();

	AObserverBase *			GetObserver()
							{
								return (AObserver<OutputWindowHandler> *)mTaskObserver;
							}

	void					ReceiveNotification(void *ioData);//local message

	void					SetText(CFStringRef inText, Boolean inLastPart, Boolean inSuccess);
	void					AppendText(const UInt8 *inCStr, long theLen = -1);

	void					AppendOutputData( const UInt8 *inData, size_t inSize, Boolean inSuccess );

	void					GetOutputWindowSettings(CFArrayRef inCommandName,
													CFDictionaryRef inSettingsDict,
													CFBundleRef inExternBundleRef,
													CFStringRef inLocalizationTableName,
													OutputWindowSettings &outSettings);

	// "#RRGGBB" for a color of six hex digits, with or without a leading #, as OUTPUT_WINDOW_SETTINGS
	// gives them; NULL for anything else
	static CFStringRef		CreateColorString(CFStringRef inHexDigits);

protected:
	void					OpenWindow(CFDictionaryRef inSettingsDict, CFArrayRef inCommandName, CFStringRef inDynamicName,
										CFBundleRef inExternBundleRef, CFStringRef inLocalizationTableName);
	void					CommandEnded(Boolean inSuccess);
	// Deletes this handler (and so closes the window) after inDelay seconds, from the main run loop
	void					DeleteAfter(CFTimeInterval inDelay);
	static void				DeleteTimerFired(CFRunLoopTimerRef inTimer, void *inInfo);

	ARefCountedObj< AObserver<OutputWindowHandler> > mTaskObserver;
	std::unique_ptr<OMCHostedWindow> mWindow;
	std::string				mWindowUUID;
	CFObj<CFRunLoopTimerRef> mDeleteTimer;

	CFTimeInterval			mAutoCloseTimeout {-1.0};
	Boolean					mAutoCloseOnSuccessOnly {true};
	bool					mClosedByUser {false};

private:
							OutputWindowHandler(const OutputWindowHandler& inOutputWindowHandler);
	OutputWindowHandler&	operator=(const OutputWindowHandler&);
};

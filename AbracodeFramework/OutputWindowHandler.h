//**************************************************************************************
// Filename:	OutputWindowHandler.h
// Copyright � 2004 Abracode, Inc.  All rights reserved.
//
// Description:	
//
//**************************************************************************************
// Revision History:
// Wednesday, July 9, 2003 - Original
//**************************************************************************************

#pragma once

#include <Carbon/Carbon.h>
#include "AStdNew.h"
#include "AObserver.h"
#include "AStdNew.h"
#include "CFObj.h"
#include "OMCOutputWindowController.h"

typedef enum
{
	kOMCWindowRegular,
	kOMCWindowFloating,
	kOMCWindowGlobalFloating,
	kOMCWindowCustom
} OMCWindowType;

typedef struct OMCColor
{
	CGFloat red;
	CGFloat green;
	CGFloat blue;
	CGFloat alpha;
} OMCColor;

struct OutputWindowSettings
{
	OutputWindowSettings()
		: oneLineDelay(0.1 * kEventDurationSecond), title(NULL), alpha(1.0f),
		windowClass(kUtilityWindowClass), 
		windowAttributes(kWindowCloseBoxAttribute + kWindowCollapseBoxAttribute + kWindowResizableAttribute + kWindowFullZoomAttribute +
						kWindowHideOnFullScreenAttribute + kWindowStandardHandlerAttribute + kWindowLiveResizeAttribute + kWindowNoConstrainAttribute),
		positionMethod(kWindowAlertPositionOnMainScreen), width(400), height(200), fontSize(10.0),
		textBox(CGRectZero), closeBox(CGRectZero), resizeBox(CGRectZero),
		useFadeIn(false), useFadeOut(false)
	{
		topLeftPosition.x = topLeftPosition.y = 50.0;
		specialPosition.x = specialPosition.y = -1.0f;

		backColor.red = 1.0;
		backColor.green = 1.0;
		backColor.blue = 1.0;
		backColor.alpha = 1.0;
		
		textColor.red = 0.0;
		textColor.green = 0.0;
		textColor.blue = 0.0;
		textColor.alpha = 1.0;
	}

	EventTimerInterval oneLineDelay;
	CFObj<CFStringRef> title;
	float		alpha;
	WindowClass windowClass;//UInt32
	OMCWindowType windowType;
	WindowAttributes windowAttributes;//UInt32
	WindowPositionMethod positionMethod; //UInt32
	CGPoint		topLeftPosition;//for absolute position only
	CGPoint		specialPosition;//in range 0.0 - 1.0 for min/max of screen rect, negative: no special position
	short		width;
	short		height;
	OMCColor	backColor;
	OMCColor	textColor;
	CFObj<CGImageRef> backgroundImage;
	CFObj<CFStringRef> fontName;
	CGFloat		fontSize;
	CGRect		textBox;
	CGRect		closeBox;
	CGRect		resizeBox;
	Boolean		useFadeIn;
	Boolean		useFadeOut;
};

class OmcExecutor;

class OutputWindowHandler
{
public:
							OutputWindowHandler( CFDictionaryRef inSettingsDict, CFArrayRef inCommandName, CFStringRef inDynamicName, 
												CFBundleRef inBundleRef, CFBundleRef inExternBundleRef, CFStringRef inLocalizationTableName);
							OutputWindowHandler(CFArrayRef inCommandName, CFStringRef inDynamicName, CFStringRef inTextToDisplay, CFDictionaryRef inSettingsDict,
												CFBundleRef inBundleRef, CFBundleRef inExternBundleRef, CFStringRef inLocalizationTableName);
	virtual					~OutputWindowHandler();

	AObserverBase *			GetObserver()
							{
								return (AObserver<OutputWindowHandler> *)mTaskObserver;
							}

	void					ReceiveNotification(void *ioData);//local message

	void					SetText(CFStringRef inText, Boolean inLastPart, Boolean inSuccess);
	OSStatus				AppendText(const UInt8 *inCStr, long theLen = -1);
	
	Boolean					ShouldCloseWindow() { return mShouldCloseWindow; }
	
	void					AppendOutputData( const UInt8 *inData, size_t inSize, Boolean inSuccess );
	CGImageRef				CreateImage(CFBundleRef inBundle, CFStringRef inBackroundPictureName);

	void					GetOutputWindowSettings(CFArrayRef inCommandName, CFDictionaryRef inSettingsDict,
													CFBundleRef inBundleRef, CFBundleRef inExternBundleRef,
													CFStringRef inLocalizationTableName, OutputWindowSettings &outSettings);

	static Boolean			HexStringToColor(CFStringRef inString, OMCColor &outColor);

	void					ScheduleSelfDestruction(CFTimeInterval inTimeInterval);

protected:
	ARefCountedObj< AObserver<OutputWindowHandler> > mTaskObserver;
	OMCOutputWindowControllerRef mOutputWindowController;

	CFRunLoopTimerRef		mAutoCloseTimer;
	CFTimeInterval			mAutoCloseTimeout;

	Boolean					mShouldCloseWindow;
	Boolean					mAutoCloseOnSuccessOnly;
	Boolean					mUseFadeOut;

private:
							OutputWindowHandler(const OutputWindowHandler& inOutputWindowHandler);
	OutputWindowHandler&	operator=(const OutputWindowHandler&);
};
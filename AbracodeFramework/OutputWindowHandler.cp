//**************************************************************************************
// Filename:	OutputWindowHandler.cp
// Copyright � 2004 Abracode, Inc.  All rights reserved.
//
// Description:	
//
//**************************************************************************************
// Revision History:
// Wednesday, July 9, 2003 - Original
//**************************************************************************************

#include "OutputWindowHandler.h"
#include "OmcExecutor.h"
#include "CFObj.h"
#include "DebugSettings.h"
#include "CMUtils.h"
#include "StSwitchToFront.h"
#include "DefaultExternBundle.h"
#include "ACFDict.h"
#include "OmcTaskNotification.h"

//inNewFinalizer must be allocated with operator new and we take ownership of it and delete it in our destructor
OutputWindowHandler::OutputWindowHandler( CFDictionaryRef inSettingsDict,
										CFArrayRef inCommandName, CFStringRef inDynamicName,
										CFBundleRef inBundleRef, CFBundleRef inExternBundleRef,
										CFStringRef inLocalizationTableName)
	: mTaskObserver( new AObserver<OutputWindowHandler>(this) ),
	mOutputWindowController(NULL), mAutoCloseTimer(NULL),
	mShouldCloseWindow(false), mAutoCloseOnSuccessOnly(true), mUseFadeOut(false),
	mAutoCloseTimeout(-1.0)
{
	TRACE_CSTR("Entering OutputWindowHandler constructor (with command)\n");

	OutputWindowSettings windowSettings;
	GetOutputWindowSettings(inCommandName, inSettingsDict, inBundleRef, inExternBundleRef, inLocalizationTableName, windowSettings);

	if(windowSettings.title == NULL)
	{
		windowSettings.title.Adopt(inDynamicName, kCFObjRetain);
		if(windowSettings.title == NULL)
		{
			windowSettings.title.Adopt( CFSTR(""), kCFObjRetain);
		}
	}

	StSwitchToFront switcher(false);//switch us to front, don't restore
	mOutputWindowController = CreateOutputWindowController(windowSettings, this);
}

OutputWindowHandler::OutputWindowHandler(CFArrayRef inCommandName, CFStringRef inDynamicName, CFStringRef inTextToDisplay, CFDictionaryRef inSettingsDict,
										CFBundleRef inBundleRef, CFBundleRef inExternBundleRef,
										CFStringRef inLocalizationTableName)
	:  mTaskObserver( new AObserver<OutputWindowHandler>(this) ),
	mOutputWindowController(NULL), mAutoCloseTimer(NULL), 
	mShouldCloseWindow(false), mAutoCloseOnSuccessOnly(true), mUseFadeOut(false), 
	mAutoCloseTimeout(-1.0)
{

	TRACE_CSTR("Entering OutputWindowHandler constructor (with text to display)\n");
	
	OutputWindowSettings windowSettings;
	GetOutputWindowSettings(inCommandName, inSettingsDict, inBundleRef, inExternBundleRef, inLocalizationTableName, windowSettings);

	if(windowSettings.title == NULL)
	{
		windowSettings.title.Adopt(inDynamicName, kCFObjRetain);
		if(windowSettings.title == NULL)
		{
			windowSettings.title.Adopt( CFSTR(""), kCFObjRetain);
		}
	}

	StSwitchToFront switcher(false);//switch us to front, don't restore

	mOutputWindowController = CreateOutputWindowController(windowSettings, this);
	OMCOutputWindowSetText(mOutputWindowController, inTextToDisplay);
}


OutputWindowHandler::~OutputWindowHandler()
{
	TRACE_CSTR("Entering OutputWindowHandler destructor\n");

	if(mTaskObserver != NULL)
		mTaskObserver->SetOwner(NULL);//observer may outlive us so it is very important to tell that we died

	if(mAutoCloseTimer != NULL)
	{
		CFRunLoopTimerInvalidate(mAutoCloseTimer);
		CFRelease(mAutoCloseTimer);
		mAutoCloseTimer = NULL;
	}

	if( mOutputWindowController != NULL)
	{
		ReleaseOutputWindowController(mOutputWindowController);
		mOutputWindowController = NULL;
	}

// TaskManager Quits app for commands without output window
// but when window is there, the app needs to run until the window dies

#ifdef BUILD_DEPUTY
	TRACE_CSTR("Quitting the deputy application loop\n");
	extern void TerminateApplication(CFTimeInterval inDelay);
	TerminateApplication(mUseFadeOut ? 1.0 : 0.0);
	//::QuitApplicationEventLoop();
#endif

	TRACE_CSTR("Exiting OutputWindowHandler destructor\n");
}


void
OutputWindowHandler::SetText(CFStringRef inText, Boolean inLastPart, Boolean inSuccess)
{
	if(mOutputWindowController != NULL)
	   OMCOutputWindowSetText(mOutputWindowController, inText);

	if(inLastPart)
	{
		Boolean allowAutoclose = ( !mAutoCloseOnSuccessOnly || inSuccess );
		if( (mAutoCloseTimeout >= 0.0) && allowAutoclose )
		{
            OMCOutputWindowScheduleClosing(mOutputWindowController, mAutoCloseTimeout);
		}
	}
}


OSStatus
OutputWindowHandler::AppendText(const UInt8 *inCStr, long theLen /*=-1*/)
{
	if(inCStr == NULL)
		return noErr;
	
	if(theLen < 0)
		theLen = strlen( (const char *)inCStr );

	if(theLen == 0)
		return noErr;

	CFObj<CFStringRef> theString( ::CFStringCreateWithBytes(kCFAllocatorDefault, inCStr, theLen, kCFStringEncodingUTF8, true) );

	if(mOutputWindowController != NULL)
	{
		OMCOutputWindowAppendText(mOutputWindowController, (CFStringRef)theString);
		return noErr;
	}
	return paramErr;
}


void
OutputWindowHandler::ReceiveNotification(void *ioData)
{
	if(ioData == NULL)
		return;

	OmcTaskData *taskData = (OmcTaskData *)ioData;

	switch(taskData->messageID)
	{
		case kOmcTaskFinished:
		{
			bool isSuccess = true; //TODO
			if( taskData->dataType == kOmcDataTypeBoolean )
			{
				bool wasSynchronous = taskData->data.test;
			}
			AppendOutputData( NULL, 0, taskData->error == noErr );//this finalizes our data processing and optionally starts autoclose timer
		}
		break;

		case kOmcTaskProgress:
		{
			if( taskData->dataType == kOmcDataTypePointer )
				AppendOutputData( (const UInt8 *)taskData->data.ptr, taskData->dataSize, true );
			else if( taskData->dataType == kOmcDataTypeCFString )
				SetText( (CFStringRef)taskData->data.cfObj, false, true );
		}
		break;

		default:
		break;
	}
}


void
OutputWindowHandler::AppendOutputData( const UInt8 *inData, size_t inSize, Boolean inSuccess )
{
	if( inSize == 0 )
	{
		Boolean allowAutoclose = ( !mAutoCloseOnSuccessOnly || inSuccess );
		if( (mAutoCloseTimeout >= 0.0) && allowAutoclose && (mAutoCloseTimer == NULL) )
		{
            OMCOutputWindowScheduleClosing(mOutputWindowController, mAutoCloseTimeout);
		}
	}
	else
	{
		AppendText( inData, inSize);
	}
}

void OutputWindowHandlerDeleterCallBack(CFRunLoopTimerRef timer, void* info)
{
#pragma unused (timer)
	OutputWindowHandler *theHandler = (OutputWindowHandler *)info;
	delete theHandler;//the destructor will remove the timer
}

void
OutputWindowHandler::GetOutputWindowSettings(CFArrayRef inCommandName, CFDictionaryRef inSettingsDict,
											CFBundleRef inBundleRef, CFBundleRef inExternBundleRef,
											CFStringRef inLocalizationTableName, OutputWindowSettings &outSettings)
{
	CFStringRef theStr;

//set defaults
/* defaults set in constructor
	outSettings.oneLineDelay = 0.1 * kEventDurationSecond;
	outSettings.title = NULL;
	outSettings.alpha = 1.0;
*/
#ifdef BUILD_DEPUTY
//regular floating window is never shown in background app - the default is global floating
	outSettings.windowType = kOMCWindowGlobalFloating;
	outSettings.windowClass = kUtilityWindowClass;
	outSettings.windowAttributes = kWindowCloseBoxAttribute + kWindowCollapseBoxAttribute + 
								kWindowResizableAttribute + kWindowFullZoomAttribute +
								kWindowHideOnFullScreenAttribute +
								kWindowStandardHandlerAttribute + kWindowLiveResizeAttribute + kWindowNoConstrainAttribute;				
#else //BUILD_DEPUTY
	//we need to check if the process is background only - in this case we cannot use floating
	//because it will never show
	
	ProcessSerialNumber psn = { 0, kCurrentProcess };
	ProcessInfoRec info;
	info.processInfoLength = sizeof(ProcessInfoRec);
	info.processName = NULL;
	info.processAppRef = NULL;
	::GetProcessInformation( &psn, &info );

	if( (info.processMode & modeOnlyBackground) != 0 )
	{
		DEBUG_CSTR("Current process is background-only\n");
		DEBUG_CSTR("processMode = %d\n", (int)info.processMode);
		outSettings.windowType = kOMCWindowGlobalFloating;
		outSettings.windowClass = kUtilityWindowClass;
		outSettings.windowAttributes = kWindowCloseBoxAttribute + kWindowCollapseBoxAttribute + 
									kWindowResizableAttribute + kWindowFullZoomAttribute +
									kWindowHideOnFullScreenAttribute +
									kWindowStandardHandlerAttribute + kWindowLiveResizeAttribute + kWindowNoConstrainAttribute;				
	}
	else
	{
		DEBUG_CSTR("Current process is NOT background-only\n");
		DEBUG_CSTR("processMode = %d\n", (int)info.processMode);
		outSettings.windowType = kOMCWindowFloating;
		outSettings.windowClass = kFloatingWindowClass;
		outSettings.windowAttributes = kWindowCloseBoxAttribute + kWindowCollapseBoxAttribute + 
								kWindowResizableAttribute + kWindowFullZoomAttribute +
								kWindowHideOnSuspendAttribute + kWindowHideOnFullScreenAttribute +
								kWindowStandardHandlerAttribute + kWindowLiveResizeAttribute + kWindowNoConstrainAttribute;
	}

#endif //BUILD_DEPUTY

	if(inSettingsDict == NULL)
		return;

	ACFDict settings(inSettingsDict);

//deprecated
	double secondsInterval = 0.1;
	if( settings.GetValue(CFSTR("LINE_OUTPUT_INTERVAL"), secondsInterval) )
		outSettings.oneLineDelay = secondsInterval * kEventDurationSecond;

	CFStringRef windowTitle = NULL;
	settings.GetValue(CFSTR("WINDOW_TITLE"), windowTitle);

	if( (windowTitle != NULL) && (inLocalizationTableName != NULL) )
	{//client wants localization
		CFBundleRef localizationBundle = inExternBundleRef;//.omc module with localization?
		if(localizationBundle == NULL)
			localizationBundle = CFBundleGetMainBundle();//this will not work if command delegated to deputy (should be rare for droplet)

		outSettings.title.Adopt( ::CFCopyLocalizedStringFromTableInBundle( windowTitle, inLocalizationTableName, localizationBundle, "") );
	}
	else
	{
		outSettings.title.Adopt(windowTitle, kCFObjRetain);
	}
	
	if( settings.GetValue(CFSTR("WINDOW_ALPHA"), outSettings.alpha) )
	{
		if(outSettings.alpha < 0.0)
			outSettings.alpha = 0.0;
		if(outSettings.alpha > 1.0)
			outSettings.alpha = 1.0;
	}
	

	settings.GetValue(CFSTR("WINDOW_OPEN_FADE_IN"), outSettings.useFadeIn);
	settings.GetValue(CFSTR("WINDOW_CLOSE_FADE_OUT"), outSettings.useFadeOut);
	mUseFadeOut =  outSettings.useFadeOut;

	double secondsTimeout = -1.0;
	if( settings.GetValue(CFSTR("AUTO_CLOSE_TIMEOUT"), secondsTimeout) )
	{
		mAutoCloseTimeout = secondsTimeout;
	}

	settings.GetValue(CFSTR("AUTO_CLOSE_ON_SUCCESS_ONLY"), mAutoCloseOnSuccessOnly);
	
	Boolean isCustom = false;
	
	if( settings.GetValue(CFSTR("WINDOW_TYPE"), theStr) )
	{
		if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("regular"), 0 ) )
		{
			outSettings.windowType = kOMCWindowRegular;
			outSettings.windowClass = kDocumentWindowClass;
			outSettings.windowAttributes = kWindowCloseBoxAttribute + kWindowCollapseBoxAttribute + 
										kWindowResizableAttribute + kWindowFullZoomAttribute +
										kWindowStandardHandlerAttribute + kWindowLiveResizeAttribute + kWindowNoConstrainAttribute;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("floating"), 0 ) )
		{
#ifdef BUILD_DEPUTY
//regular floating window is never shown for backround deputy app. replace with global floating
			outSettings.windowType = kOMCWindowGlobalFloating;
			outSettings.windowClass = kUtilityWindowClass;
			outSettings.windowAttributes = kWindowCloseBoxAttribute + kWindowCollapseBoxAttribute + 
										kWindowResizableAttribute + kWindowFullZoomAttribute +
										kWindowHideOnFullScreenAttribute +
										kWindowStandardHandlerAttribute + kWindowLiveResizeAttribute + kWindowNoConstrainAttribute;				

#else
			if( (info.processMode & modeOnlyBackground) != 0 )
			{
				outSettings.windowType = kOMCWindowGlobalFloating;
				outSettings.windowClass = kUtilityWindowClass;
				outSettings.windowAttributes = kWindowCloseBoxAttribute + kWindowCollapseBoxAttribute + 
											kWindowResizableAttribute + kWindowFullZoomAttribute +
											kWindowHideOnFullScreenAttribute +
											kWindowStandardHandlerAttribute + kWindowLiveResizeAttribute + kWindowNoConstrainAttribute;				
			}
			else
			{
				outSettings.windowType = kOMCWindowFloating;
				outSettings.windowClass = kFloatingWindowClass;
				outSettings.windowAttributes = kWindowCloseBoxAttribute + kWindowCollapseBoxAttribute + 
											kWindowResizableAttribute + kWindowFullZoomAttribute +
											kWindowHideOnSuspendAttribute + kWindowHideOnFullScreenAttribute +
											kWindowStandardHandlerAttribute + kWindowLiveResizeAttribute + kWindowNoConstrainAttribute;
			}
#endif
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("global_floating"), 0 ) )
		{
			outSettings.windowType = kOMCWindowGlobalFloating;
			outSettings.windowClass = kUtilityWindowClass;
			outSettings.windowAttributes = kWindowCloseBoxAttribute + kWindowCollapseBoxAttribute + 
										kWindowResizableAttribute + kWindowFullZoomAttribute +
										kWindowHideOnFullScreenAttribute +
										kWindowStandardHandlerAttribute + kWindowLiveResizeAttribute + kWindowNoConstrainAttribute;				
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("custom"), 0 ) )
		{
			outSettings.windowType = kOMCWindowCustom;
			outSettings.windowClass = kOverlayWindowClass;
			outSettings.windowAttributes	= kWindowNoShadowAttribute + kWindowStandardHandlerAttribute + kWindowNoConstrainAttribute;
			isCustom = true;
		}
	}


	if( settings.GetValue(CFSTR("WINDOW_POSITION"), theStr) )
	{
		if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("absolute"), 0 ) )
		{
			outSettings.positionMethod = 0;//absolute position
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("alert"), 0 ) )
		{
			outSettings.positionMethod = kWindowAlertPositionOnMainScreen;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("center"), 0 ) )
		{
			outSettings.positionMethod = kWindowCenterOnMainScreen;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("cascade"), 0 ) )
		{
			outSettings.positionMethod = kWindowCascadeOnMainScreen;
		}
	}
	
	settings.GetValue(CFSTR("ABSOLUTE_POSITION_TOP"), outSettings.topLeftPosition.y);
	settings.GetValue(CFSTR("ABSOLUTE_POSITION_LEFT"), outSettings.topLeftPosition.x);

	settings.GetValue(CFSTR("FRACT_POSITION_TOP"), outSettings.specialPosition.y);
	settings.GetValue(CFSTR("FRACT_POSITION_LEFT"), outSettings.specialPosition.x);
	
	CGImageRef customImage = NULL;
	if( settings.GetValue(CFSTR("CUSTOM_WINDOW_PNG_IMAGE"), theStr) )
	{
		//try reading with from external bundle
		if(inExternBundleRef != NULL)
			customImage = CreateImage(inExternBundleRef, theStr);
		
		if(customImage == NULL)//not found in external - try in main
			customImage = CreateImage(inBundleRef, theStr);
	}
	
	if(customImage != NULL)
	{
		outSettings.backgroundImage.Adopt(customImage, kCFObjRetain);
		outSettings.width = ::CGImageGetWidth(customImage);
		outSettings.height = ::CGImageGetHeight(customImage);
		CFRelease(customImage);
	}
	else
	{
		settings.GetValue(CFSTR("WINDOW_WIDTH"), outSettings.width);
		if(outSettings.width <= 0)
			outSettings.width = 400;

		settings.GetValue(CFSTR("WINDOW_HEIGHT"), outSettings.height);
		if(outSettings.height <= 0)
			outSettings.height = 200;

		if( settings.GetValue(CFSTR("BACKGROUND_COLOR"), theStr) )
			HexStringToColor(theStr, outSettings.backColor);
	}
	
	if( settings.GetValue(CFSTR("TEXT_COLOR"), theStr) )
		HexStringToColor(theStr, outSettings.textColor);

	CFStringRef fontName = NULL;	
	settings.GetValue(CFSTR("TEXT_FONT"), fontName);
	if(fontName == NULL)
		fontName = CFSTR("Monaco");

	outSettings.fontName.Adopt(fontName, kCFObjRetain);
	
	settings.GetValue(CFSTR("TEXT_SIZE"), outSettings.fontSize );

	if( outSettings.fontSize < 0 )
		outSettings.fontSize = 10;
	if( outSettings.fontSize > 10000 )
		outSettings.fontSize = 10000;

//custom window settings:
	if(isCustom)
	{
//textbox position and dimensions
		settings.GetValue(CFSTR("CUSTOM_TEXTBOX_POSITION_TOP"), outSettings.textBox.origin.y);
		settings.GetValue(CFSTR("CUSTOM_TEXTBOX_POSITION_LEFT"), outSettings.textBox.origin.x);

		settings.GetValue(CFSTR("CUSTOM_TEXTBOX_WIDTH"), outSettings.textBox.size.width);
		settings.GetValue(CFSTR("CUSTOM_TEXTBOX_HEIGHT"), outSettings.textBox.size.height);

		if( (int)outSettings.textBox.size.width == 0 )
			outSettings.textBox.size.width = outSettings.width - outSettings.textBox.origin.x;
		
		if( (int)outSettings.textBox.size.height == 0 )
			outSettings.textBox.size.height = outSettings.height - outSettings.textBox.origin.y;

		//now switch the origin to be from the bottom
		outSettings.textBox.origin.y = outSettings.height - outSettings.textBox.size.height - outSettings.textBox.origin.y;

//custom close box
		settings.GetValue(CFSTR("CUSTOM_CLOSEBOX_POSITION_TOP"), outSettings.closeBox.origin.y);//y-origin is top-relative
		settings.GetValue(CFSTR("CUSTOM_CLOSEBOX_POSITION_LEFT"), outSettings.closeBox.origin.x);
		
		settings.GetValue(CFSTR("CUSTOM_CLOSEBOX_WIDTH"), outSettings.closeBox.size.width);
		settings.GetValue(CFSTR("CUSTOM_CLOSEBOX_HEIGHT"), outSettings.closeBox.size.height);

//custom resize box
		settings.GetValue(CFSTR("CUSTOM_RESIZEBOX_POSITION_BOTTOM"), outSettings.resizeBox.origin.y);//y-origin is bottom-relative
		settings.GetValue(CFSTR("CUSTOM_RESIZEBOX_POSITION_RIGHT"), outSettings.resizeBox.origin.x);//x-origin is right-relative

		settings.GetValue(CFSTR("CUSTOM_RESIZEBOX_WIDTH"), outSettings.resizeBox.size.width);
		settings.GetValue(CFSTR("CUSTOM_RESIZEBOX_HEIGHT"), outSettings.resizeBox.size.height);
	}
}

#define ONE_HEX_CHAR_TO_NUMBER(_hc) \
(((_hc) >= '0') && ((_hc) <= '9')) ? ((_hc)-'0') : \
(((_hc) >= 'A') && ((_hc) <= 'F')) ? ((_hc)-'A'+10) : \
(((_hc) >= 'a') && ((_hc) <= 'f')) ? ((_hc)-'a'+10) : -1

//static
Boolean
OutputWindowHandler::HexStringToColor(CFStringRef inString, OMCColor &outColor)
{
	if(inString == NULL)
		return false;
	
	CFIndex charCount = CFStringGetLength(inString);
	if(charCount != 6)
		return false;
	
	UniChar hexChars[6] = {0, 0, 0, 0, 0, 0};
	CFStringGetCharacters(inString, CFRangeMake(0, 6), hexChars);
	
	//red
	short hiPart = ONE_HEX_CHAR_TO_NUMBER(hexChars[0]);
	if(hiPart < 0)
		return false;
	
	short loPart = ONE_HEX_CHAR_TO_NUMBER(hexChars[1]);
	if(loPart < 0)
		return false;
	
	unsigned short red = hiPart * 16 + loPart;
	outColor.red = (CGFloat)red/256.0;
	
	
	//green
	hiPart = ONE_HEX_CHAR_TO_NUMBER(hexChars[2]);
	if(hiPart < 0)
		return false;
	
	loPart = ONE_HEX_CHAR_TO_NUMBER(hexChars[3]);
	if(loPart < 0)
		return false;
	
	unsigned short green = hiPart * 16 + loPart;
	outColor.green = (CGFloat)green/256.0;
	
	//blue
	hiPart = ONE_HEX_CHAR_TO_NUMBER(hexChars[4]);
	if(hiPart < 0)
		return false;
	
	loPart = ONE_HEX_CHAR_TO_NUMBER(hexChars[5]);
	if(loPart < 0)
		return false;
	
	unsigned short blue = hiPart * 16 + loPart;
	outColor.blue = (CGFloat)blue/256.0;
	
	outColor.alpha = 1.0;

	return true;
}

CGImageRef
OutputWindowHandler::CreateImage(CFBundleRef inBundle, CFStringRef inBackroundPictureName)
{
	CFIndex strLen = ::CFStringGetLength(inBackroundPictureName);
	if(strLen == 0)
		return NULL;

	UniChar firstChar = ::CFStringGetCharacterAtIndex(inBackroundPictureName, 0);
	CFURLRef url = NULL;
	
	if(firstChar == (UniChar)'/')
	{//absolute path
		url = ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, inBackroundPictureName, kCFURLPOSIXPathStyle, false);
	}
	else
	{//image in resources
		if(inBundle == NULL)
			inBundle = ::CFBundleGetMainBundle();
		url = ::CFBundleCopyResourceURL( inBundle, inBackroundPictureName, NULL, NULL );
	}

	if( url == NULL )
		return NULL;

	CFObj<CGImageSourceRef> imgSource( CGImageSourceCreateWithURL(url, NULL) );
	CGImageRef outImage = NULL;
	if(imgSource != NULL)
		outImage = CGImageSourceCreateImageAtIndex( imgSource, 0, NULL );

	::CFRelease( url );
	
	return outImage;
}

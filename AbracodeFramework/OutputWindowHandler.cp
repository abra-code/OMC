//**************************************************************************************
// Filename:	OutputWindowHandler.cp
// Copyright (c) 2004 Abracode, Inc.  All rights reserved.
//
// Description:	A command's OUTPUT window (OutputWindowHandler.h). Portable: the window comes
//				from the window host, and the text and the look go to the document through
//				ActionUI's C interface.
//
//**************************************************************************************
// Revision History:
// Wednesday, July 9, 2003 - Original
// 2026-11-09 - The window is a built-in ActionUI document (OMC 5.6)
//**************************************************************************************

#include "OutputWindowHandler.h"
#include "OMCWindowHost.h"
#include "OMCMainThreadSignal.h"
#include "CFObj.h"
#include "ACFDict.h"
#include "ACFJSON.h"
#include "ACFString.h"
#include "ActionUIC.h"
#include "DebugSettings.h"
#include "OmcTaskNotification.h"
#include "OMCHostInfo.h"
#include <algorithm>

// The document's text view (BuiltInDocuments/omc_output.json)
static const int64_t kOutputTextID = 1;

// Sets a property of the document's text view to a CF property list value, as JSON
static void SetTextViewProperty(const char *inWindowUUID, const char *inPropertyName, CFPropertyListRef inValue)
{
	CFObj<CFDataRef> json( ACFJSONCreateData(inValue, nullptr) );
	if(json == nullptr)
		return;
	std::string jsonText((const char *)CFDataGetBytePtr(json), (size_t)CFDataGetLength(json));
	actionUISetElementPropertyJSON(inWindowUUID, kOutputTextID, inPropertyName, jsonText.c_str());
}

OutputWindowHandler::OutputWindowHandler( CFDictionaryRef inSettingsDict,
										CFArrayRef inCommandName,
										CFStringRef inDynamicName,
										CFBundleRef inExternBundleRef,
										CFStringRef inLocalizationTableName)
	: mTaskObserver( new AObserver<OutputWindowHandler>(this) )
{
	TRACE_CSTR("Entering OutputWindowHandler constructor (with command)\n");
	OpenWindow(inSettingsDict, inCommandName, inDynamicName, inExternBundleRef, inLocalizationTableName);
}

OutputWindowHandler::OutputWindowHandler(CFArrayRef inCommandName,
										CFStringRef inDynamicName,
										CFStringRef inTextToDisplay,
										CFDictionaryRef inSettingsDict,
										CFBundleRef inExternBundleRef,
										CFStringRef inLocalizationTableName)
	:  mTaskObserver( new AObserver<OutputWindowHandler>(this) )
{
	TRACE_CSTR("Entering OutputWindowHandler constructor (with text to display)\n");
	OpenWindow(inSettingsDict, inCommandName, inDynamicName, inExternBundleRef, inLocalizationTableName);
	SetText(inTextToDisplay, false, true);
}

OutputWindowHandler::~OutputWindowHandler()
{
	TRACE_CSTR("Entering OutputWindowHandler destructor\n");

	if(mTaskObserver != NULL)
		mTaskObserver->SetOwner(NULL);//observer may outlive us so it is very important to tell that we died

	mDeleteCall.reset(); // a pending delete never runs on a deleted handler
	mWindow.reset(); // closes the window

	TRACE_CSTR("Exiting OutputWindowHandler destructor\n");
}

void
OutputWindowHandler::OpenWindow(CFDictionaryRef inSettingsDict, CFArrayRef inCommandName, CFStringRef inDynamicName,
								CFBundleRef inExternBundleRef, CFStringRef inLocalizationTableName)
{
	OutputWindowSettings settings;
	GetOutputWindowSettings(inCommandName, inSettingsDict, inExternBundleRef, inLocalizationTableName, settings);

	if(settings.title == nullptr)
		settings.title.Adopt(inDynamicName, kCFObjRetain);
	if(settings.title == nullptr)
		settings.title.Adopt(CFSTR(""), kCFObjRetain);

	OMCHostedWindowSpec spec;
	spec.documentName = CFSTR("omc_output");
	spec.title = settings.title;
	spec.contentWidth = settings.width;
	spec.contentHeight = settings.height;

	switch(settings.windowType)
	{
		case kOMCWindowRegular:			spec.level = OMCHostedWindowLevel::normal;		break;
		case kOMCWindowFloating:		spec.level = OMCHostedWindowLevel::floating;	break;
		case kOMCWindowGlobalFloating:	spec.level = OMCHostedWindowLevel::utility;		break;
	}

	switch(settings.positionMethod)
	{
		case kOMCWindowAbsolutePosition:			spec.placement = OMCHostedWindowPlacement::absolute;		break;
		case kOMCWindowAlertPositionOnMainScreen:	spec.placement = OMCHostedWindowPlacement::alert;			break;
		case kOMCWindowCenterOnMainScreen:			spec.placement = OMCHostedWindowPlacement::screenCenter;	break;
		case kOMCWindowCascadeOnMainScreen:			spec.placement = OMCHostedWindowPlacement::cascade;		break;
	}
	spec.absoluteLeft = settings.absoluteLeft;
	spec.absoluteTop = settings.absoluteTop;
	spec.fractionLeft = settings.fractionLeft;
	spec.fractionTop = settings.fractionTop;

	// The user closed it: this handler goes away, from the run loop, since the window is still
	// telling its delegate
	mWindow = OMCCreateHostedWindow(spec, [this]()
	{
		mClosedByUser = true;
		DeleteAfter(0);
	});
	if(mWindow == nullptr)
	{ // the output goes nowhere, as when the nib could not be loaded; no window close will delete
	  // this handler, so it goes away from the run loop (the caller still uses it until then)
		DeleteAfter(0);
		return;
	}

	mWindowUUID = ACFStringToUTF8(mWindow->GetWindowUUID());
	const char *uuid = mWindowUUID.c_str();

	// The font: TEXT_FONT, else Monaco; the monospaced system font where the named font is missing
	CFObj<CFNumberRef> fontSize( CFNumberCreate(kCFAllocatorDefault, kCFNumberDoubleType, &settings.fontSize) );
	const void *fontKeys[] = { CFSTR("name"), CFSTR("size"), CFSTR("design") };
	const void *fontValues[] = { (CFStringRef)settings.fontName, (CFNumberRef)fontSize, CFSTR("monospaced") };
	CFObj<CFDictionaryRef> font( CFDictionaryCreate(kCFAllocatorDefault, fontKeys, fontValues, 3,
													&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks) );
	SetTextViewProperty(uuid, "font", font);

	if(settings.textColor != nullptr)
		SetTextViewProperty(uuid, "foregroundStyle", settings.textColor);

	if(settings.backgroundColor != nullptr)
	{ // the text view draws no background of its own, so the element's background shows
		SetTextViewProperty(uuid, "scrollContentBackground", CFSTR("hidden"));
		SetTextViewProperty(uuid, "background", settings.backgroundColor);
	}

	StSwitchToFront switcher(false);//switch us to front, don't restore
	mWindow->Show();
}

void
OutputWindowHandler::SetText(CFStringRef inText, Boolean inLastPart, Boolean inSuccess)
{
	if( (mWindow != nullptr) && (inText != nullptr) )
	{
		std::string text = ACFStringToUTF8(inText);
		actionUISetElementValueString(mWindowUUID.c_str(), kOutputTextID, 0, text.c_str(), nullptr);
	}

	if(inLastPart)
		CommandEnded(inSuccess);
}

// The executor delivers whole UTF-8 characters (OmcExecutor.cp); bytes that are not UTF-8 show
// as replacement characters
void
OutputWindowHandler::AppendText(const UInt8 *inCStr, long theLen /*=-1*/)
{
	if( (inCStr == NULL) || (mWindow == nullptr) )
		return;

	if(theLen < 0)
		theLen = (long)strlen( (const char *)inCStr );

	if(theLen == 0)
		return;

	// a NUL byte would end the C string and drop the rest of the piece: leave the NULs out (they
	// showed nothing in 5.5 either)
	std::string piece((const char *)inCStr, (size_t)theLen);
	piece.erase(std::remove(piece.begin(), piece.end(), '\0'), piece.end());
	if(piece.empty())
		return;
	actionUIAppendElementText(mWindowUUID.c_str(), kOutputTextID, piece.c_str());
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
		CommandEnded(inSuccess);
	else
		AppendText( inData, (long)inSize);
}

// AUTO_CLOSE_TIMEOUT starts when the command ends (successfully, unless AUTO_CLOSE_ON_SUCCESS_ONLY
// is false)
void
OutputWindowHandler::CommandEnded(Boolean inSuccess)
{
	Boolean allowAutoclose = ( !mAutoCloseOnSuccessOnly || inSuccess );
	if( (mAutoCloseTimeout >= 0.0) && allowAutoclose && !mClosedByUser && (mWindow != nullptr) )
		DeleteAfter(mAutoCloseTimeout);
}

void
OutputWindowHandler::DeleteAfter(CFTimeInterval inDelay)
{
	// replaces a pending one (a user close replaces a pending AUTO_CLOSE_TIMEOUT)
	mDeleteCall = OMCMainThreadSignal::ScheduleAfter(inDelay, DeleteDue, this);
}

//static
void
OutputWindowHandler::DeleteDue(void *inContext)
{
	// the scheduled call may be destroyed from inside its own callback (OMCMainThreadSignal.h)
	OutputWindowHandler *handler = (OutputWindowHandler *)inContext;
	delete handler;
}

// Command.plist SCHEMA SOURCE OF TRUTH - OUTPUT_WINDOW_SETTINGS (WINDOW_TITLE,
// AUTO_CLOSE_TIMEOUT, AUTO_CLOSE_ON_SUCCESS_ONLY, WINDOW_TYPE enum [regular/floating/
// global_floating; custom is read as floating], WINDOW_POSITION enum [absolute/alert/center/
// cascade], ABSOLUTE/FRACT positions, WINDOW_WIDTH/HEIGHT, BACKGROUND/TEXT_COLOR, TEXT_FONT/SIZE).
// Ignored since 5.6: WINDOW_ALPHA, WINDOW_OPEN_FADE_IN/CLOSE_FADE_OUT, CUSTOM_WINDOW_PNG_IMAGE,
// CUSTOM_TEXTBOX_* / CUSTOM_CLOSEBOX_* / CUSTOM_RESIZEBOX_*.
// Adding/removing/renaming/deprecating/retyping any key (or enum value) here REQUIRES
// updating the matching verifier schema and rebuilding the skill, else the Command.plist
// verifier drifts (false positives/negatives):
//   verifier schema: Distribution/AppletBuilder.app/Contents/Library/command_verifier/schemas/OUTPUT_WINDOW_SETTINGS.json
//   rebuild skill:   python3 Skill/build_skill.py
void
OutputWindowHandler::GetOutputWindowSettings(CFArrayRef inCommandName,
											CFDictionaryRef inSettingsDict,
											CFBundleRef inExternBundleRef,
											CFStringRef inLocalizationTableName,
											OutputWindowSettings &outSettings)
{
	CFStringRef theStr;
	//we need to check if the process is background only - in this case we cannot use floating
	//because it will never show
    bool regularGUIApp = RunningInRegularGUIApp();
    outSettings.windowType = regularGUIApp ? kOMCWindowFloating : kOMCWindowGlobalFloating;
	outSettings.fontName.Adopt(CFSTR("Monaco"), kCFObjRetain);

	if(inSettingsDict == nullptr)
		return;

	ACFDict settings(inSettingsDict);

	CFStringRef windowTitle = nullptr;
	settings.GetValue(CFSTR("WINDOW_TITLE"), windowTitle);

	if( (windowTitle != nullptr) && (inLocalizationTableName != nullptr) )
	{//client wants localization
		CFBundleRef localizationBundle = inExternBundleRef;//.omc module with localization?
		if(localizationBundle == nullptr)
			localizationBundle = CFBundleGetMainBundle();

		outSettings.title.Adopt( ::CFCopyLocalizedStringFromTableInBundle( windowTitle, inLocalizationTableName, localizationBundle, "") );
	}
	else
	{
		outSettings.title.Adopt(windowTitle, kCFObjRetain);
	}

	double secondsTimeout = -1.0;
	if( settings.GetValue(CFSTR("AUTO_CLOSE_TIMEOUT"), secondsTimeout) )
	{
		mAutoCloseTimeout = secondsTimeout;
	}

	settings.GetValue(CFSTR("AUTO_CLOSE_ON_SUCCESS_ONLY"), mAutoCloseOnSuccessOnly);

	if( settings.GetValue(CFSTR("WINDOW_TYPE"), theStr) )
	{
		if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("regular"), 0 ) )
		{
			outSettings.windowType = kOMCWindowRegular;
		}
		else if( (kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("floating"), 0 )) ||
				 (kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("custom"), 0 )) ) // custom PNG windows are gone
		{
            outSettings.windowType = regularGUIApp ? kOMCWindowFloating : kOMCWindowGlobalFloating;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("global_floating"), 0 ) )
		{
			outSettings.windowType = kOMCWindowGlobalFloating;
		}
	}

	if( settings.GetValue(CFSTR("WINDOW_POSITION"), theStr) )
	{
		if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("absolute"), 0 ) )
		{
			outSettings.positionMethod = kOMCWindowAbsolutePosition;//absolute position
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("alert"), 0 ) )
		{
			outSettings.positionMethod = kOMCWindowAlertPositionOnMainScreen;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("center"), 0 ) )
		{
			outSettings.positionMethod = kOMCWindowCenterOnMainScreen;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("cascade"), 0 ) )
		{
			outSettings.positionMethod = kOMCWindowCascadeOnMainScreen;
		}
	}

	settings.GetValue(CFSTR("ABSOLUTE_POSITION_TOP"), outSettings.absoluteTop);
	settings.GetValue(CFSTR("ABSOLUTE_POSITION_LEFT"), outSettings.absoluteLeft);

	settings.GetValue(CFSTR("FRACT_POSITION_TOP"), outSettings.fractionTop);
	settings.GetValue(CFSTR("FRACT_POSITION_LEFT"), outSettings.fractionLeft);

	settings.GetValue(CFSTR("WINDOW_WIDTH"), outSettings.width);
	if(outSettings.width <= 0)
		outSettings.width = 400;

	settings.GetValue(CFSTR("WINDOW_HEIGHT"), outSettings.height);
	if(outSettings.height <= 0)
		outSettings.height = 200;

	if( settings.GetValue(CFSTR("BACKGROUND_COLOR"), theStr) )
		outSettings.backgroundColor.Adopt( CreateColorString(theStr) );

	if( settings.GetValue(CFSTR("TEXT_COLOR"), theStr) )
		outSettings.textColor.Adopt( CreateColorString(theStr) );

	CFStringRef fontName = nullptr;
	if( settings.GetValue(CFSTR("TEXT_FONT"), fontName) && (fontName != nullptr) && (CFStringGetLength(fontName) > 0) )
		outSettings.fontName.Adopt(fontName, kCFObjRetain);

	settings.GetValue(CFSTR("TEXT_SIZE"), outSettings.fontSize );

	if( outSettings.fontSize <= 0 )
		outSettings.fontSize = 12;
	if( outSettings.fontSize > 10000 )
		outSettings.fontSize = 10000;
}

//static
CFStringRef
OutputWindowHandler::CreateColorString(CFStringRef inHexDigits)
{
	if(inHexDigits == nullptr)
		return nullptr;
	CFIndex length = CFStringGetLength(inHexDigits);
	CFIndex start = 0;
	if( (length == 7) && (CFStringGetCharacterAtIndex(inHexDigits, 0) == '#') )
		start = 1; // the docs' examples and the verifier allow a leading #
	if( (length - start) != 6 )
		return nullptr;

	UniChar hexChars[6] = {0, 0, 0, 0, 0, 0};
	CFStringGetCharacters(inHexDigits, CFRangeMake(start, 6), hexChars);
	for(UniChar oneChar : hexChars)
	{
		bool isHexDigit = ((oneChar >= '0') && (oneChar <= '9')) ||
						((oneChar >= 'A') && (oneChar <= 'F')) ||
						((oneChar >= 'a') && (oneChar <= 'f'));
		if(!isHexDigit)
			return nullptr;
	}
	return CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("#%C%C%C%C%C%C"),
									hexChars[0], hexChars[1], hexChars[2], hexChars[3], hexChars[4], hexChars[5]);
}

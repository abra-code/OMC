//
//  OMCProgressWindow.cpp
//  Abracode
//
//  A command's PROGRESS window (OMCProgressWindow.h). Portable: the window comes from the window
//  host, and the values go to the document through ActionUI's C interface.
//

#include "OMCProgressWindow.h"
#include "OMCWindowHost.h"
#include "OMCEngineBundle.h"
#include "ACFString.h"
#include "ActionUIC.h"
#include "ACFJSON.h"
#include <cmath>
#include <map>

// The document's element ids (BuiltInDocuments/omc_progress.json)
static const int64_t kStatusTextID = 2;
static const int64_t kProgressBarID = 3;
static const int64_t kStopButtonID = 4;


const char *const OMCProgressWindow::kStopActionID = "omc.builtin.progress.stop";

// Open progress windows by window UUID, for the Stop action. Never destroyed, so a window that
// goes away while the process exits does not find it gone.
static std::map<std::string, OMCProgressWindow *> &OpenProgressWindows()
{
	static std::map<std::string, OMCProgressWindow *> *sWindows = new std::map<std::string, OMCProgressWindow *>();
	return *sWindows;
}

// The documents carry no text of their own: the Stop button's accessibility label and help tag
// come from the framework's Private.strings
static void SetStopButtonLabel(const char *inWindowUUID)
{
	CFObj<CFStringRef> stop;
	CFBundleRef frameworkBundle = OMCGetEngineBundle();
	if(frameworkBundle != nullptr)
		stop.Adopt( CFCopyLocalizedStringFromTableInBundle(CFSTR("Stop"), CFSTR("Private"), frameworkBundle, "") );
	if(stop == nullptr)
		stop.Adopt(CFSTR("Stop"), kCFObjRetain);

	CFObj<CFDataRef> json( ACFJSONCreateData(stop, nullptr) );
	if(json == nullptr)
		return;
	std::string jsonText((const char *)CFDataGetBytePtr(json), (size_t)CFDataGetLength(json));
	actionUISetElementPropertyJSON(inWindowUUID, kStopButtonID, "accessibilityLabel", jsonText.c_str());
	actionUISetElementPropertyJSON(inWindowUUID, kStopButtonID, "help", jsonText.c_str());
}

std::unique_ptr<OMCProgressWindow>
OMCProgressWindow::Create(CFStringRef inTitle)
{
	static bool sStopHandlerRegistered = false;
	if(!sStopHandlerRegistered)
	{
		actionUIRegisterActionHandler(kStopActionID, StopActionHandler);
		sStopHandlerRegistered = true;
	}

	OMCHostedWindowSpec spec;
	spec.documentName = CFSTR("omc_progress");
	spec.title = inTitle;
	spec.closable = false; // Stop is the way to close it, as in the nib window it replaces
	CFObj<CFStringRef> autosaveName( CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("omc_progress_window %@"), inTitle) );
	spec.frameAutosaveName = autosaveName;

	std::unique_ptr<OMCHostedWindow> window = OMCCreateHostedWindow(spec, nullptr);
	if(window == nullptr)
		return nullptr;

	std::unique_ptr<OMCProgressWindow> progressWindow(new OMCProgressWindow());
	progressWindow->mWindowUUID = ACFStringToUTF8(window->GetWindowUUID());
	progressWindow->mWindow = std::move(window);
	OpenProgressWindows()[progressWindow->mWindowUUID] = progressWindow.get();
	SetStopButtonLabel(progressWindow->mWindowUUID.c_str());
	return progressWindow;
}

OMCProgressWindow::~OMCProgressWindow()
{
	OpenProgressWindows().erase(mWindowUUID);
}

void
OMCProgressWindow::Show()
{
	if(!mCanceled)
		mWindow->Show();
}

void
OMCProgressWindow::SetProgress(double inProgress, CFStringRef inText)
{
	if(mCanceled)
		return;

	const char *uuid = mWindowUUID.c_str();
	bool wantsDeterminate = (inProgress >= 0.0);
	int newValue = (int)std::round(inProgress);

	if( (mLastValue == INT_MIN) || (wantsDeterminate != mIsDeterminate) )
	{
		if(!wantsDeterminate)
			actionUISetElementStateJSON(uuid, kProgressBarID, "progress", "-1"); // a negative progress is indeterminate
		mIsDeterminate = wantsDeterminate;
	}

	if( wantsDeterminate && (newValue > mLastValue) )
	{
		if(newValue > 100)
			newValue = 100;
		std::string valueJSON = std::to_string(newValue);
		actionUISetElementStateJSON(uuid, kProgressBarID, "progress", valueJSON.c_str());
		mLastValue = newValue;
	}
	else if(!wantsDeterminate)
	{
		mLastValue = newValue;
	}

	if(inText != nullptr)
	{
		if( (mLastText == nullptr) || (CFStringCompare(mLastText, inText, 0) != kCFCompareEqualTo) )
		{
			std::string text = ACFStringToUTF8(inText);
			actionUISetElementValueString(uuid, kStatusTextID, 0, text.c_str(), nullptr);
		}
		mLastText.Adopt(inText, kCFObjRetain);
	}
}

void
OMCProgressWindow::Stop()
{
	mCanceled = true;
	mWindow->Close();
}

void
OMCProgressWindow::StopActionHandler(const char *inActionID, const char *inWindowUUID, int64_t inViewID, int64_t inViewPartID, const char *inContextJSON)
{
	if(inWindowUUID == nullptr)
		return;
	auto found = OpenProgressWindows().find(inWindowUUID);
	if(found != OpenProgressWindows().end())
		found->second->Stop();
}

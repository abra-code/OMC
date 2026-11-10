//
//  OMCActionUIWindow.cpp
//  Abracode
//
//  See OMCActionUIWindow.h. Replaces OMCActionUIWindowController.mm and the parts of its base class,
//  OMCWindowController.mm, that ActionUI windows used: the window's lifecycle, its subcommands, the
//  default action handler and the registry of open windows.
//

#include "OMCActionUIWindow.h"
#include "OMCActionUIDialog.h"
#include "OMCActionUIControls.h"
#include "OMCActionUIDocumentLookup.h"
#include "OMCActionUIModelLifetime.h"
#include "OMCActionUIRemoteHost.h"
#include "OMCDialogControlAccessor.h"
#include "OMCAppShell.h"
#include "OMCLog.h"
#include "OMCMainThreadSignal.h"
#include "OnMyCommand.h"
#include "CommandRuntimeData.h"
#include "ACFDict.h"
#include "ACFString.h"
#include "ACFJSON.h"
#include "ActionUIC.h"
#include <algorithm>
#include <cassert>
#include <string>
#include <vector>

#if CURRENT_OMC_VERSION >= 50000

namespace
{

// The open windows. A window is registered when it is made and leaves when it has closed and its
// end subcommand has run; the list keeps a non-blocking window alive while it is open.
std::vector<std::shared_ptr<OMCActionUIWindow>> &OpenWindows()
{
	static std::vector<std::shared_ptr<OMCActionUIWindow>> *sOpenWindows = new std::vector<std::shared_ptr<OMCActionUIWindow>>();
	return *sOpenWindows;
}

bool IsEqual(CFStringRef inA, CFStringRef inB)
{
	return (inA != nullptr) && (inB != nullptr) && (::CFStringCompare(inA, inB, 0) == kCFCompareEqualTo);
}

// The dialog's accessor: omc_dialog_control's messages and the engine's reads of the values go to
// the window while it lives, and to nothing after (it holds the window weakly)
class WindowAccessor final : public OMCDialogControlAccessor
{
public:
	explicit WindowAccessor(std::weak_ptr<OMCActionUIWindow> inWindow) : mWindow(std::move(inWindow)) { }

	void SetControlValues(CFDictionaryRef inControlDict) noexcept override
	{
		if(std::shared_ptr<OMCActionUIWindow> window = mWindow.lock())
			OMCDispatchDialogControlMessage(inControlDict, *window);
	}

	void CopyAllControlValues(CFMutableDictionaryRef ioControlValues, CFMutableDictionaryRef ioCustomProperties,
							SelectionIterator *inSelIterator) noexcept override
	{
		(void)ioCustomProperties;
		(void)inSelIterator;
		if(std::shared_ptr<OMCActionUIWindow> window = mWindow.lock())
			window->CopyAllControlValues(ioControlValues);
	}

	CFTypeRef CopyControlValue(CFStringRef inControlID, CFStringRef inControlPart, SelectionIterator *inSelIterator,
							CFDictionaryRef *outCustomProperties) noexcept override
	{
		(void)inSelIterator;
		if(outCustomProperties != nullptr)
			*outCustomProperties = nullptr;
		if(std::shared_ptr<OMCActionUIWindow> window = mWindow.lock())
			return window->CopyControlValue(inControlID, inControlPart);
		return nullptr;
	}

private:
	std::weak_ptr<OMCActionUIWindow> mWindow;
};

// OMC_ACTIONUI_TRIGGER_CONTEXT keeps 5.5's form (Phase 5 decision 2): ActionUI hands the context
// over as JSON; a string is the string itself, true and false are 1 and 0, null is no context, and
// a number, an array or a dictionary is its JSON text (compact, as NSJSONSerialization wrote it, and
// a number as NSNumber printed it, with no ".0" on a whole number)
CFStringRef CreateTriggerContext(const char *inContextJSON)
{
	if(inContextJSON == nullptr)
		return nullptr;
	std::string text(inContextJSON);
	if(text == "null")
		return nullptr;
	if(text == "true")
		return CFSTR("1");
	if(text == "false")
		return CFSTR("0");
	if( !text.empty() && (text[0] == '"') )
	{
		CFObj<CFDataRef> data( ::CFDataCreate(kCFAllocatorDefault, (const UInt8 *)text.data(), (CFIndex)text.size()) );
		CFObj<CFPropertyListRef> parsed( ACFJSONCreatePropertyList(data, kCFPropertyListImmutable, nullptr) );
		if( (parsed != nullptr) && (::CFGetTypeID(parsed) == ::CFStringGetTypeID()) )
			return (CFStringRef)parsed.Detach();
	}
	return ::CFStringCreateWithCString(kCFAllocatorDefault, text.c_str(), kCFStringEncodingUTF8);
}

// ActionUI's default action handler, for every action id no built-in window registered: finds the
// window by its UUID and runs the action there, with the trigger variables set for its length
void HandleAction(const char *inActionID, const char *inWindowUUID, int64_t inViewID, int64_t inViewPartID, const char *inContextJSON)
{
	if( (inActionID == nullptr) || (inWindowUUID == nullptr) )
		return;
	CFObj<CFStringRef> windowUUID( ::CFStringCreateWithCString(kCFAllocatorDefault, inWindowUUID, kCFStringEncodingUTF8) );
	std::shared_ptr<OMCActionUIWindow> window = OMCActionUIWindow::Find(windowUUID);
	if(window == nullptr)
	{
		OMCLogMessage("Window not found for provided UUID: %s when handling actionID: %s from viewID: %lld", inWindowUUID, inActionID, (long long)inViewID);
		return;
	}
	CFObj<CFStringRef> context( CreateTriggerContext(inContextJSON) );
	CFObj<CFStringRef> actionID( ::CFStringCreateWithCString(kCFAllocatorDefault, inActionID, kCFStringEncodingUTF8) );
	window->SetControlContext((CFIndex)inViewID, (CFIndex)inViewPartID, context);
	window->DispatchCommand(actionID, nullptr);
	window->ClearControlContext();
}

void ReleaseWindow(void *inContext)
{
	delete static_cast<std::shared_ptr<OMCActionUIWindow> *>(inContext);
}

} // namespace

#pragma mark - Registry

std::shared_ptr<OMCActionUIWindow>
OMCActionUIWindow::Create(OnMyCommand *inPlugin, CommandRuntimeData *inCommandRuntimeData)
{
	if( (inPlugin == nullptr) || (inCommandRuntimeData == nullptr) )
		return nullptr;
	std::shared_ptr<OMCActionUIWindow> window = std::make_shared<OMCActionUIWindow>(inPlugin, inCommandRuntimeData);
	OpenWindows().push_back(window);
	window->Init();
	return window;
}

std::shared_ptr<OMCActionUIWindow>
OMCActionUIWindow::Find(CFStringRef inWindowUUID)
{
	if(inWindowUUID == nullptr)
		return nullptr;
	for(const std::shared_ptr<OMCActionUIWindow> &window : OpenWindows())
	{
		if( IsEqual(window->GetWindowUUID(), inWindowUUID) )
			return window;
	}
	return nullptr;
}

std::shared_ptr<OMCActionUIWindow>
OMCActionUIWindow::FindKeyWindow()
{
	for(const std::shared_ptr<OMCActionUIWindow> &window : OpenWindows())
	{
		if( (window->mHostedWindow != nullptr) && !window->mClosed && window->mHostedWindow->IsKey() )
			return window;
	}
	return nullptr;
}

// Leaves the list on the main queue, after the close that led here has finished: the window often
// closes inside its own button's action, and its host must not take the hosting view out of it there
void
OMCActionUIWindow::Unregister()
{
	std::vector<std::shared_ptr<OMCActionUIWindow>> &openWindows = OpenWindows();
	auto found = std::find_if(openWindows.begin(), openWindows.end(),
							[this](const std::shared_ptr<OMCActionUIWindow> &inWindow) { return inWindow.get() == this; });
	if(found == openWindows.end())
		return;
	auto *heldWindow = new std::shared_ptr<OMCActionUIWindow>(std::move(*found));
	openWindows.erase(found);
	if( !OMCMainThreadSignal::RunAfter(0, ReleaseWindow, heldWindow) )
		ReleaseWindow(heldWindow); // the caller still holds the window for its length
}

#pragma mark - Lifecycle

OMCActionUIWindow::OMCActionUIWindow(OnMyCommand *inPlugin, CommandRuntimeData *inCommandRuntimeData)
{
	mPlugin.Adopt(inPlugin, kARefCountRetain);
	mCommandRuntimeData.Adopt(inCommandRuntimeData, kARefCountRetain);
	mExternBundle.Adopt(inPlugin->GetCurrentCommandExternBundle(), kCFObjRetain);
	mCommandName.Adopt(inPlugin->GetCurrentCommand().name, kCFObjRetain);
}

OMCActionUIWindow::~OMCActionUIWindow()
{
	CFObj<CFStringRef> windowUUID( GetWindowUUID(), kCFObjRetain );
	if(mDialog != nullptr)
		mDialog->SetControlAccessor(nullptr);
	mHostedWindow.reset();
	// The window's ActionUI model outlives the window until the last command started for it has
	// ended: the end command, which starts as the window closes, may read the closed window through
	// the ActionUI remote bridge (OMCActionUIModelLifetime.h)
	if(windowUUID != nullptr)
		OMCActionUIModelWindowClosed(windowUUID);
}

void
OMCActionUIWindow::Init()
{
	mDialog.Adopt( new OMCActionUIDialog() );
	mDialog->SetControlAccessor( std::make_unique<WindowAccessor>(weak_from_this()) );
	mCommandRuntimeData->SetAssociatedDialogUUID(mDialog->GetDialogUUID());

	// The window now has a UUID, which is the only thing a remote client needs to address it, so
	// this is the earliest point at which serving is meaningful, and it is before the init
	// subcommand runs, so that subcommand's own handler can already reach back in. Idempotent.
	OMCEnsureActionUIRemoteBridgeStarted();

	CommandDescription &currCommand = mPlugin->GetCurrentCommand();
	ACFDict params( currCommand.actionUIWindow );
	CFObj<CFStringRef> jsonName;
	params.CopyValue( CFSTR("JSON_NAME"), jsonName );
	if(jsonName == nullptr)
		return; // no document, no window

	params.CopyValue( CFSTR("INIT_SUBCOMMAND_ID"), mInitSubcommandID );
	params.CopyValue( CFSTR("END_OK_SUBCOMMAND_ID"), mEndOKSubcommandID );
	params.CopyValue( CFSTR("END_CANCEL_SUBCOMMAND_ID"), mEndCancelSubcommandID );
	params.CopyValue( CFSTR("WINDOW_DID_ACTIVATE_SUBCOMMAND_ID"), mDidActivateSubcommandID );
	params.CopyValue( CFSTR("WINDOW_DID_DEACTIVATE_SUBCOMMAND_ID"), mDidDeactivateSubcommandID );

	bool isBlocking = true; // a blocking window when not given
	params.GetValue( CFSTR("IS_BLOCKING"), isBlocking );
	mIsModal = isBlocking;

	CFObj<CFStringRef> windowTitle;
	params.CopyValue( CFSTR("WINDOW_TITLE"), windowTitle );
	CFStringRef windowType = nullptr;
	params.GetValue( CFSTR("WINDOW_TYPE"), windowType );

	CFObj<CFURLRef> documentURL( OMCCopyActionUIDocumentURL(jsonName, mExternBundle, mPlugin->GetBundleRef()) );
	if(documentURL == nullptr)
	{
		std::string name = ACFStringToUTF8(jsonName);
		OMCLogMessage("Cannot find ActionUI JSON file: %s", name.c_str());
		return;
	}

	// The window host makes the window: the content spans the titlebar (required for a SwiftUI
	// NavigationSplitView root, see OMCWindowHost.mm), the size limits come from the document, a
	// document of fixed size makes a window the user cannot resize, and the frame saved under
	// "OMC.<JSON_NAME>" comes back, else the window opens at its fitting size, centered.
	CFObj<CFStringRef> autosaveName( ::CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("OMC.%@"), (CFStringRef)jsonName) );
	OMCHostedWindowSpec spec;
	spec.documentURL = documentURL;
	spec.windowUUID = mDialog->GetDialogUUID();
	spec.frameAutosaveName = autosaveName;
	spec.placement = OMCHostedWindowPlacement::restoredElseCentered;
	spec.contentSpansTitlebar = true;
	spec.sizeLimitsFromDocument = true;
	// The model outlives the window until the last command started for it has ended (the destructor)
	spec.removesModelWhenDestroyed = false;
	// A regular non-blocking window gets the minimize button, and with it a working Window >
	// Minimize (Cmd-M). A blocking dialog runs in a modal session, and minimizing it would leave the
	// app stuck behind an invisible modal window. Panels do not minimize (the host gives none the button).
	spec.miniaturizable = !mIsModal;
	if( IsEqual(windowType, CFSTR("floating")) )
		spec.level = OMCHostedWindowLevel::floating;
	else if( IsEqual(windowType, CFSTR("global_floating")) )
		spec.level = OMCHostedWindowLevel::utility;
	// "regular" is the default

	// Every close of the window runs the end subcommand; the host holds these callbacks and this
	// window holds the host, so they hold the window weakly
	std::weak_ptr<OMCActionUIWindow> weakWindow = weak_from_this();
	mHostedWindow = OMCCreateHostedWindow(spec, [weakWindow]() {
		if(std::shared_ptr<OMCActionUIWindow> window = weakWindow.lock())
			window->WindowDidClose();
	});
	if(mHostedWindow == nullptr)
	{
		std::string name = ACFStringToUTF8(jsonName);
		OMCLogMessage("Unable to create a view from ActionUI JSON file: %s", name.c_str());
		return;
	}
	mHostedWindow->SetKeyChangeCallbacks(
		[weakWindow]() {
			if(std::shared_ptr<OMCActionUIWindow> window = weakWindow.lock())
				window->RunActivationSubcommand(window->mDidActivateSubcommandID);
		},
		[weakWindow]() {
			if(std::shared_ptr<OMCActionUIWindow> window = weakWindow.lock())
				window->RunActivationSubcommand(window->mDidDeactivateSubcommandID);
		});

	SetUpTitle(windowTitle);

	// One default handler for every command window: it finds the window by its UUID
	static bool sHandlerSet = false;
	if(!sHandlerSet)
	{
		actionUISetDefaultActionHandler(HandleAction);
		sHandlerSet = true;
	}
}

// WINDOW_TITLE, else the associated file (the title bar's proxy and an Open Recent entry), else the
// command's name with its dynamic parts
void
OMCActionUIWindow::SetUpTitle(CFStringRef inWindowTitle)
{
	if(inWindowTitle != nullptr)
	{
		mHostedWindow->SetTitle(inWindowTitle);
		return;
	}

	OneObjProperties *associatedObj = mCommandRuntimeData->GetAssociatedObject();
	if(associatedObj != nullptr)
	{
		CFURLRef fileURL = associatedObj->url.Get();
		if(fileURL != nullptr)
		{
			mHostedWindow->SetRepresentedFile(fileURL);
			OMCNoteRecentDocument(fileURL);
		}
		return;
	}

	CommandDescription &currCommand = mPlugin->GetCurrentCommand();
	CFBundleRef localizationBundle = nullptr;
	if(currCommand.localizationTableName != nullptr) // the command wants to be localized
	{
		localizationBundle = mPlugin->GetCurrentCommandExternBundle();
		if(localizationBundle == nullptr)
			localizationBundle = ::CFBundleGetMainBundle();
	}
	CFObj<CFStringRef> dynamicCommandName( mPlugin->CreateDynamicCommandName(currCommand, *mCommandRuntimeData,
																			currCommand.localizationTableName, localizationBundle) );
	mHostedWindow->SetTitle(dynamicCommandName);
}

CFStringRef
OMCActionUIWindow::GetWindowUUID() const
{
	return (mDialog != nullptr) ? mDialog->GetDialogUUID() : nullptr;
}

void *
OMCActionUIWindow::GetNativeWindow() const
{
	return (mHostedWindow != nullptr) ? mHostedWindow->GetNativeWindow() : nullptr;
}

void
OMCActionUIWindow::Run()
{
	if( !InitializeDialog() )
		return;
	if(mHostedWindow == nullptr)
		return;
	if(mIsModal)
		mHostedWindow->RunModal();
	else
		mHostedWindow->Show();
}

bool
OMCActionUIWindow::IsOkeyed() const
{
	if(mCurrentCommandID == nullptr)
		return false;
	if(mEndOKSubcommandID != nullptr)
		return IsEqual(mCurrentCommandID, mEndOKSubcommandID);
	return IsEqual(mCurrentCommandID, CFSTR("omc.dialog.ok"));
}

bool
OMCActionUIWindow::IsCanceled() const
{
	if(mCurrentCommandID == nullptr)
		return false;
	if(mEndCancelSubcommandID != nullptr)
		return IsEqual(mCurrentCommandID, mEndCancelSubcommandID);
	return IsEqual(mCurrentCommandID, CFSTR("omc.dialog.cancel"));
}

void
OMCActionUIWindow::DispatchCommand(CFStringRef inCommandID, CFTypeRef inContext)
{
	mCurrentCommandID.Adopt(inCommandID, kCFObjRetain);
	if( IsOkeyed() || IsCanceled() )
		CloseFromCommand();
	else
		ProcessCommand(inContext);
}

// The message port first, then the init subcommand (INIT_SUBCOMMAND_ID, else omc.dialog.initialize),
// before the window shows. False when the command reported an error.
bool
OMCActionUIWindow::InitializeDialog()
{
	CFObj<CFStringRef> originalCommandID( mCurrentCommandID.Get(), kCFObjRetain );
	mCurrentCommandID.Adopt( (mInitSubcommandID != nullptr) ? mInitSubcommandID.Get() : CFSTR("omc.dialog.initialize"), kCFObjRetain );
	mDialog->StartListening();
	ProcessCommand(nullptr);
	mCurrentCommandID.Swap(originalCommandID);
	return (mPlugin->GetError() == noErr);
}

// The end subcommand: END_OK_SUBCOMMAND_ID or END_CANCEL_SUBCOMMAND_ID, else
// omc.dialog.terminate.ok or omc.dialog.terminate.cancel
void
OMCActionUIWindow::Terminate()
{
	bool wasOkeyed = IsOkeyed();
	CFObj<CFStringRef> originalCommandID( mCurrentCommandID.Get(), kCFObjRetain );
	if( wasOkeyed && (mEndOKSubcommandID != nullptr) )
		mCurrentCommandID.Adopt(mEndOKSubcommandID.Get(), kCFObjRetain);
	else if( !wasOkeyed && (mEndCancelSubcommandID != nullptr) )
		mCurrentCommandID.Adopt(mEndCancelSubcommandID.Get(), kCFObjRetain);
	else
		mCurrentCommandID.Adopt(wasOkeyed ? CFSTR("omc.dialog.terminate.ok") : CFSTR("omc.dialog.terminate.cancel"), kCFObjRetain);
	ProcessCommand(nullptr);
	mCurrentCommandID.Swap(originalCommandID);
}

// The OK or Cancel id, or TERMINATE: the window closes (which ends a modal run) and the end
// subcommand runs. Without a window there is nothing to close, as before.
void
OMCActionUIWindow::CloseFromCommand()
{
	if( (mHostedWindow == nullptr) || mClosed )
		return;
	mHostedWindow->Close(); // the host's own close: its close callback does not run
	WindowDidClose();
}

// Every close, the user's or this window's: ends a modal run, runs the end subcommand, and leaves
// the list of open windows
void
OMCActionUIWindow::WindowDidClose()
{
	if(mClosed)
		return;
	mClosed = true;
	if(mIsModal && (mHostedWindow != nullptr))
		mHostedWindow->EndModal();
	Terminate();
	Unregister();
}

void
OMCActionUIWindow::RunActivationSubcommand(CFStringRef inSubcommandID)
{
	if(inSubcommandID == nullptr)
		return;
	CFObj<CFStringRef> originalCommandID( mCurrentCommandID.Get(), kCFObjRetain );
	mCurrentCommandID.Adopt(inSubcommandID, kCFObjRetain);
	ProcessCommand(nullptr);
	mCurrentCommandID.Swap(originalCommandID);
}

// Runs the subcommand with the current command id: one of the dialog's predefined ids
// (omc.dialog.*) looked up among the subcommands, any other among the commands
void
OMCActionUIWindow::ProcessCommand(CFTypeRef inContext)
{
	if( (mPlugin == nullptr) || (mCurrentCommandID == nullptr) )
		return;
	SInt32 commandIndex = OMCDialog::IsPredefinedDialogCommandID(mCurrentCommandID)
							? mPlugin->FindSubcommandIndex(mCommandName, mCurrentCommandID)
							: mPlugin->FindCommandIndex(mCommandName, mCurrentCommandID);
	if(commandIndex < 0)
		return;

	// An ActionUI window has no selection iterator: none while the subcommand runs
	SelectionIterator *oldIterator = mDialog->GetSelectionIterator();
	mDialog->SetSelectionIterator(nullptr);
	(void)mPlugin->ExecuteSubcommand(commandIndex, mCommandRuntimeData, inContext);
	mDialog->SetSelectionIterator(oldIterator);
}

void
OMCActionUIWindow::SetControlContext(CFIndex inViewID, CFIndex inViewPartID, CFStringRef inContext)
{
	mCommandRuntimeData->controlContextViewID = inViewID;
	mCommandRuntimeData->controlContextViewPartID = inViewPartID;
	if(inContext != nullptr)
		mCommandRuntimeData->controlContextJSON.Adopt(inContext, kCFObjRetain);
	else
		mCommandRuntimeData->controlContextJSON = nullptr;
}

void
OMCActionUIWindow::ClearControlContext()
{
	mCommandRuntimeData->controlContextViewID = -1;
	mCommandRuntimeData->controlContextViewPartID = -1;
	mCommandRuntimeData->controlContextJSON = nullptr;
}

#pragma mark - Values

void
OMCActionUIWindow::CopyAllControlValues(CFMutableDictionaryRef ioControlValues)
{
	OMCActionUICopyAllControlValues(GetWindowUUID(), ioControlValues);
}

CFTypeRef
OMCActionUIWindow::CopyControlValue(CFStringRef inControlID, CFStringRef inControlPart)
{
	return OMCActionUICopyControlValue(GetWindowUUID(), inControlID, inControlPart);
}

#pragma mark - OMCDialogControlTarget: the window's elements (OMCActionUIControls.h)

void OMCActionUIWindow::RemoveAllListItems(CFStringRef inControlID) { OMCActionUIClearControlRows(GetWindowUUID(), inControlID); }
void OMCActionUIWindow::SetListItems(CFStringRef inControlID, CFArrayRef inItems) { OMCActionUISetControlListItems(GetWindowUUID(), inControlID, inItems); }
void OMCActionUIWindow::AppendListItems(CFStringRef inControlID, CFArrayRef inItems) { OMCActionUIAppendControlListItems(GetWindowUUID(), inControlID, inItems); }
void OMCActionUIWindow::EmptyTable(CFStringRef inControlID) { OMCActionUIClearControlRows(GetWindowUUID(), inControlID); }
// The same as EmptyTable for ActionUI (no separate "remove without reload")
void OMCActionUIWindow::RemoveTableRows(CFStringRef inControlID) { OMCActionUIClearControlRows(GetWindowUUID(), inControlID); }
void OMCActionUIWindow::SetTableRows(CFStringRef inControlID, CFArrayRef inRows) { OMCActionUISetControlTableRows(GetWindowUUID(), inControlID, inRows); }
void OMCActionUIWindow::AddTableRows(CFStringRef inControlID, CFArrayRef inRows) { OMCActionUIAppendControlTableRows(GetWindowUUID(), inControlID, inRows); }
void OMCActionUIWindow::SetTableColumns(CFStringRef inControlID, CFArrayRef inColumns) { OMCActionUISetControlTableColumns(GetWindowUUID(), inControlID, inColumns); }
void OMCActionUIWindow::SetTableColumnWidths(CFStringRef inControlID, CFArrayRef inWidths) { OMCActionUISetControlTableColumnWidths(GetWindowUUID(), inControlID, inWidths); }
void OMCActionUIWindow::SelectRow(CFStringRef inControlID, CFIndex inRowIndex) { OMCActionUISelectControlRow(GetWindowUUID(), inControlID, inRowIndex); }
void OMCActionUIWindow::SelectRowWithContent(CFStringRef inControlID, CFStringRef inText, CFIndex inColumnNumber)
	{ OMCActionUISelectControlRowWithContent(GetWindowUUID(), inControlID, inText, inColumnNumber); }
void OMCActionUIWindow::DeselectRow(CFStringRef inControlID) { OMCActionUIDeselectControlRow(GetWindowUUID(), inControlID); }
void OMCActionUIWindow::SetProperty(CFStringRef inControlID, CFStringRef inKey, CFStringRef inValue) { OMCActionUISetControlProperty(GetWindowUUID(), inControlID, inKey, inValue); }
void OMCActionUIWindow::SetState(CFStringRef inControlID, CFStringRef inKey, CFStringRef inValue) { OMCActionUISetControlState(GetWindowUUID(), inControlID, inKey, inValue); }

void
OMCActionUIWindow::PresentModal(CFStringRef inResourceNameOrPath, CFStringRef inOnDismissActionID)
{
	if( (inResourceNameOrPath == nullptr) || (::CFStringGetLength(inResourceNameOrPath) == 0) )
		return;
	CFObj<CFURLRef> documentURL( OMCCopyActionUIDocumentURL(inResourceNameOrPath, mExternBundle, mPlugin->GetBundleRef()) );
	if(documentURL == nullptr)
	{
		std::string name = ACFStringToUTF8(inResourceNameOrPath);
		OMCLogMessage("omc_dialog_control omc_present_modal: cannot find JSON: %s", name.c_str());
		return;
	}
	OMCActionUIPresentModal(GetWindowUUID(), documentURL, inOnDismissActionID);
}

void OMCActionUIWindow::DismissModal() { OMCActionUIDismissModal(GetWindowUUID()); }
void OMCActionUIWindow::PresentToast(CFStringRef inMessage, double inDuration, CFStringRef inActionTitle, CFStringRef inActionID)
	{ OMCActionUIPresentToast(GetWindowUUID(), inMessage, inDuration, inActionTitle, inActionID); }
void OMCActionUIWindow::DismissToast() { OMCActionUIDismissToast(GetWindowUUID()); }
void OMCActionUIWindow::PresentAlert(CFStringRef inTitle, CFStringRef inMessage, CFArrayRef inButtonSpecs)
	{ OMCActionUIPresentAlert(GetWindowUUID(), inTitle, inMessage, inButtonSpecs); }
void OMCActionUIWindow::PresentConfirmationDialog(CFStringRef inTitle, CFStringRef inMessage, CFArrayRef inButtonSpecs)
	{ OMCActionUIPresentConfirmationDialog(GetWindowUUID(), inTitle, inMessage, inButtonSpecs); }
void OMCActionUIWindow::DismissDialog() { OMCActionUIDismissDialog(GetWindowUUID()); }
void OMCActionUIWindow::InsertElement(CFIndex inParentID, CFStringRef inJSON, CFStringRef inContainer, CFStringRef inPosition)
	{ OMCActionUIInsertElement(GetWindowUUID(), inParentID, inJSON, inContainer, inPosition); }
void OMCActionUIWindow::InsertElementRow(CFIndex inParentID, CFStringRef inJSON, CFStringRef inContainer, CFStringRef inPosition)
	{ OMCActionUIInsertElementRow(GetWindowUUID(), inParentID, inJSON, inContainer, inPosition); }
void OMCActionUIWindow::RemoveElement(CFIndex inViewID) { OMCActionUIRemoveElement(GetWindowUUID(), inViewID); }
void OMCActionUIWindow::SetControlValue(CFStringRef inControlID, CFStringRef inValue, CFStringRef inContentType)
	{ OMCActionUISetControlValue(GetWindowUUID(), inControlID, inValue, inContentType); }
void OMCActionUIWindow::SetControlEnabled(CFStringRef inControlID, bool inEnabled) { OMCActionUISetControlEnabled(GetWindowUUID(), inControlID, inEnabled); }
void OMCActionUIWindow::SetControlVisible(CFStringRef inControlID, bool inVisible) { OMCActionUISetControlVisible(GetWindowUUID(), inControlID, inVisible); }

#pragma mark - OMCDialogControlTarget: what ActionUI's declarative layout has no use for

static void
LogUnsupported(const char *inWhat, CFStringRef inControlID)
{
	std::string controlID = ACFStringToUTF8(inControlID);
	OMCLogMessage("[OMCActionUIWindow] %s: %s - not supported in an ActionUI window", inWhat, controlID.c_str());
}

void OMCActionUIWindow::SetCommandID(CFStringRef inControlID, CFStringRef inCommandID) { (void)inCommandID; LogUnsupported("setCommandID", inControlID); }
void OMCActionUIWindow::SelectControl(CFStringRef inControlID) { LogUnsupported("selectControl", inControlID); }
void OMCActionUIWindow::MoveControl(CFStringRef inControlID, double, double) { LogUnsupported("moveControl", inControlID); }
void OMCActionUIWindow::ScrollControl(CFStringRef inControlID, double, double) { LogUnsupported("scrollControl", inControlID); }
void OMCActionUIWindow::ResizeControl(CFStringRef inControlID, double, double) { LogUnsupported("resizeControl", inControlID); }
void OMCActionUIWindow::InvokeMessagesOnControl(CFStringRef inControlID, CFArrayRef) { LogUnsupported("invokeMessages", inControlID); }

#pragma mark - OMCDialogControlTarget: the window and the application

void
OMCActionUIWindow::SetWindowTitle(CFStringRef inTitle)
{
	if(mHostedWindow != nullptr)
		mHostedWindow->SetTitle(inTitle);
}

void
OMCActionUIWindow::BringWindowToFront()
{
	if( (mHostedWindow != nullptr) && !mClosed )
		mHostedWindow->Show();
}

void OMCActionUIWindow::ActivateApplication() { OMCActivateThisApp(); }
void OMCActionUIWindow::QuitApplication() { OMCQuitThisApp(); }

// TERMINATE: closes the window as its OK or Cancel would
void
OMCActionUIWindow::CloseWindow(bool inOK)
{
	if(inOK)
		mCurrentCommandID.Adopt( (mEndOKSubcommandID != nullptr) ? mEndOKSubcommandID.Get() : CFSTR("omc.dialog.ok"), kCFObjRetain );
	else
		mCurrentCommandID.Adopt( (mEndCancelSubcommandID != nullptr) ? mEndCancelSubcommandID.Get() : CFSTR("omc.dialog.cancel"), kCFObjRetain );
	CloseFromCommand();
}

void
OMCActionUIWindow::SetWindowTopLeftPosition(double inLeft, double inTop)
{
	if(mHostedWindow != nullptr)
		mHostedWindow->SetTopLeftPosition(inLeft, inTop);
}

void
OMCActionUIWindow::SetWindowLayoutSize(double inWidth, double inHeight)
{
	if(mHostedWindow != nullptr)
		mHostedWindow->SetLayoutSize(inWidth, inHeight);
}

// INVOKE: macOS only, through the window's native handle (Platform/OMCInvoke.h)
void
OMCActionUIWindow::InvokeMessages(OMCInvokeTarget inTarget, CFArrayRef inMessages)
{
	OMCInvokeMessages(inTarget, GetNativeWindow(), inMessages);
}

#pragma mark - Running the command's window

ARefCountedObj<OMCDialog>
RunActionUIDialog(OnMyCommand *inPlugin, CommandRuntimeData *commandRuntimeData)
{
	ARefCountedObj<OMCDialog> outDialog;
	if(inPlugin == nullptr)
		return outDialog;
	assert(commandRuntimeData != nullptr);
	CommandDescription &currCommand = inPlugin->GetCurrentCommand();

	// Held for the length of the run: the window leaves the list of open windows when it closes,
	// which for a blocking window is inside the modal run
	std::shared_ptr<OMCActionUIWindow> window = OMCActionUIWindow::Create(inPlugin, commandRuntimeData);
	if(window == nullptr)
		return outDialog;

	outDialog.Adopt(window->GetDialog(), kARefCountRetain);
	bool hasWindow = (window->GetNativeWindow() != nullptr);
	window->Run();
	if( window->IsModal() )
	{
		if( hasWindow && window->IsOkeyed() )
		{
			// The window is closed but still lives until this function returns, so collect the
			// requested special values (all rows) now, as the nib dialog does: afterwards the engine
			// can no longer read them
			outDialog->CopyAllControlValues(currCommand.specialRequestedNibControls, nullptr);
		}
		else
		{
			outDialog.Adopt(nullptr);
		}
	}
	return outDialog;
}

#else // CURRENT_OMC_VERSION < 50000

ARefCountedObj<OMCDialog>
RunActionUIDialog(OnMyCommand *, CommandRuntimeData *)
{
	return ARefCountedObj<OMCDialog>();
}

#endif // CURRENT_OMC_VERSION >= 50000

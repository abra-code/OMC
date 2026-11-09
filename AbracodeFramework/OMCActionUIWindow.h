//
//  OMCActionUIWindow.h
//  Abracode
//
//  The window an ActionUI command opens (Command.plist's ACTIONUI_WINDOW), in portable C++: a window
//  of the window host (Platform/OMCWindowHost.h) around the command's ActionUI document, its dialog
//  (OMCActionUIDialog: the message port, the values for the commands), and its logic:
//  - the init subcommand before the window shows, then a modal run for a blocking window;
//  - the window's actions: an action id that is the OK or Cancel id closes the window, any other runs
//    the subcommand with that id, with the action's view, part and context in the trigger variables;
//  - the end subcommand on every close (OK or Cancel, from the window or from omc_dialog_control);
//  - the activation subcommands as the window becomes and stops being the key window;
//  - omc_dialog_control's messages, through the portable dispatcher (OMCDialogControlDispatch.h),
//    with this window as the target.
//
//  Command.plist SCHEMA SOURCE OF TRUTH - ACTIONUI_WINDOW (JSON_NAME, WINDOW_TYPE enum
//  [floating/global_floating], WINDOW_TITLE, IS_BLOCKING, INIT_SUBCOMMAND_ID, END_OK_SUBCOMMAND_ID,
//  END_CANCEL_SUBCOMMAND_ID, WINDOW_DID_ACTIVATE_SUBCOMMAND_ID, WINDOW_DID_DEACTIVATE_SUBCOMMAND_ID).
//  JSON_NAME resolves to a .json anywhere under Resources (root / localized .lproj); the subcommand-ID
//  keys reference COMMAND_IDs. Adding, removing, renaming, deprecating or retyping any key (or enum
//  value) here REQUIRES updating the matching verifier schema and rebuilding the skill, else the
//  Command.plist verifier drifts:
//    verifier schema: Distribution/AppletBuilder.app/Contents/Library/command_verifier/schemas/ACTIONUI_WINDOW.json
//    rebuild skill:   python3 Skill/build_skill.py
//
//  Main thread only.
//

#pragma once
#include "OMCDialogControlDispatch.h"
#include "OMCWindowHost.h"
#include "ARefCounted.h"
#include "CFObj.h"
#include <memory>

class OnMyCommand;
class CommandRuntimeData;
class OMCDialog;

class OMCActionUIWindow final : public OMCDialogControlTarget, public std::enable_shared_from_this<OMCActionUIWindow>
{
public:
	// Makes the window of the command now current in inPlugin, not shown yet, and registers it.
	// The window is nullptr inside when the command names no document or it cannot be loaded; the
	// object still runs the command's subcommands, as the controller it replaces did.
	static std::shared_ptr<OMCActionUIWindow> Create(OnMyCommand *inPlugin, CommandRuntimeData *inCommandRuntimeData);

	// The open windows: by the dialog's UUID, and the one that gets the keyboard's input
	static std::shared_ptr<OMCActionUIWindow> Find(CFStringRef inWindowUUID);
	static std::shared_ptr<OMCActionUIWindow> FindKeyWindow();

							~OMCActionUIWindow() override;

	OMCDialog *				GetDialog() const { return mDialog.Get(); }
	CFStringRef				GetWindowUUID() const;
	bool					IsModal() const { return mIsModal; }
	bool					IsOkeyed() const;

	// The init subcommand, then a blocking window runs modally and returns when it closes; a
	// non-blocking one is shown and this returns at once
	void					Run();

	// An action of the window, or a command a menu or a test sends to it: the OK or Cancel id closes
	// the window, any other runs the subcommand with that id
	void					DispatchCommand(CFStringRef inCommandID, CFTypeRef inContext);

	// The platform's window, for what has no portable form (macOS: the NSWindow); nullptr without one
	void *					GetNativeWindow() const;

	// OMCDialogControlTarget
	void RemoveAllListItems(CFStringRef inControlID) override;
	void SetListItems(CFStringRef inControlID, CFArrayRef inItems) override;
	void AppendListItems(CFStringRef inControlID, CFArrayRef inItems) override;
	void EmptyTable(CFStringRef inControlID) override;
	void RemoveTableRows(CFStringRef inControlID) override;
	void SetTableRows(CFStringRef inControlID, CFArrayRef inRows) override;
	void AddTableRows(CFStringRef inControlID, CFArrayRef inRows) override;
	void SetTableColumns(CFStringRef inControlID, CFArrayRef inColumns) override;
	void SetTableColumnWidths(CFStringRef inControlID, CFArrayRef inWidths) override;
	void SelectRow(CFStringRef inControlID, CFIndex inRowIndex) override;
	void SelectRowWithContent(CFStringRef inControlID, CFStringRef inText, CFIndex inColumnNumber) override;
	void DeselectRow(CFStringRef inControlID) override;
	void SetProperty(CFStringRef inControlID, CFStringRef inKey, CFStringRef inValue) override;
	void SetState(CFStringRef inControlID, CFStringRef inKey, CFStringRef inValue) override;
	void PresentModal(CFStringRef inResourceNameOrPath, CFStringRef inOnDismissActionID) override;
	void DismissModal() override;
	void PresentToast(CFStringRef inMessage, double inDuration, CFStringRef inActionTitle, CFStringRef inActionID) override;
	void DismissToast() override;
	void PresentAlert(CFStringRef inTitle, CFStringRef inMessage, CFArrayRef inButtonSpecs) override;
	void PresentConfirmationDialog(CFStringRef inTitle, CFStringRef inMessage, CFArrayRef inButtonSpecs) override;
	void DismissDialog() override;
	void InsertElement(CFIndex inParentID, CFStringRef inJSON, CFStringRef inContainer, CFStringRef inPosition) override;
	void InsertElementRow(CFIndex inParentID, CFStringRef inJSON, CFStringRef inContainer, CFStringRef inPosition) override;
	void RemoveElement(CFIndex inViewID) override;
	void SetWindowTitle(CFStringRef inTitle) override;
	void SetControlValue(CFStringRef inControlID, CFStringRef inValue, CFStringRef inContentType) override;
	void SetControlEnabled(CFStringRef inControlID, bool inEnabled) override;
	void SetControlVisible(CFStringRef inControlID, bool inVisible) override;
	void SetCommandID(CFStringRef inControlID, CFStringRef inCommandID) override;
	void BringWindowToFront() override;
	void ActivateApplication() override;
	void SelectControl(CFStringRef inControlID) override;
	void CloseWindow(bool inOK) override;
	void QuitApplication() override;
	void SetWindowTopLeftPosition(double inLeft, double inTop) override;
	void MoveControl(CFStringRef inControlID, double inLeft, double inTop) override;
	void ScrollControl(CFStringRef inControlID, double inLeft, double inTop) override;
	void SetWindowLayoutSize(double inWidth, double inHeight) override;
	void ResizeControl(CFStringRef inControlID, double inWidth, double inHeight) override;
	void InvokeMessages(OMCInvokeTarget inTarget, CFArrayRef inMessages) override;
	void InvokeMessagesOnControl(CFStringRef inControlID, CFArrayRef inMessages) override;

	// The window's values, for the dialog's accessor
	void					CopyAllControlValues(CFMutableDictionaryRef ioControlValues);
	CFTypeRef				CopyControlValue(CFStringRef inControlID, CFStringRef inControlPart);

	// The trigger variables of one action (OMC_ACTIONUI_TRIGGER_VIEW_ID, _VIEW_PART_ID, _CONTEXT)
	void					SetControlContext(CFIndex inViewID, CFIndex inViewPartID, CFStringRef inContext);
	void					ClearControlContext();

	// For Create only (std::make_shared)
							OMCActionUIWindow(OnMyCommand *inPlugin, CommandRuntimeData *inCommandRuntimeData);

private:
	void					Init();
	void					SetUpTitle(CFStringRef inWindowTitle);
	bool					IsCanceled() const;
	bool					InitializeDialog();
	void					Terminate();
	void					CloseFromCommand();
	void					WindowDidClose();
	void					RunActivationSubcommand(CFStringRef inSubcommandID);
	void					ProcessCommand(CFTypeRef inContext);
	void					Unregister();

	ARefCountedObj<OnMyCommand>			mPlugin;
	ARefCountedObj<CommandRuntimeData>	mCommandRuntimeData;
	ARefCountedObj<OMCDialog>			mDialog;
	CFObj<CFBundleRef>					mExternBundle;
	CFObj<CFArrayRef>					mCommandName;
	std::unique_ptr<OMCHostedWindow>	mHostedWindow;

	CFObj<CFStringRef>					mInitSubcommandID;
	CFObj<CFStringRef>					mEndOKSubcommandID;
	CFObj<CFStringRef>					mEndCancelSubcommandID;
	CFObj<CFStringRef>					mDidActivateSubcommandID;
	CFObj<CFStringRef>					mDidDeactivateSubcommandID;
	CFObj<CFStringRef>					mCurrentCommandID;	// the action or subcommand being handled
	bool								mIsModal { true };	// IS_BLOCKING, true when not given
	bool								mClosed { false };
};

// Runs the current command's ActionUI window (OnMyCommand.cp): returns its dialog for the command
// to read its values, or nullptr when it was canceled. A blocking window returns after it closed
// (with its values copied while the window still lived), a non-blocking one right after it opened.
ARefCountedObj<OMCDialog> RunActionUIDialog(OnMyCommand *inPlugin, CommandRuntimeData *commandRuntimeData);

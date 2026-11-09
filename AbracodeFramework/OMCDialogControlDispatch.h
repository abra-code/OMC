//
//  OMCDialogControlDispatch.h
//  Abracode
//
//  An omc_dialog_control message, as a dialog receives it (a dictionary of keys such as VALUES,
//  ENABLE_DISABLE or TERMINATE, each mapping control IDs to their arguments; omc_dialog_control/main.c
//  writes it), turned into calls on the dialog's window. Portable C++: the window is any
//  OMCDialogControlTarget, the nib and ActionUI window controllers today (OMCWindowController.mm),
//  the portable ActionUI window later.
//
//  The keys are handled in a fixed order, which is behavior: list and table contents first, then row
//  selection (so one message can fill a table and select in it), properties and states, sheets and
//  dialogs, inserted and removed elements, values, enabled and visible, command ids, SELECT, then
//  TERMINATE, which ends the handling when it closes the window or quits the application, so MOVE,
//  SCROLL, RESIZE and INVOKE in the same message are skipped. Within one key the control IDs come in
//  the dictionary's order.
//
//  Control IDs are strings; the special IDs "omc_window", "omc_application" and "omc_workspace" name
//  the window, the application and the workspace.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include "OMCInvoke.h"

class OMCDialogControlTarget
{
public:
	virtual					~OMCDialogControlTarget() = default;

	// Lists and tables
	virtual void			RemoveAllListItems(CFStringRef inControlID) = 0;
	virtual void			SetListItems(CFStringRef inControlID, CFArrayRef inItems) = 0;
	virtual void			AppendListItems(CFStringRef inControlID, CFArrayRef inItems) = 0;
	virtual void			EmptyTable(CFStringRef inControlID) = 0;
	virtual void			RemoveTableRows(CFStringRef inControlID) = 0;
	virtual void			SetTableRows(CFStringRef inControlID, CFArrayRef inRows) = 0;
	virtual void			AddTableRows(CFStringRef inControlID, CFArrayRef inRows) = 0;
	virtual void			SetTableColumns(CFStringRef inControlID, CFArrayRef inColumns) = 0;
	virtual void			SetTableColumnWidths(CFStringRef inControlID, CFArrayRef inWidths) = 0;
	virtual void			SelectRow(CFStringRef inControlID, CFIndex inRowIndex) = 0;
	virtual void			SelectRowWithContent(CFStringRef inControlID, CFStringRef inText, CFIndex inColumnNumber) = 0;
	virtual void			DeselectRow(CFStringRef inControlID) = 0;

	// Properties and states (the value as omc_dialog_control passed it: text, maybe JSON)
	virtual void			SetProperty(CFStringRef inControlID, CFStringRef inKey, CFStringRef inValue) = 0;
	virtual void			SetState(CFStringRef inControlID, CFStringRef inKey, CFStringRef inValue) = 0;

	// The window's sheets, toasts and dialogs; inMessage, inOnDismissActionID, inActionTitle and
	// inActionID may be NULL
	virtual void			PresentModal(CFStringRef inResourceNameOrPath, CFStringRef inOnDismissActionID) = 0;
	virtual void			DismissModal() = 0;
	virtual void			PresentToast(CFStringRef inMessage, double inDuration, CFStringRef inActionTitle, CFStringRef inActionID) = 0;
	virtual void			DismissToast() = 0;
	virtual void			PresentAlert(CFStringRef inTitle, CFStringRef inMessage, CFArrayRef inButtonSpecs) = 0;
	virtual void			PresentConfirmationDialog(CFStringRef inTitle, CFStringRef inMessage, CFArrayRef inButtonSpecs) = 0;
	virtual void			DismissDialog() = 0;

	// Elements added and removed at run time; inContainer and inPosition may be NULL
	virtual void			InsertElement(CFIndex inParentID, CFStringRef inJSON, CFStringRef inContainer, CFStringRef inPosition) = 0;
	virtual void			InsertElementRow(CFIndex inParentID, CFStringRef inJSON, CFStringRef inContainer, CFStringRef inPosition) = 0;
	virtual void			RemoveElement(CFIndex inViewID) = 0;

	// Values; inContentType may be NULL
	virtual void			SetWindowTitle(CFStringRef inTitle) = 0;
	virtual void			SetControlValue(CFStringRef inControlID, CFStringRef inValue, CFStringRef inContentType) = 0;
	virtual void			SetControlEnabled(CFStringRef inControlID, bool inEnabled) = 0;
	virtual void			SetControlVisible(CFStringRef inControlID, bool inVisible) = 0;
	virtual void			SetCommandID(CFStringRef inControlID, CFStringRef inCommandID) = 0;

	// SELECT
	virtual void			BringWindowToFront() = 0;
	virtual void			ActivateApplication() = 0;
	virtual void			SelectControl(CFStringRef inControlID) = 0;

	// TERMINATE: close the window as its OK or Cancel would; quit the application
	virtual void			CloseWindow(bool inOK) = 0;
	virtual void			QuitApplication() = 0;

	// MOVE, SCROLL, RESIZE: the window's top-left corner from the top-left corner of the main
	// screen's visible area, and the size of its layout area; a control's position and size
	virtual void			SetWindowTopLeftPosition(double inLeft, double inTop) = 0;
	virtual void			MoveControl(CFStringRef inControlID, double inLeft, double inTop) = 0;
	virtual void			ScrollControl(CFStringRef inControlID, double inLeft, double inTop) = 0;
	virtual void			SetWindowLayoutSize(double inWidth, double inHeight) = 0;
	virtual void			ResizeControl(CFStringRef inControlID, double inWidth, double inHeight) = 0;

	// INVOKE: messages to the window, the application or the workspace, or to a control
	virtual void			InvokeMessages(OMCInvokeTarget inTarget, CFArrayRef inMessages) = 0;
	virtual void			InvokeMessagesOnControl(CFStringRef inControlID, CFArrayRef inMessages) = 0;
};

// Handles one omc_dialog_control message; a NULL or empty one does nothing
void OMCDispatchDialogControlMessage(CFDictionaryRef inMessage, OMCDialogControlTarget &inTarget);

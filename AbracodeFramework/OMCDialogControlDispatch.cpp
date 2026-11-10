//
//  OMCDialogControlDispatch.cpp
//  Abracode
//
//  See OMCDialogControlDispatch.h. Moved from OMCWindowController.mm's setControlValues:, key by key
//  and in the same order, as part of moving the ActionUI window's logic to portable C++.
//

#include "OMCDialogControlDispatch.h"
#include "ACFDict.h"
#include "ACFType.h"
#include "CFObj.h"
#include <vector>

namespace
{

// Calls inBody(key, value) for each entry of inDict, in the dictionary's order
template <typename Body>
void ForEachEntry(CFDictionaryRef inDict, Body inBody)
{
	CFIndex count = (inDict != nullptr) ? ::CFDictionaryGetCount(inDict) : 0;
	if(count <= 0)
		return;
	std::vector<CFTypeRef> keys((size_t)count);
	std::vector<CFTypeRef> values((size_t)count);
	::CFDictionaryGetKeysAndValues(inDict, (const void **)keys.data(), (const void **)values.data());
	for(CFIndex i = 0; i < count; i++)
		inBody(keys[(size_t)i], values[(size_t)i]);
}

inline bool IsControl(CFStringRef inControlID, CFStringRef inSpecialID)
{
	return (::CFStringCompare(inControlID, inSpecialID, 0) == kCFCompareEqualTo);
}

inline CFStringRef StringAt(CFArrayRef inArray, CFIndex inIndex)
{
	if( (inArray == nullptr) || (inIndex >= ::CFArrayGetCount(inArray)) )
		return nullptr;
	return ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(inArray, inIndex) );
}

// The entries of a key whose value is an array: (control ID, array)
template <typename Body>
void ForEachControlArray(ACFDict &inMessage, CFStringRef inKey, Body inBody)
{
	CFDictionaryRef dict = nullptr;
	if( !inMessage.GetValue(inKey, dict) )
		return;
	ForEachEntry(dict, [&](CFTypeRef inKeyRef, CFTypeRef inValueRef) {
		CFStringRef controlID = ACFType<CFStringRef>::DynamicCast(inKeyRef);
		CFArrayRef array = ACFType<CFArrayRef>::DynamicCast(inValueRef);
		if( (controlID != nullptr) && (array != nullptr) )
			inBody(controlID, array);
	});
}

// The entries of a key whose value does not matter: each control ID
template <typename Body>
void ForEachControl(ACFDict &inMessage, CFStringRef inKey, Body inBody)
{
	CFDictionaryRef dict = nullptr;
	if( !inMessage.GetValue(inKey, dict) )
		return;
	ForEachEntry(dict, [&](CFTypeRef inKeyRef, CFTypeRef) {
		CFStringRef controlID = ACFType<CFStringRef>::DynamicCast(inKeyRef);
		if(controlID != nullptr)
			inBody(controlID);
	});
}

// The arguments of a window-level key (PRESENT_MODAL, PRESENT_TOAST, ...): the array under "omc_window"
CFArrayRef WindowArguments(ACFDict &inMessage, CFStringRef inKey)
{
	CFDictionaryRef dict = nullptr;
	if( !inMessage.GetValue(inKey, dict) || (dict == nullptr) )
		return nullptr;
	CFArrayRef arguments = (CFArrayRef)::CFDictionaryGetValue(dict, CFSTR("omc_window"));
	if( (arguments == nullptr) || (::CFArrayGetCount(arguments) < 1) )
		return nullptr;
	return arguments;
}

bool HasWindowEntry(ACFDict &inMessage, CFStringRef inKey)
{
	CFDictionaryRef dict = nullptr;
	if( !inMessage.GetValue(inKey, dict) )
		return false;
	return (dict != nullptr) && (::CFDictionaryGetValue(dict, CFSTR("omc_window")) != nullptr);
}

// An alert's or a confirmation dialog's button specs: the strings after the title and the message
CFArrayRef CreateButtonSpecs(CFArrayRef inArguments)
{
	CFIndex count = ::CFArrayGetCount(inArguments);
	CFObj<CFMutableArrayRef> specs( ::CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks) );
	for(CFIndex i = 2; i < count; i++)
	{
		CFStringRef spec = StringAt(inArguments, i);
		if(spec != nullptr)
			::CFArrayAppendValue(specs, spec);
	}
	return specs.Detach();
}

// MOVE, SCROLL and RESIZE's two numbers, as integers, 0 when missing
void TwoNumbers(CFArrayRef inArguments, double &outFirst, double &outSecond)
{
	CFStringRef first = StringAt(inArguments, 0);
	CFStringRef second = StringAt(inArguments, 1);
	outFirst = (first != nullptr) ? (double)::CFStringGetIntValue(first) : 0;
	outSecond = (second != nullptr) ? (double)::CFStringGetIntValue(second) : 0;
}

} // namespace

void
OMCDispatchDialogControlMessage(CFDictionaryRef inMessage, OMCDialogControlTarget &inTarget)
{
	if( (inMessage == nullptr) || (::CFDictionaryGetCount(inMessage) == 0) )
		return;

	ACFDict message(inMessage);

	// List and table contents
	ForEachControl(message, CFSTR("REMOVE_LIST_ITEMS"), [&](CFStringRef inID) { inTarget.RemoveAllListItems(inID); });
	ForEachControlArray(message, CFSTR("SET_LIST_ITEMS"), [&](CFStringRef inID, CFArrayRef inItems) { inTarget.SetListItems(inID, inItems); });
	ForEachControlArray(message, CFSTR("APPEND_LIST_ITEMS"), [&](CFStringRef inID, CFArrayRef inItems) { inTarget.AppendListItems(inID, inItems); });
	ForEachControl(message, CFSTR("PREPARE_TABLE_EMPTY"), [&](CFStringRef inID) { inTarget.EmptyTable(inID); });
	ForEachControl(message, CFSTR("REMOVE_TABLE_ROWS"), [&](CFStringRef inID) { inTarget.RemoveTableRows(inID); });
	ForEachControlArray(message, CFSTR("SET_TABLE_ROWS"), [&](CFStringRef inID, CFArrayRef inRows) { inTarget.SetTableRows(inID, inRows); });
	ForEachControlArray(message, CFSTR("ADD_TABLE_ROWS"), [&](CFStringRef inID, CFArrayRef inRows) { inTarget.AddTableRows(inID, inRows); });
	ForEachControlArray(message, CFSTR("SET_TABLE_COLUMNS"), [&](CFStringRef inID, CFArrayRef inColumns) { inTarget.SetTableColumns(inID, inColumns); });
	ForEachControlArray(message, CFSTR("SET_TABLE_WIDTHS"), [&](CFStringRef inID, CFArrayRef inWidths) { inTarget.SetTableColumnWidths(inID, inWidths); });

	// Row selection, after the contents, so that one message can fill a table and select in it
	{
		CFDictionaryRef selectRowDict = nullptr;
		if( message.GetValue(CFSTR("SELECT_ROW"), selectRowDict) )
		{
			ForEachEntry(selectRowDict, [&](CFTypeRef inKey, CFTypeRef inValue) {
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast(inKey);
				CFStringRef indexString = ACFType<CFStringRef>::DynamicCast(inValue);
				if( (controlID != nullptr) && (indexString != nullptr) )
					inTarget.SelectRow(controlID, (CFIndex)::CFStringGetIntValue(indexString));
			});
		}
	}
	ForEachControlArray(message, CFSTR("SELECT_ROW_CONTENT"), [&](CFStringRef inID, CFArrayRef inArguments) {
		if( ::CFArrayGetCount(inArguments) < 1 )
			return;
		CFStringRef text = StringAt(inArguments, 0);
		CFStringRef columnString = StringAt(inArguments, 1);
		CFIndex columnNumber = (columnString != nullptr) ? (CFIndex)::CFStringGetIntValue(columnString) : 0; // 0: any column
		if(text != nullptr)
			inTarget.SelectRowWithContent(inID, text, columnNumber);
	});
	ForEachControl(message, CFSTR("DESELECT_ROW"), [&](CFStringRef inID) { inTarget.DeselectRow(inID); });

	// Properties and states: [key, value]
	ForEachControlArray(message, CFSTR("SET_PROPERTY"), [&](CFStringRef inID, CFArrayRef inArguments) {
		CFStringRef key = StringAt(inArguments, 0);
		CFStringRef value = StringAt(inArguments, 1);
		if( (key != nullptr) && (value != nullptr) )
			inTarget.SetProperty(inID, key, value);
	});
	ForEachControlArray(message, CFSTR("SET_STATE"), [&](CFStringRef inID, CFArrayRef inArguments) {
		CFStringRef key = StringAt(inArguments, 0);
		CFStringRef value = StringAt(inArguments, 1);
		if( (key != nullptr) && (value != nullptr) )
			inTarget.SetState(inID, key, value);
	});

	// The window's sheet, toast and dialogs
	if( CFArrayRef arguments = WindowArguments(message, CFSTR("PRESENT_MODAL")) )
	{
		CFStringRef resourceNameOrPath = StringAt(arguments, 0);
		CFStringRef dismissActionID = StringAt(arguments, 1);
		if(resourceNameOrPath != nullptr)
			inTarget.PresentModal(resourceNameOrPath, dismissActionID);
	}
	if( HasWindowEntry(message, CFSTR("DISMISS_MODAL")) )
		inTarget.DismissModal();

	if( CFArrayRef arguments = WindowArguments(message, CFSTR("PRESENT_TOAST")) )
	{
		CFStringRef toastMessage = StringAt(arguments, 0);
		CFStringRef duration = StringAt(arguments, 1);
		if(toastMessage != nullptr)
			inTarget.PresentToast(toastMessage, (duration != nullptr) ? ::CFStringGetDoubleValue(duration) : 0.0,
								StringAt(arguments, 2), StringAt(arguments, 3));
	}
	if( HasWindowEntry(message, CFSTR("DISMISS_TOAST")) )
		inTarget.DismissToast();

	if( CFArrayRef arguments = WindowArguments(message, CFSTR("PRESENT_ALERT")) )
	{
		CFStringRef title = StringAt(arguments, 0);
		CFObj<CFArrayRef> buttonSpecs( CreateButtonSpecs(arguments) );
		if(title != nullptr)
			inTarget.PresentAlert(title, StringAt(arguments, 1), buttonSpecs);
	}
	if( CFArrayRef arguments = WindowArguments(message, CFSTR("PRESENT_CONFIRMATION_DIALOG")) )
	{
		CFStringRef title = StringAt(arguments, 0);
		CFObj<CFArrayRef> buttonSpecs( CreateButtonSpecs(arguments) );
		if(title != nullptr)
			inTarget.PresentConfirmationDialog(title, StringAt(arguments, 1), buttonSpecs);
	}
	if( HasWindowEntry(message, CFSTR("DISMISS_DIALOG")) )
		inTarget.DismissDialog();

	// Elements added and removed at run time: [json, container, position]
	ForEachControlArray(message, CFSTR("INSERT_ELEMENT"), [&](CFStringRef inID, CFArrayRef inArguments) {
		CFStringRef json = StringAt(inArguments, 0);
		if( (::CFArrayGetCount(inArguments) >= 1) && (json != nullptr) )
			inTarget.InsertElement((CFIndex)::CFStringGetIntValue(inID), json, StringAt(inArguments, 1), StringAt(inArguments, 2));
	});
	ForEachControlArray(message, CFSTR("INSERT_ELEMENT_ROW"), [&](CFStringRef inID, CFArrayRef inArguments) {
		CFStringRef json = StringAt(inArguments, 0);
		if( (::CFArrayGetCount(inArguments) >= 1) && (json != nullptr) )
			inTarget.InsertElementRow((CFIndex)::CFStringGetIntValue(inID), json, StringAt(inArguments, 1), StringAt(inArguments, 2));
	});
	ForEachControl(message, CFSTR("REMOVE_ELEMENT"), [&](CFStringRef inID) {
		inTarget.RemoveElement((CFIndex)::CFStringGetIntValue(inID));
	});

	// Values; "omc_window"'s value is the window's title
	{
		CFDictionaryRef valuesDict = nullptr;
		if( message.GetValue(CFSTR("VALUES"), valuesDict) )
		{
			CFDictionaryRef contentTypesDict = nullptr;
			message.GetValue(CFSTR("VALUE_CONTENT_TYPES"), contentTypesDict);
			ForEachEntry(valuesDict, [&](CFTypeRef inKey, CFTypeRef inValue) {
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast(inKey);
				if(controlID == nullptr)
					return;
				CFStringRef value = ACFType<CFStringRef>::DynamicCast(inValue);
				if( IsControl(controlID, CFSTR("omc_window")) )
				{
					if(value != nullptr)
						inTarget.SetWindowTitle(value);
					return;
				}
				CFStringRef contentType = nullptr;
				if(contentTypesDict != nullptr)
					contentType = ACFType<CFStringRef>::DynamicCast( ::CFDictionaryGetValue(contentTypesDict, controlID) );
				inTarget.SetControlValue(controlID, value, contentType);
			});
		}
	}

	// Enabled, visible: a boolean per control
	{
		CFDictionaryRef enableDisableDict = nullptr;
		if( message.GetValue(CFSTR("ENABLE_DISABLE"), enableDisableDict) )
		{
			ForEachEntry(enableDisableDict, [&](CFTypeRef inKey, CFTypeRef inValue) {
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast(inKey);
				CFBooleanRef enable = ACFType<CFBooleanRef>::DynamicCast(inValue);
				if( (controlID != nullptr) && (enable != nullptr) )
					inTarget.SetControlEnabled(controlID, ::CFBooleanGetValue(enable));
			});
		}
		CFDictionaryRef showHideDict = nullptr;
		if( message.GetValue(CFSTR("SHOW_HIDE"), showHideDict) )
		{
			ForEachEntry(showHideDict, [&](CFTypeRef inKey, CFTypeRef inValue) {
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast(inKey);
				CFBooleanRef show = ACFType<CFBooleanRef>::DynamicCast(inValue);
				if( (controlID != nullptr) && (show != nullptr) )
					inTarget.SetControlVisible(controlID, ::CFBooleanGetValue(show));
			});
		}
	}

	// Command ids: a string per control
	{
		CFDictionaryRef commandIDsDict = nullptr;
		if( message.GetValue(CFSTR("COMMAND_IDS"), commandIDsDict) )
		{
			ForEachEntry(commandIDsDict, [&](CFTypeRef inKey, CFTypeRef inValue) {
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast(inKey);
				CFStringRef commandID = ACFType<CFStringRef>::DynamicCast(inValue);
				if( (controlID != nullptr) && (commandID != nullptr) )
					inTarget.SetCommandID(controlID, commandID);
			});
		}
	}

	// SELECT: the window to the front, the application active, or a control
	ForEachControl(message, CFSTR("SELECT"), [&](CFStringRef inID) {
		if( IsControl(inID, CFSTR("omc_window")) )
			inTarget.BringWindowToFront();
		else if( IsControl(inID, CFSTR("omc_application")) )
			inTarget.ActivateApplication();
		else
			inTarget.SelectControl(inID);
	});

	// TERMINATE ends the handling when it closes the window or quits the application: the rest of
	// the message (MOVE, SCROLL, RESIZE, INVOKE) is skipped
	{
		CFDictionaryRef terminateDict = nullptr;
		if( message.GetValue(CFSTR("TERMINATE"), terminateDict) )
		{
			CFIndex count = ::CFDictionaryGetCount(terminateDict);
			std::vector<CFTypeRef> keys((size_t)count);
			std::vector<CFTypeRef> values((size_t)count);
			::CFDictionaryGetKeysAndValues(terminateDict, (const void **)keys.data(), (const void **)values.data());
			for(CFIndex i = 0; i < count; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast(keys[(size_t)i]);
				CFBooleanRef terminateOK = ACFType<CFBooleanRef>::DynamicCast(values[(size_t)i]);
				if( (controlID == nullptr) || (terminateOK == nullptr) )
					continue;
				if( IsControl(controlID, CFSTR("omc_window")) )
				{
					inTarget.CloseWindow(::CFBooleanGetValue(terminateOK));
					return;
				}
				if( IsControl(controlID, CFSTR("omc_application")) )
				{
					inTarget.QuitApplication();
					return;
				}
			}
		}
	}

	// MOVE, SCROLL, RESIZE: [x, y] and [width, height], as integers
	ForEachControlArray(message, CFSTR("MOVE"), [&](CFStringRef inID, CFArrayRef inArguments) {
		double left = 0, top = 0;
		TwoNumbers(inArguments, left, top);
		if( IsControl(inID, CFSTR("omc_window")) )
			inTarget.SetWindowTopLeftPosition(left, top);
		else
			inTarget.MoveControl(inID, left, top);
	});
	ForEachControlArray(message, CFSTR("SCROLL"), [&](CFStringRef inID, CFArrayRef inArguments) {
		double left = 0, top = 0;
		TwoNumbers(inArguments, left, top);
		inTarget.ScrollControl(inID, left, top);
	});
	ForEachControlArray(message, CFSTR("RESIZE"), [&](CFStringRef inID, CFArrayRef inArguments) {
		double width = 0, height = 0;
		TwoNumbers(inArguments, width, height);
		if( IsControl(inID, CFSTR("omc_window")) )
			inTarget.SetWindowLayoutSize(width, height);
		else
			inTarget.ResizeControl(inID, width, height);
	});

	// INVOKE: messages to the window, the application, the workspace or a control
	ForEachControlArray(message, CFSTR("INVOKE"), [&](CFStringRef inID, CFArrayRef inMessages) {
		if( IsControl(inID, CFSTR("omc_window")) )
			inTarget.InvokeMessages(OMCInvokeTarget::window, inMessages);
		else if( IsControl(inID, CFSTR("omc_application")) )
			inTarget.InvokeMessages(OMCInvokeTarget::application, inMessages);
		else if( IsControl(inID, CFSTR("omc_workspace")) )
			inTarget.InvokeMessages(OMCInvokeTarget::workspace, inMessages);
		else
			inTarget.InvokeMessagesOnControl(inID, inMessages);
	});
}

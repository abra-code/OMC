//
//  OMCInputDialog.h
//  Abracode
//
//  A command's INPUT dialog (INPUT_DIALOG in Command.plist), which asks for the text that
//  __DLG_INPUT_TEXT__ / OMC_DLG_INPUT_TEXT stands for: a message, then a text field, a password
//  field, a pop-up menu or a combo box (a text field with a menu that fills it), then Cancel and OK.
//  A built-in ActionUI document per kind (BuiltInDocuments/omc_input_*.json), run modally in a
//  window of the window host (Platform/OMCWindowHost.h). Portable: the values go to and come from
//  the document through ActionUI's C interface.
//
//  Main thread only.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <vector>
#include "CFObj.h"

class OnMyCommandCM;
class CommandRuntimeData;

// Runs the current command's input dialog. Returns true when the user pressed OK, with
// commandRuntimeData.inputText set to the choice.
Boolean RunInputDialog(OnMyCommandCM *inPlugin, CommandRuntimeData &commandRuntimeData);

struct OMCInputMenuItem
{
	CFObj<CFStringRef>	name;	// shown
	CFObj<CFStringRef>	value;	// the choice when this item is chosen; NULL: the name
};

struct OMCInputDialogSettings
{
	UInt16							type {0};			// kInputClearText, kInputPasswordText, kInputPopupMenu or kInputComboBox
	CFObj<CFStringRef>				title;
	CFObj<CFStringRef>				message;
	CFObj<CFStringRef>				okTitle;			// NULL: "OK" from the framework's Private.strings
	CFObj<CFStringRef>				cancelTitle;		// NULL: "Cancel" from the framework's Private.strings
	CFObj<CFStringRef>				defaultValue;		// the text, or the name of the menu item chosen at first
	std::vector<OMCInputMenuItem>	menuItems;			// the pop-up menu and the combo box
};

// Runs the dialog modally. Returns true when the user pressed OK, with outChoice set: the text
// typed, or the value of the menu item chosen (a combo box's text that is a menu item's name gives
// that item's value too).
bool OMCRunInputDialog(const OMCInputDialogSettings &inSettings, CFObj<CFStringRef> &outChoice);

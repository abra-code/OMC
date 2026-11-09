//
//  OMCActionUIControls.h
//  Abracode
//
//  What omc_dialog_control does to the controls of an ActionUI command window, in portable C++ over
//  ActionUI's C interface (ActionUIC.h). Each call names the window by its UUID and the control by
//  omc_dialog_control's control ID, the element's integer id as text. Main thread only, like the
//  window.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <string>

// The control's value from text; inContentType ("plain", "markdown", "html", "rtf", "json") may be NULL
void OMCActionUISetControlValue(CFStringRef inWindowUUID, CFStringRef inControlID, CFStringRef inValue, CFStringRef inContentType) noexcept;

// The element's "disabled" property, the opposite of inEnabled
void OMCActionUISetControlEnabled(CFStringRef inWindowUUID, CFStringRef inControlID, bool inEnabled) noexcept;

// The element's "hidden" property, the opposite of inVisible
void OMCActionUISetControlVisible(CFStringRef inWindowUUID, CFStringRef inControlID, bool inVisible) noexcept;

// omc_set_property and omc_set_state: inValue is used as JSON when it looks like a JSON fragment and
// parses as one (OMCActionUICreateJSONForValueText), else as a string
void OMCActionUISetControlProperty(CFStringRef inWindowUUID, CFStringRef inControlID, CFStringRef inPropertyName, CFStringRef inValue) noexcept;
void OMCActionUISetControlState(CFStringRef inWindowUUID, CFStringRef inControlID, CFStringRef inStateKey, CFStringRef inValue) noexcept;

// Lists and tables keep their items as rows of strings (a list's rows have one column each)

// Removes every row: omc_list_remove_all, omc_table_remove_all_rows and omc_table_prepare_empty
void OMCActionUIClearControlRows(CFStringRef inWindowUUID, CFStringRef inControlID) noexcept;

// A list's items, one row each (strings); set replaces them all, even with none, and append adds
// nothing for none
void OMCActionUISetControlListItems(CFStringRef inWindowUUID, CFStringRef inControlID, CFArrayRef inItems) noexcept;
void OMCActionUIAppendControlListItems(CFStringRef inWindowUUID, CFStringRef inControlID, CFArrayRef inItems) noexcept;

// A table's rows, each a string with its cells separated by tabs; set and append as for list items
void OMCActionUISetControlTableRows(CFStringRef inWindowUUID, CFStringRef inControlID, CFArrayRef inTabSeparatedRows) noexcept;
void OMCActionUIAppendControlTableRows(CFStringRef inWindowUUID, CFStringRef inControlID, CFArrayRef inTabSeparatedRows) noexcept;

// The table's "columns" property (names) and "widths" property (numbers, or strings read as numbers)
void OMCActionUISetControlTableColumns(CFStringRef inWindowUUID, CFStringRef inControlID, CFArrayRef inColumnNames) noexcept;
void OMCActionUISetControlTableColumnWidths(CFStringRef inWindowUUID, CFStringRef inControlID, CFArrayRef inWidths) noexcept;

// Selects the row at a 0-based index
void OMCActionUISelectControlRow(CFStringRef inWindowUUID, CFStringRef inControlID, CFIndex inRowIndex) noexcept;

// Selects the first row with a cell that is exactly inText, in the 1-based column inColumnNumber
// (OMC's column numbers, as in OMC_ACTIONUI_TABLE_<ID>_COLUMN_<M>_VALUE), or in any column for 0
void OMCActionUISelectControlRowWithContent(CFStringRef inWindowUUID, CFStringRef inControlID, CFStringRef inText, CFIndex inColumnNumber) noexcept;

void OMCActionUIDeselectControlRow(CFStringRef inWindowUUID, CFStringRef inControlID) noexcept;

// The JSON ActionUI is given for a value omc_dialog_control passed as text: when the text starts as
// a JSON fragment does ({, [, ", t, f, n, a digit or -) and parses as JSON (as NSJSONSerialization
// did, ACFJSON.h), that value, written out again; otherwise the text as a JSON string. Empty when
// inValue is NULL or has no UTF-8 form (a lone surrogate). Written out again rather than passed on
// because ActionUI's parser reads a number's text exactly where NSJSONSerialization made a double:
// 9007199254740993.0 must arrive as the double's 9007199254740992, as it did. (ActionUI's parser
// accepts trailing commas itself.)
std::string OMCActionUICreateJSONForValueText(CFStringRef inValue) noexcept;

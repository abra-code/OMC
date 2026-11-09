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

// The JSON ActionUI is given for a value omc_dialog_control passed as text: when the text starts as
// a JSON fragment does ({, [, ", t, f, n, a digit or -) and parses as JSON (as NSJSONSerialization
// did, ACFJSON.h), that value, written out again; otherwise the text as a JSON string. Empty when
// inValue is NULL or has no UTF-8 form (a lone surrogate). Written out again rather than passed on
// because ActionUI's parser reads a number's text exactly where NSJSONSerialization made a double:
// 9007199254740993.0 must arrive as the double's 9007199254740992, as it did. (ActionUI's parser
// accepts trailing commas itself.)
std::string OMCActionUICreateJSONForValueText(CFStringRef inValue) noexcept;

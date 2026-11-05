//
//  OMCDialogControlAccessor.h
//  Abracode
//
//  How an OMCDialog reads and writes the controls of its window, in plain C++.
//  The window layer provides one: on macOS, Platform/Apple/OMCControlAccessorBridge wraps a window
//  controller that adopts the Objective-C OMCControlAccessor protocol. The dialog owns its accessor.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

class SelectionIterator;

class OMCDialogControlAccessor
{
public:
	virtual					~OMCDialogControlAccessor() = default;

	// Sets control values from a dictionary in the format omc_dialog_control writes.
	virtual void			SetControlValues(CFDictionaryRef inControlDict) noexcept = 0;

	// Adds the value of every control to ioControlValues (key: control ID, value: dictionary of
	// column/part to value) and any custom properties to ioCustomProperties.
	virtual void			CopyAllControlValues(CFMutableDictionaryRef ioControlValues,
												CFMutableDictionaryRef ioCustomProperties,
												SelectionIterator *inSelIterator) noexcept = 0;

	// The value of one control part, retained (caller releases), or NULL. *outCustomProperties,
	// when given, receives the control's custom properties, also retained (caller releases), or NULL.
	virtual CFTypeRef		CopyControlValue(CFStringRef inControlID, CFStringRef inControlPart,
											SelectionIterator *inSelIterator,
											CFDictionaryRef *outCustomProperties) noexcept = 0;
};

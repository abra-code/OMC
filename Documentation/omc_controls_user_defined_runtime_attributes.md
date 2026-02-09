OMC Controls Custom Properties
The following custom properties are supported by OMC controls to put in “User Defined Runtime Attributes” in “Identity” inspector in Xcode.

```
The strings below are for columns:
	“Type”		“Key Path”

OMCBox:
	Number		tag

OMCButton:
	String		commandID
	String		mappedOnValue
	String		mappedOffValue
	String		escapingMode
	Boolean		acceptFileDrop
	Boolean		acceptTextDrop

OMCButtonCell:
	String		commandID
	String		mappedOnValue
	String		mappedOffValue
	String		escapingMode

OMCComboBox:
	String		commandID
	String		escapingMode

OMCIKImageView:
	Number		tag
	String		escapingMode

OMCImageView:
	String		commandID
	String		escapingMode

OMCMenuItem:
	String		commandID
	String		mappedValue
	String		escapingMode

OMCPDFView:
	Number		tag
	String		escapingMode

OMCPopUpButton:
	String		commandID

OMCProgressIndicator:
	Number		tag

OMCSearchField:
	String		commandID
	String		escapingMode

OMCSecureTextField:
	String		commandID
	String		escapingMode

OMCSlider:
	String		commandID

OMCTableView:
	String		selectionCommandID
	String		doubleClickCommandID
	String		combinedSelectionPrefix
	String		combinedSelectionSuffix
	String		combinedSelectionSeparator
	String		multipleColumnPrefix
	String		multipleColumnSuffix
	String		multipleColumnSeparator
	String		escapingMode

OMCTextField:
	String		commandID
	String		escapingMode

OMCTextView:
	Number		tag
	String		escapingMode

OMCView:
	Number		tag

OMCWebView:
	Number		tag
	String		escapingMode


escapingMode predefined strings:
	esc_none
	esc_with_backslash
	esc_with_percent
	esc_with_percent_all
	esc_for_applescript
	esc_wrap_with_single_quotes_for_shell

```

//
//  OMCActionUIControls.cpp
//  Abracode
//
//  See OMCActionUIControls.h. Moved from OMCActionUIWindowController.mm, which made the same changes
//  through ActionUI's Objective-C adapter, as part of moving the ActionUI window's logic to portable
//  C++.
//

#include "OMCActionUIControls.h"
#include "CFObj.h"
#include "ACFString.h"
#include "ACFJSON.h"
#include "ActionUIC.h"
#include "OMCLog.h"
#include <climits>
#include <cstring>
#include <vector>
#include <fstream>
#include <iterator>

static int64_t
ViewIDFromControlID(CFStringRef inControlID) noexcept
{
	return (int64_t)::CFStringGetIntValue(inControlID);
}

static std::string
JSONText(CFPropertyListRef inValue) noexcept
{
	CFObj<CFDataRef> json( ACFJSONCreateData(inValue, nullptr) );
	if(json == nullptr)
		return std::string();
	return std::string((const char *)::CFDataGetBytePtr(json), (size_t)::CFDataGetLength(json));
}

// Whether the text starts as a JSON fragment does, which saves parsing the plain strings that are
// most of what scripts send
static bool
LooksLikeJSONFragment(CFStringRef inText) noexcept
{
	if( ::CFStringGetLength(inText) == 0 )
		return false;
	UniChar first = ::CFStringGetCharacterAtIndex(inText, 0);
	switch(first)
	{
		case '{': case '[':				// object, array
		case '"':						// quoted string
		case 't': case 'f': case 'n':	// true, false, null
			return true;
		default:
			return ((first >= '0') && (first <= '9')) || (first == '-'); // number
	}
}

std::string
OMCActionUICreateJSONForValueText(CFStringRef inValue) noexcept
{
	if(inValue == nullptr)
		return std::string();

	if( LooksLikeJSONFragment(inValue) )
	{
		CFObj<CFDataRef> textData( ::CFStringCreateExternalRepresentation(kCFAllocatorDefault, inValue, kCFStringEncodingUTF8, 0) );
		if(textData != nullptr)
		{
			CFObj<CFPropertyListRef> parsed( ACFJSONCreatePropertyList(textData, kCFPropertyListImmutable, nullptr) );
			if(parsed != nullptr)
			{
				std::string json = JSONText(parsed);
				if( !json.empty() )
					return json;
			}
		}
	}
	return JSONText(inValue);
}

void
OMCActionUISetControlValue(CFStringRef inWindowUUID, CFStringRef inControlID, CFStringRef inValue, CFStringRef inContentType) noexcept
{
	if( (inWindowUUID == nullptr) || (inControlID == nullptr) || (inValue == nullptr) )
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	std::string value = ACFStringToUTF8(inValue);
	std::string contentType = ACFStringToUTF8(inContentType);
	actionUISetElementValueString(uuid.c_str(), ViewIDFromControlID(inControlID), 0, value.c_str(),
								(inContentType != nullptr) ? contentType.c_str() : nullptr);
}

static void
SetPropertyJSON(CFStringRef inWindowUUID, CFStringRef inControlID, const char *inPropertyName, const std::string &inJSON) noexcept
{
	if( (inWindowUUID == nullptr) || (inControlID == nullptr) || inJSON.empty() )
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	actionUISetElementPropertyJSON(uuid.c_str(), ViewIDFromControlID(inControlID), inPropertyName, inJSON.c_str());
}

void
OMCActionUISetControlEnabled(CFStringRef inWindowUUID, CFStringRef inControlID, bool inEnabled) noexcept
{
	SetPropertyJSON(inWindowUUID, inControlID, "disabled", inEnabled ? "false" : "true");
}

void
OMCActionUISetControlVisible(CFStringRef inWindowUUID, CFStringRef inControlID, bool inVisible) noexcept
{
	SetPropertyJSON(inWindowUUID, inControlID, "hidden", inVisible ? "false" : "true");
}

void
OMCActionUISetControlProperty(CFStringRef inWindowUUID, CFStringRef inControlID, CFStringRef inPropertyName, CFStringRef inValue) noexcept
{
	if( (inPropertyName == nullptr) || (inValue == nullptr) )
		return;
	std::string propertyName = ACFStringToUTF8(inPropertyName);
	SetPropertyJSON(inWindowUUID, inControlID, propertyName.c_str(), OMCActionUICreateJSONForValueText(inValue));
}

void
OMCActionUISetControlState(CFStringRef inWindowUUID, CFStringRef inControlID, CFStringRef inStateKey, CFStringRef inValue) noexcept
{
	if( (inWindowUUID == nullptr) || (inControlID == nullptr) || (inStateKey == nullptr) || (inValue == nullptr) )
		return;
	std::string json = OMCActionUICreateJSONForValueText(inValue);
	if( json.empty() )
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	std::string stateKey = ACFStringToUTF8(inStateKey);
	actionUISetElementStateJSON(uuid.c_str(), ViewIDFromControlID(inControlID), stateKey.c_str(), json.c_str());
}

#pragma mark - Lists and tables

static void
SetRowsJSON(CFStringRef inWindowUUID, CFStringRef inControlID, CFArrayRef inRows, bool inAppend) noexcept
{
	if( (inWindowUUID == nullptr) || (inControlID == nullptr) )
		return;
	std::string json = JSONText(inRows);
	if( json.empty() )
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	if(inAppend)
		actionUIAppendElementRowsJSON(uuid.c_str(), ViewIDFromControlID(inControlID), json.c_str());
	else
		actionUISetElementRowsJSON(uuid.c_str(), ViewIDFromControlID(inControlID), json.c_str());
}

// Each item a row of one cell; items that are not strings are left out
static CFArrayRef
CreateListRows(CFArrayRef inItems) noexcept
{
	CFIndex count = (inItems != nullptr) ? ::CFArrayGetCount(inItems) : 0;
	CFMutableArrayRef rows = ::CFArrayCreateMutable(kCFAllocatorDefault, count, &kCFTypeArrayCallBacks);
	for(CFIndex i = 0; i < count; i++)
	{
		CFTypeRef item = ::CFArrayGetValueAtIndex(inItems, i);
		if( (item == nullptr) || (::CFGetTypeID(item) != ::CFStringGetTypeID()) )
			continue;
		CFObj<CFArrayRef> row( ::CFArrayCreate(kCFAllocatorDefault, &item, 1, &kCFTypeArrayCallBacks) );
		::CFArrayAppendValue(rows, row);
	}
	return rows;
}

// Each string split into cells at its tabs; items that are not strings are left out
static CFArrayRef
CreateTableRows(CFArrayRef inTabSeparatedRows) noexcept
{
	CFIndex count = (inTabSeparatedRows != nullptr) ? ::CFArrayGetCount(inTabSeparatedRows) : 0;
	CFMutableArrayRef rows = ::CFArrayCreateMutable(kCFAllocatorDefault, count, &kCFTypeArrayCallBacks);
	for(CFIndex i = 0; i < count; i++)
	{
		CFTypeRef item = ::CFArrayGetValueAtIndex(inTabSeparatedRows, i);
		if( (item == nullptr) || (::CFGetTypeID(item) != ::CFStringGetTypeID()) )
			continue;
		CFObj<CFArrayRef> cells( ::CFStringCreateArrayBySeparatingStrings(kCFAllocatorDefault, (CFStringRef)item, CFSTR("\t")) );
		if(cells != nullptr)
			::CFArrayAppendValue(rows, cells);
	}
	return rows;
}

void
OMCActionUIClearControlRows(CFStringRef inWindowUUID, CFStringRef inControlID) noexcept
{
	if( (inWindowUUID == nullptr) || (inControlID == nullptr) )
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	actionUIClearElementRows(uuid.c_str(), ViewIDFromControlID(inControlID));
}

void
OMCActionUISetControlListItems(CFStringRef inWindowUUID, CFStringRef inControlID, CFArrayRef inItems) noexcept
{
	CFObj<CFArrayRef> rows( CreateListRows(inItems) );
	SetRowsJSON(inWindowUUID, inControlID, rows, false);
}

void
OMCActionUIAppendControlListItems(CFStringRef inWindowUUID, CFStringRef inControlID, CFArrayRef inItems) noexcept
{
	CFObj<CFArrayRef> rows( CreateListRows(inItems) );
	if( ::CFArrayGetCount(rows) > 0 )
		SetRowsJSON(inWindowUUID, inControlID, rows, true);
}

void
OMCActionUISetControlTableRows(CFStringRef inWindowUUID, CFStringRef inControlID, CFArrayRef inTabSeparatedRows) noexcept
{
	CFObj<CFArrayRef> rows( CreateTableRows(inTabSeparatedRows) );
	SetRowsJSON(inWindowUUID, inControlID, rows, false);
}

void
OMCActionUIAppendControlTableRows(CFStringRef inWindowUUID, CFStringRef inControlID, CFArrayRef inTabSeparatedRows) noexcept
{
	CFObj<CFArrayRef> rows( CreateTableRows(inTabSeparatedRows) );
	if( ::CFArrayGetCount(rows) > 0 )
		SetRowsJSON(inWindowUUID, inControlID, rows, true);
}

void
OMCActionUISetControlTableColumns(CFStringRef inWindowUUID, CFStringRef inControlID, CFArrayRef inColumnNames) noexcept
{
	CFIndex count = (inColumnNames != nullptr) ? ::CFArrayGetCount(inColumnNames) : 0;
	CFObj<CFMutableArrayRef> names( ::CFArrayCreateMutable(kCFAllocatorDefault, count, &kCFTypeArrayCallBacks) );
	for(CFIndex i = 0; i < count; i++)
	{
		CFTypeRef name = ::CFArrayGetValueAtIndex(inColumnNames, i);
		if(name != nullptr)
			::CFArrayAppendValue(names, name);
	}
	SetPropertyJSON(inWindowUUID, inControlID, "columns", JSONText(names));
}

void
OMCActionUISetControlTableColumnWidths(CFStringRef inWindowUUID, CFStringRef inControlID, CFArrayRef inWidths) noexcept
{
	CFIndex count = (inWidths != nullptr) ? ::CFArrayGetCount(inWidths) : 0;
	CFObj<CFMutableArrayRef> widths( ::CFArrayCreateMutable(kCFAllocatorDefault, count, &kCFTypeArrayCallBacks) );
	for(CFIndex i = 0; i < count; i++)
	{
		CFTypeRef item = ::CFArrayGetValueAtIndex(inWidths, i);
		double width = 0;
		if( (item != nullptr) && (::CFGetTypeID(item) == ::CFNumberGetTypeID()) )
			::CFNumberGetValue((CFNumberRef)item, kCFNumberDoubleType, &width);
		else if( (item != nullptr) && (::CFGetTypeID(item) == ::CFStringGetTypeID()) )
			width = ::CFStringGetDoubleValue((CFStringRef)item);
		else
			continue;
		CFObj<CFNumberRef> number( ::CFNumberCreate(kCFAllocatorDefault, kCFNumberDoubleType, &width) );
		::CFArrayAppendValue(widths, number);
	}
	SetPropertyJSON(inWindowUUID, inControlID, "widths", JSONText(widths));
}

#pragma mark - Row selection

void
OMCActionUISelectControlRow(CFStringRef inWindowUUID, CFStringRef inControlID, CFIndex inRowIndex) noexcept
{
	if( (inWindowUUID == nullptr) || (inControlID == nullptr) )
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	actionUISelectElementRowByIndex(uuid.c_str(), ViewIDFromControlID(inControlID), (int64_t)inRowIndex);
}

void
OMCActionUISelectControlRowWithContent(CFStringRef inWindowUUID, CFStringRef inControlID, CFStringRef inText, CFIndex inColumnNumber) noexcept
{
	if( (inWindowUUID == nullptr) || (inControlID == nullptr) || (inText == nullptr) )
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	std::string text = ACFStringToUTF8(inText);
	// ActionUI's columns are 0-based, and a negative one means any column
	int64_t zeroBasedColumn = (inColumnNumber > 0) ? (int64_t)(inColumnNumber - 1) : -1;
	(void)actionUISelectElementRowWithContent(uuid.c_str(), ViewIDFromControlID(inControlID), text.c_str(), zeroBasedColumn); // no match is not an error
}

void
OMCActionUIDeselectControlRow(CFStringRef inWindowUUID, CFStringRef inControlID) noexcept
{
	if( (inWindowUUID == nullptr) || (inControlID == nullptr) )
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	actionUIClearElementSelection(uuid.c_str(), ViewIDFromControlID(inControlID));
}

#pragma mark - Modal, toast, alert and confirmation

// ActionUI's last error, for the log
static std::string
LastActionUIError() noexcept
{
	char *error = actionUIGetLastError();
	if(error == nullptr)
		return std::string("unknown error");
	std::string outError(error);
	actionUIFreeString(error);
	return outError;
}

void
OMCActionUIPresentModal(CFStringRef inWindowUUID, CFURLRef inDocumentURL, CFStringRef inOnDismissActionID) noexcept
{
	if( (inWindowUUID == nullptr) || (inDocumentURL == nullptr) )
		return;
	char path[PATH_MAX];
	if( !::CFURLGetFileSystemRepresentation(inDocumentURL, true, (UInt8 *)path, sizeof(path)) )
	{
		OMCLogMessage("omc_dialog_control omc_present_modal: the document path is too long");
		return;
	}
	std::ifstream file(path, std::ios::in | std::ios::binary);
	if( !file )
	{
		OMCLogMessage("omc_dialog_control omc_present_modal: cannot read the document at %s", path);
		return;
	}
	std::string json( (std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>() );
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	std::string dismissActionID = ACFStringToUTF8(inOnDismissActionID);
	bool presented = actionUIPresentModal(uuid.c_str(), json.c_str(), "json", ActionUIModalStyleSheet,
										(inOnDismissActionID != nullptr) ? dismissActionID.c_str() : nullptr);
	if( !presented )
		OMCLogMessage("omc_dialog_control omc_present_modal: %s", LastActionUIError().c_str());
}

void
OMCActionUIDismissModal(CFStringRef inWindowUUID) noexcept
{
	if(inWindowUUID == nullptr)
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	actionUIDismissModal(uuid.c_str());
}

void
OMCActionUIPresentToast(CFStringRef inWindowUUID, CFStringRef inMessage, double inDuration, CFStringRef inActionTitle, CFStringRef inActionID) noexcept
{
	if( (inWindowUUID == nullptr) || (inMessage == nullptr) || (::CFStringGetLength(inMessage) == 0) )
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	std::string message = ACFStringToUTF8(inMessage);
	std::string actionTitle = ACFStringToUTF8(inActionTitle);
	std::string actionID = ACFStringToUTF8(inActionID);
	actionUIPresentToast(uuid.c_str(), message.c_str(), (inDuration > 0) ? inDuration : 4.0,
						actionTitle.empty() ? nullptr : actionTitle.c_str(),
						actionID.empty() ? nullptr : actionID.c_str());
}

void
OMCActionUIDismissToast(CFStringRef inWindowUUID) noexcept
{
	if(inWindowUUID == nullptr)
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	actionUIDismissToast(uuid.c_str());
}

// The buttons as ActionUI's JSON: [{"title":..., "role":..., "actionID":...}], role and actionID left
// out for the default role and no action
static CFArrayRef
CreateButtonDescriptors(CFArrayRef inButtonSpecs) noexcept
{
	CFIndex count = (inButtonSpecs != nullptr) ? ::CFArrayGetCount(inButtonSpecs) : 0;
	CFMutableArrayRef buttons = ::CFArrayCreateMutable(kCFAllocatorDefault, count, &kCFTypeArrayCallBacks);
	for(CFIndex i = 0; i < count; i++)
	{
		CFTypeRef spec = ::CFArrayGetValueAtIndex(inButtonSpecs, i);
		if( (spec == nullptr) || (::CFGetTypeID(spec) != ::CFStringGetTypeID()) )
			continue;
		CFObj<CFArrayRef> parts( ::CFStringCreateArrayBySeparatingStrings(kCFAllocatorDefault, (CFStringRef)spec, CFSTR(":")) );
		CFIndex partCount = (parts != nullptr) ? ::CFArrayGetCount(parts) : 0;
		CFStringRef title = (partCount >= 1) ? (CFStringRef)::CFArrayGetValueAtIndex(parts, 0) : nullptr;
		if( (title == nullptr) || (::CFStringGetLength(title) == 0) )
			continue;
		CFStringRef role = (partCount >= 2) ? (CFStringRef)::CFArrayGetValueAtIndex(parts, 1) : nullptr;
		CFStringRef actionID = (partCount >= 3) ? (CFStringRef)::CFArrayGetValueAtIndex(parts, 2) : nullptr;

		CFObj<CFMutableDictionaryRef> button( ::CFDictionaryCreateMutable(kCFAllocatorDefault, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks) );
		::CFDictionarySetValue(button, CFSTR("title"), title);
		if( (role != nullptr) && ((::CFStringCompare(role, CFSTR("cancel"), 0) == kCFCompareEqualTo) ||
								  (::CFStringCompare(role, CFSTR("destructive"), 0) == kCFCompareEqualTo)) )
			::CFDictionarySetValue(button, CFSTR("role"), role);
		if( (actionID != nullptr) && (::CFStringGetLength(actionID) > 0) )
			::CFDictionarySetValue(button, CFSTR("actionID"), actionID);
		::CFArrayAppendValue(buttons, button);
	}
	return buttons;
}

void
OMCActionUIPresentAlert(CFStringRef inWindowUUID, CFStringRef inTitle, CFStringRef inMessage, CFArrayRef inButtonSpecs) noexcept
{
	if( (inWindowUUID == nullptr) || (inTitle == nullptr) || (::CFStringGetLength(inTitle) == 0) )
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	std::string title = ACFStringToUTF8(inTitle);
	std::string message = ACFStringToUTF8(inMessage);
	CFObj<CFArrayRef> buttons( CreateButtonDescriptors(inButtonSpecs) );
	std::string buttonsJSON = (::CFArrayGetCount(buttons) > 0) ? JSONText(buttons) : std::string();
	actionUIPresentAlert(uuid.c_str(), title.c_str(), message.empty() ? nullptr : message.c_str(),
						buttonsJSON.empty() ? nullptr : buttonsJSON.c_str());
}

void
OMCActionUIPresentConfirmationDialog(CFStringRef inWindowUUID, CFStringRef inTitle, CFStringRef inMessage, CFArrayRef inButtonSpecs) noexcept
{
	if( (inWindowUUID == nullptr) || (inTitle == nullptr) || (::CFStringGetLength(inTitle) == 0) )
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	std::string title = ACFStringToUTF8(inTitle);
	std::string message = ACFStringToUTF8(inMessage);
	CFObj<CFArrayRef> buttons( CreateButtonDescriptors(inButtonSpecs) );
	std::string buttonsJSON = JSONText(buttons);
	actionUIPresentConfirmationDialog(uuid.c_str(), title.c_str(), message.empty() ? nullptr : message.c_str(),
									buttonsJSON.empty() ? "[]" : buttonsJSON.c_str());
}

void
OMCActionUIDismissDialog(CFStringRef inWindowUUID) noexcept
{
	if(inWindowUUID == nullptr)
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	actionUIDismissDialog(uuid.c_str());
}

#pragma mark - Inserted and removed elements

// "prepend", "at:<index>", "before:<id>", "after:<id>"; anything else appends
static ActionUIInsertPosition
ParsePosition(CFStringRef inPosition, int64_t *outParam) noexcept
{
	*outParam = 0;
	if( (inPosition == nullptr) || (::CFStringGetLength(inPosition) == 0) )
		return ActionUIInsertPositionAppend;
	if( ::CFStringCompare(inPosition, CFSTR("prepend"), 0) == kCFCompareEqualTo )
		return ActionUIInsertPositionPrepend;

	struct { CFStringRef prefix; ActionUIInsertPosition position; } kPrefixes[] = {
		{ CFSTR("at:"), ActionUIInsertPositionAt },
		{ CFSTR("before:"), ActionUIInsertPositionBefore },
		{ CFSTR("after:"), ActionUIInsertPositionAfter }
	};
	for(const auto &prefix : kPrefixes)
	{
		if( ::CFStringHasPrefix(inPosition, prefix.prefix) )
		{
			CFIndex prefixLength = ::CFStringGetLength(prefix.prefix);
			CFObj<CFStringRef> param( ::CFStringCreateWithSubstring(kCFAllocatorDefault, inPosition,
											CFRangeMake(prefixLength, ::CFStringGetLength(inPosition) - prefixLength)) );
			*outParam = (int64_t)::CFStringGetIntValue(param);
			return prefix.position;
		}
	}
	return ActionUIInsertPositionAppend;
}

void
OMCActionUIInsertElement(CFStringRef inWindowUUID, CFIndex inParentID, CFStringRef inJSON, CFStringRef inContainer, CFStringRef inPosition) noexcept
{
	if( (inWindowUUID == nullptr) || (inJSON == nullptr) || (::CFStringGetLength(inJSON) == 0) )
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	std::string json = ACFStringToUTF8(inJSON);
	std::string container = ACFStringToUTF8(inContainer);
	int64_t positionParam = 0;
	ActionUIInsertPosition position = ParsePosition(inPosition, &positionParam);
	int64_t insertedID = actionUIInsertElement(uuid.c_str(), (int64_t)inParentID, json.c_str(),
											(inContainer != nullptr) ? container.c_str() : nullptr, position, positionParam);
	if(insertedID == -1) // only -1 is a failure: an element with no "id" gets a negative one from -2 down
		OMCLogMessage("omc_dialog_control omc_insert_element: %s", LastActionUIError().c_str());
}

void
OMCActionUIInsertElementRow(CFStringRef inWindowUUID, CFIndex inParentID, CFStringRef inJSON, CFStringRef inContainer, CFStringRef inPosition) noexcept
{
	if( (inWindowUUID == nullptr) || (inJSON == nullptr) || (::CFStringGetLength(inJSON) == 0) )
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	std::string json = ACFStringToUTF8(inJSON);
	std::string container = ACFStringToUTF8(inContainer);
	int64_t positionParam = 0;
	ActionUIInsertPosition position = ParsePosition(inPosition, &positionParam);
	char *insertedIDs = actionUIInsertRow(uuid.c_str(), (int64_t)inParentID, json.c_str(),
										(inContainer != nullptr) ? container.c_str() : nullptr, position, positionParam);
	if(insertedIDs == nullptr)
		OMCLogMessage("omc_dialog_control omc_insert_element_row: %s", LastActionUIError().c_str());
	else
		actionUIFreeString(insertedIDs);
}

void
OMCActionUIRemoveElement(CFStringRef inWindowUUID, CFIndex inViewID) noexcept
{
	if(inWindowUUID == nullptr)
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	if( !actionUIRemoveElement(uuid.c_str(), (int64_t)inViewID) )
		OMCLogMessage("omc_dialog_control omc_remove_element: %s", LastActionUIError().c_str());
}

#pragma mark - Values for the commands

// ActionUI's text as a CFString (the caller releases it), or NULL; frees inText
static CFStringRef
CreateStringAndFree(char *inText) noexcept
{
	if(inText == nullptr)
		return nullptr;
	CFStringRef outString = ::CFStringCreateWithCString(kCFAllocatorDefault, inText, kCFStringEncodingUTF8);
	actionUIFreeString(inText);
	return outString;
}

// ActionUI's JSON as a property list (the caller releases it), or NULL; frees inJSON
static CFPropertyListRef
CreatePropertyListAndFree(char *inJSON) noexcept
{
	if(inJSON == nullptr)
		return nullptr;
	CFObj<CFDataRef> data( ::CFDataCreate(kCFAllocatorDefault, (const UInt8 *)inJSON, (CFIndex)strlen(inJSON)) );
	actionUIFreeString(inJSON);
	if(data == nullptr)
		return nullptr;
	return ACFJSONCreatePropertyList(data, kCFPropertyListImmutable, nullptr);
}

static CFStringRef
CopyElementValue(const std::string &inWindowUUID, int64_t inViewID, int64_t inPartID) noexcept
{
	return CreateStringAndFree( actionUIGetElementValueString(inWindowUUID.c_str(), inViewID, inPartID, nullptr) );
}

void
OMCActionUICopyAllControlValues(CFStringRef inWindowUUID, CFMutableDictionaryRef ioControlValues) noexcept
{
	if( (inWindowUUID == nullptr) || (ioControlValues == nullptr) )
		return;
	std::string uuid = ACFStringToUTF8(inWindowUUID);

	// {"<id>": "<element type>", ...}, the ids ActionUI lists (positive ones)
	CFObj<CFPropertyListRef> info( CreatePropertyListAndFree(actionUIGetElementInfoJSON(uuid.c_str())) );
	if( (info == nullptr) || (::CFGetTypeID(info) != ::CFDictionaryGetTypeID()) )
		return;
	CFDictionaryRef infoDict = (CFDictionaryRef)info.Get();
	CFIndex elementCount = ::CFDictionaryGetCount(infoDict);
	if(elementCount == 0)
		return;
	std::vector<CFTypeRef> keys((size_t)elementCount);
	::CFDictionaryGetKeysAndValues(infoDict, keys.data(), nullptr);

	for(CFTypeRef key : keys)
	{
		if( (key == nullptr) || (::CFGetTypeID(key) != ::CFStringGetTypeID()) )
			continue;
		CFStringRef controlID = (CFStringRef)key;
		int64_t viewID = ViewIDFromControlID(controlID);

		int64_t columnCount = actionUIGetElementColumnCount(uuid.c_str(), viewID);
		if(columnCount > 0)
		{
			// Every column's part, empty when no row is selected, so that
			// OMC_ACTIONUI_TABLE_<ID>_COLUMN_<M>_VALUE is always exported
			CFObj<CFMutableDictionaryRef> parts( ::CFDictionaryCreateMutable(kCFAllocatorDefault, (CFIndex)columnCount + 1,
															&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks) );
			for(int64_t partID = 0; partID <= columnCount; partID++)
			{
				CFObj<CFStringRef> partKey( ::CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("%lld"), (long long)partID) );
				CFObj<CFStringRef> value( CopyElementValue(uuid, viewID, partID) );
				::CFDictionarySetValue(parts, partKey, (value != nullptr) ? (CFStringRef)value : CFSTR(""));
			}
			::CFDictionarySetValue(ioControlValues, controlID, parts);
		}
		else
		{
			CFObj<CFStringRef> value( CopyElementValue(uuid, viewID, 0) );
			if(value == nullptr)
				continue;
			CFObj<CFMutableDictionaryRef> parts( ::CFDictionaryCreateMutable(kCFAllocatorDefault, 1,
															&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks) );
			::CFDictionarySetValue(parts, CFSTR("0"), value);
			::CFDictionarySetValue(ioControlValues, controlID, parts);
		}
	}
}

CFStringRef
OMCActionUICopyControlValue(CFStringRef inWindowUUID, CFStringRef inControlID, CFStringRef inControlPart) noexcept
{
	if( (inWindowUUID == nullptr) || (inControlID == nullptr) )
		return nullptr;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	int64_t partID = (inControlPart != nullptr) ? (int64_t)::CFStringGetIntValue(inControlPart) : 0;
	return CopyElementValue(uuid, ViewIDFromControlID(inControlID), partID);
}

CFStringRef
OMCActionUICopyAllRowsValue(CFStringRef inWindowUUID, CFStringRef inControlID, CFIndex inColumnIndex) noexcept
{
	if( (inWindowUUID == nullptr) || (inControlID == nullptr) )
		return nullptr;
	std::string uuid = ACFStringToUTF8(inWindowUUID);
	CFObj<CFPropertyListRef> rows( CreatePropertyListAndFree(actionUIGetElementRowsJSON(uuid.c_str(), ViewIDFromControlID(inControlID))) );
	CFIndex rowCount = ( (rows != nullptr) && (::CFGetTypeID(rows) == ::CFArrayGetTypeID()) ) ? ::CFArrayGetCount((CFArrayRef)rows.Get()) : 0;

	CFObj<CFMutableArrayRef> lines( ::CFArrayCreateMutable(kCFAllocatorDefault, rowCount, &kCFTypeArrayCallBacks) );
	for(CFIndex i = 0; i < rowCount; i++)
	{
		CFTypeRef row = ::CFArrayGetValueAtIndex((CFArrayRef)rows.Get(), i);
		if( (row == nullptr) || (::CFGetTypeID(row) != ::CFArrayGetTypeID()) )
			continue;
		CFArrayRef cells = (CFArrayRef)row;
		if(inColumnIndex == 0)
		{
			CFObj<CFStringRef> line( ::CFStringCreateByCombiningStrings(kCFAllocatorDefault, cells, CFSTR("\t")) );
			::CFArrayAppendValue(lines, (line != nullptr) ? (CFStringRef)line : CFSTR(""));
		}
		else
		{
			CFIndex cellIndex = inColumnIndex - 1;
			CFTypeRef cell = ( (cellIndex >= 0) && (cellIndex < ::CFArrayGetCount(cells)) ) ? ::CFArrayGetValueAtIndex(cells, cellIndex) : nullptr;
			bool isString = (cell != nullptr) && (::CFGetTypeID(cell) == ::CFStringGetTypeID());
			::CFArrayAppendValue(lines, isString ? cell : CFSTR(""));
		}
	}
	return ::CFStringCreateByCombiningStrings(kCFAllocatorDefault, lines, CFSTR("\n"));
}

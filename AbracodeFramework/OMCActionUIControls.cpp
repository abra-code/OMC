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

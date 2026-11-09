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

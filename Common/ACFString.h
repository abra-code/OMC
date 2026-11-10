//
//  ACFString.h
//
//  Small CFString helpers for portable C++.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <cstring>
#include <string>

// The string as UTF-8; empty for NULL, for an empty string, and for a string with no UTF-8 form
// (a lone surrogate). Stops at an embedded NUL. The body of CMUtils::CreateUTF8StringFromCFString,
// which now forwards here, so code outside the contextual menu utilities can use it.
inline std::string ACFStringToUTF8(CFStringRef inString)
{
	if(inString == NULL)
		return std::string();

	// Fast path: CF hands out its own UTF-8 bytes when it stores the string in a form it can
	// (NUL-terminated, so it stops at an embedded NUL too)
	const char *directBytes = ::CFStringGetCStringPtr(inString, kCFStringEncodingUTF8);
	if(directBytes != NULL)
		return std::string(directBytes);

	CFIndex uniCount = ::CFStringGetLength(inString);
	if(uniCount > 0)
	{
		CFIndex maxCount = ::CFStringGetMaximumSizeForEncoding(uniCount, kCFStringEncodingUTF8); //too big size
		std::string string((size_t)maxCount + 1, '\0');//+ 1 for null char
		bool isOK = ::CFStringGetCString(inString, &string[0], maxCount + 1, kCFStringEncodingUTF8);
		if(isOK)
		{
			string.resize(strnlen(&string[0], (size_t)maxCount));//shrink down to exact size
			return string;
		}
	}
	return std::string();
}

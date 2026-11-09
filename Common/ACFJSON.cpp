//
//  ACFJSON.cpp
//
//  See ACFJSON.h. The rules below reproduce NSJSONSerialization as measured on macOS;
//  OMCJSONFoundationParityTests compares both directions with it.
//

#include "ACFJSON.h"
#include "CFObj.h"
#include "yyjson.h"
#include <charconv>
#include <cmath>
#include <string>
#include <vector>

namespace
{

// NSJSONSerialization accepts a value nested in at most this many containers.
const size_t kMaxNestingDepth = 512;

// CF's own 128-bit integer type, which CFNumber uses internally for integers above INT64_MAX
// (CF's XML property list parser makes them). It is not in the public headers, but CFNumber
// accepts it on macOS and in swift-corelibs-foundation alike.
const CFNumberType kACFNumberSInt128Type = (CFNumberType)17;
struct ACFSInt128
{
	int64_t high;
	uint64_t low;
};

#pragma mark - Reading

// Adopts inError (+1) and hands it to the caller, or releases it when the caller asked for none.
void
SetError(CFStringRef *outError, CFStringRef inError)
{
	CFObj<CFStringRef> error(inError);
	if(outError != nullptr)
		*outError = error.Detach();
}

CFStringRef
CreateErrorString(const char *inMessage, size_t inPosition)
{
	return ::CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("JSON text is not valid at byte %lu: %s"),
										(unsigned long)inPosition, inMessage);
}

// The encoding of the JSON bytes, as NSJSONSerialization on macOS detects it: a byte order mark
// (looked for only in 4 bytes or more), else, in MORE than 4 bytes, the pattern of zero bytes
// RFC 4627 describes (4 bytes without a byte order mark are always read as UTF-8 there), else
// UTF-8. *outSkip is the length of the byte order mark.
CFStringEncoding
DetectEncoding(const UInt8 *inBytes, size_t inLength, size_t *outSkip)
{
	*outSkip = 0;
	if(inLength < 4)
		return kCFStringEncodingUTF8;

	if((inBytes[0] == 0xEF) && (inBytes[1] == 0xBB) && (inBytes[2] == 0xBF))
	{
		*outSkip = 3;
		return kCFStringEncodingUTF8;
	}
	if((inBytes[0] == 0x00) && (inBytes[1] == 0x00) && (inBytes[2] == 0xFE) && (inBytes[3] == 0xFF))
	{
		*outSkip = 4;
		return kCFStringEncodingUTF32BE;
	}
	// FF FE is always the UTF-16 little-endian mark there, even when 00 00 follows (the UTF-32
	// little-endian mark), so UTF-32 little-endian with a byte order mark does not parse
	if((inBytes[0] == 0xFF) && (inBytes[1] == 0xFE))
	{
		*outSkip = 2;
		return kCFStringEncodingUTF16LE;
	}
	if((inBytes[0] == 0xFE) && (inBytes[1] == 0xFF))
	{
		*outSkip = 2;
		return kCFStringEncodingUTF16BE;
	}

	if(inLength == 4)
		return kCFStringEncodingUTF8;
	if((inBytes[0] == 0) && (inBytes[1] == 0) && (inBytes[2] == 0))
		return kCFStringEncodingUTF32BE;
	if((inBytes[1] == 0) && (inBytes[2] == 0) && (inBytes[3] == 0))
		return kCFStringEncodingUTF32LE;
	if((inBytes[0] == 0) && (inBytes[2] == 0))
		return kCFStringEncodingUTF16BE;
	if((inBytes[1] == 0) && (inBytes[3] == 0))
		return kCFStringEncodingUTF16LE;
	return kCFStringEncodingUTF8;
}

// UTF-16 or UTF-32 text re-encoded as UTF-8 for the parser. False when it does not decode.
bool
ConvertToUTF8(const UInt8 *inBytes, size_t inLength, CFStringEncoding inEncoding, std::string &outUTF8)
{
	CFObj<CFStringRef> text( ::CFStringCreateWithBytes(kCFAllocatorDefault, inBytes, (CFIndex)inLength, inEncoding, false) );
	if(text == nullptr)
		return false;

	CFIndex length = ::CFStringGetLength(text);
	CFIndex usedBytes = 0;
	CFIndex converted = ::CFStringGetBytes(text, CFRangeMake(0, length), kCFStringEncodingUTF8, 0, false, nullptr, 0, &usedBytes);
	if(converted != length)
		return false;//a lone surrogate
	outUTF8.resize((size_t)usedBytes);
	if(usedBytes > 0)
		(void)::CFStringGetBytes(text, CFRangeMake(0, length), kCFStringEncodingUTF8, 0, false, (UInt8 *)&outUTF8[0], usedBytes, nullptr);
	return true;
}

CFNumberRef
CreateNumber(yyjson_val *inValue)
{
	if(yyjson_is_uint(inValue))
	{
		uint64_t value = yyjson_get_uint(inValue);
		if(value <= (uint64_t)INT64_MAX)
		{
			int64_t signedValue = (int64_t)value;
			return ::CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &signedValue);
		}
		// above INT64_MAX: Foundation kept the exact unsigned value, and so does CF's 128-bit type
		ACFSInt128 wide = { 0, value };
		return ::CFNumberCreate(kCFAllocatorDefault, kACFNumberSInt128Type, &wide);
	}
	if(yyjson_is_sint(inValue))
	{
		int64_t value = yyjson_get_sint(inValue);
		return ::CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &value);
	}
	double value = yyjson_get_real(inValue);
	return ::CFNumberCreate(kCFAllocatorDefault, kCFNumberFloat64Type, &value);
}

// The CF object for a parsed value nested in inDepth containers; NULL when nested too deeply.
CFTypeRef
CreateCFValue(yyjson_val *inValue, size_t inDepth, bool inMutableContainers)
{
	if(inDepth > kMaxNestingDepth)
		return nullptr;

	switch(yyjson_get_type(inValue))
	{
		case YYJSON_TYPE_NULL:
			return ::CFRetain(kCFNull);

		case YYJSON_TYPE_BOOL:
			return ::CFRetain(yyjson_get_bool(inValue) ? kCFBooleanTrue : kCFBooleanFalse);

		case YYJSON_TYPE_NUM:
			return CreateNumber(inValue);

		case YYJSON_TYPE_STR:
			return ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)yyjson_get_str(inValue),
											(CFIndex)yyjson_get_len(inValue), kCFStringEncodingUTF8, false);

		case YYJSON_TYPE_ARR:
		{
			CFObj<CFMutableArrayRef> array( ::CFArrayCreateMutable(kCFAllocatorDefault, (CFIndex)yyjson_arr_size(inValue), &kCFTypeArrayCallBacks) );
			yyjson_arr_iter iter = yyjson_arr_iter_with(inValue);
			yyjson_val *element = nullptr;
			while((element = yyjson_arr_iter_next(&iter)) != nullptr)
			{
				CFObj<CFTypeRef> elementValue( CreateCFValue(element, inDepth + 1, inMutableContainers) );
				if(elementValue == nullptr)
					return nullptr;
				::CFArrayAppendValue(array, elementValue);
			}
			if(inMutableContainers)
				return array.Detach();
			return ::CFArrayCreateCopy(kCFAllocatorDefault, array);
		}

		case YYJSON_TYPE_OBJ:
		{
			CFObj<CFMutableDictionaryRef> dict( ::CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
												&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks) );
			yyjson_obj_iter iter = yyjson_obj_iter_with(inValue);
			yyjson_val *key = nullptr;
			while((key = yyjson_obj_iter_next(&iter)) != nullptr)
			{
				yyjson_val *member = yyjson_obj_iter_get_val(key);
				CFObj<CFTypeRef> keyString( CreateCFValue(key, inDepth + 1, inMutableContainers) );
				CFObj<CFTypeRef> memberValue( CreateCFValue(member, inDepth + 1, inMutableContainers) );
				if((keyString == nullptr) || (memberValue == nullptr))
					return nullptr;
				// a repeated key: NSJSONSerialization keeps the first value in an immutable result
				// and the last in a mutable one
				if(inMutableContainers)
					::CFDictionarySetValue(dict, keyString, memberValue);
				else
					::CFDictionaryAddValue(dict, keyString, memberValue);
			}
			if(inMutableContainers)
				return dict.Detach();
			return ::CFDictionaryCreateCopy(kCFAllocatorDefault, dict);
		}

		default:
			return nullptr;
	}
}

#pragma mark - Writing

void
AppendIndent(std::string &ioText, size_t inLevel)
{
	ioText.append(inLevel * 2, ' ');
}

void
AppendUTF8(std::string &ioText, UTF32Char inChar)
{
	if(inChar < 0x80)
	{
		ioText.push_back((char)inChar);
	}
	else if(inChar < 0x800)
	{
		ioText.push_back((char)(0xC0 | (inChar >> 6)));
		ioText.push_back((char)(0x80 | (inChar & 0x3F)));
	}
	else if(inChar < 0x10000)
	{
		ioText.push_back((char)(0xE0 | (inChar >> 12)));
		ioText.push_back((char)(0x80 | ((inChar >> 6) & 0x3F)));
		ioText.push_back((char)(0x80 | (inChar & 0x3F)));
	}
	else
	{
		ioText.push_back((char)(0xF0 | (inChar >> 18)));
		ioText.push_back((char)(0x80 | ((inChar >> 12) & 0x3F)));
		ioText.push_back((char)(0x80 | ((inChar >> 6) & 0x3F)));
		ioText.push_back((char)(0x80 | (inChar & 0x3F)));
	}
}

// A quoted string: " \ / and \b \f \n \r \t escaped by name, the other control characters
// as \u00xx (lower-case hex), everything else as UTF-8.
ACFJSONWriteStatus
AppendString(std::string &ioText, CFStringRef inString)
{
	static const char kHexDigits[] = "0123456789abcdef";
	CFIndex length = ::CFStringGetLength(inString);
	std::vector<UniChar> chars((size_t)length);
	if(length > 0)
		::CFStringGetCharacters(inString, CFRangeMake(0, length), chars.data());

	ioText.push_back('"');
	for(size_t i = 0; i < chars.size(); i++)
	{
		UniChar oneChar = chars[i];
		switch(oneChar)
		{
			case '"':	ioText.append("\\\""); continue;
			case '\\':	ioText.append("\\\\"); continue;
			case '/':	ioText.append("\\/"); continue;
			case '\b':	ioText.append("\\b"); continue;
			case '\f':	ioText.append("\\f"); continue;
			case '\n':	ioText.append("\\n"); continue;
			case '\r':	ioText.append("\\r"); continue;
			case '\t':	ioText.append("\\t"); continue;
			default:	break;
		}
		if(oneChar < 0x20)
		{
			ioText.append("\\u00");
			ioText.push_back(kHexDigits[oneChar >> 4]);
			ioText.push_back(kHexDigits[oneChar & 0x0F]);
			continue;
		}
		if(::CFStringIsSurrogateHighCharacter(oneChar))
		{
			if((i + 1 >= chars.size()) || !::CFStringIsSurrogateLowCharacter(chars[i + 1]))
				return kACFJSONWriteInvalidString;
			AppendUTF8(ioText, ::CFStringGetLongCharacterForSurrogatePair(oneChar, chars[i + 1]));
			i++;
			continue;
		}
		if(::CFStringIsSurrogateLowCharacter(oneChar))
			return kACFJSONWriteInvalidString;
		AppendUTF8(ioText, oneChar);
	}
	ioText.push_back('"');
	return kACFJSONWriteOK;
}

// The decimal digits of a signed 128-bit value.
void
AppendInt128(std::string &ioText, __int128 inValue)
{
	bool negative = (inValue < 0);
	unsigned __int128 magnitude = negative ? (unsigned __int128)(-(inValue + 1)) + 1 : (unsigned __int128)inValue;
	char digits[48];
	size_t count = 0;
	do
	{
		digits[count++] = (char)('0' + (int)(magnitude % 10));
		magnitude /= 10;
	}
	while(magnitude != 0);
	if(negative)
		ioText.push_back('-');
	while(count > 0)
		ioText.push_back(digits[--count]);
}

ACFJSONWriteStatus
AppendNumber(std::string &ioText, CFNumberRef inNumber)
{
	if(::CFNumberIsFloatType(inNumber))
	{
		double value = 0.0;
		(void)::CFNumberGetValue(inNumber, kCFNumberFloat64Type, &value);
		if(!std::isfinite(value))
			return kACFJSONWriteUnrepresentable;
		// as printf's "%.17g" in the C locale, which is what NSJSONSerialization writes
		char buffer[64];
		std::to_chars_result result = std::to_chars(buffer, buffer + sizeof(buffer), value, std::chars_format::general, 17);
		ioText.append(buffer, (size_t)(result.ptr - buffer));
		return kACFJSONWriteOK;
	}

	// Integers go through CF's 128-bit form: it holds every integer CFNumber exactly, including
	// unsigned 64-bit values above INT64_MAX, which CFNumberGetValue to SInt64 would reinterpret
	// as negative instead of failing.
	ACFSInt128 wide = { 0, 0 };
	if(!::CFNumberGetValue(inNumber, kACFNumberSInt128Type, &wide))
		return kACFJSONWriteUnrepresentable;
	AppendInt128(ioText, (__int128)(((unsigned __int128)(uint64_t)wide.high << 64) | wide.low));
	return kACFJSONWriteOK;
}

ACFJSONWriteStatus AppendValue(std::string &ioText, CFTypeRef inValue, size_t inLevel);

// CFArraySortValues comparator for AppendDictionary: each value points at a CFString key,
// inContext is the locale.
CFComparisonResult
CompareKeyEntries(const void *inEntryA, const void *inEntryB, void *inContext)
{
	CFStringRef keyA = *(const CFStringRef *)inEntryA;
	CFStringRef keyB = *(const CFStringRef *)inEntryB;
	return ::CFStringCompareWithOptionsAndLocale(keyA, keyB, CFRangeMake(0, ::CFStringGetLength(keyA)),
												kCFCompareNumerically | kCFCompareCaseInsensitive | kCFCompareForcedOrdering,
												(CFLocaleRef)inContext);
}

ACFJSONWriteStatus
AppendArray(std::string &ioText, CFArrayRef inArray, size_t inLevel)
{
	CFIndex count = ::CFArrayGetCount(inArray);
	ioText.append("[\n");
	if(count == 0)
	{
		ioText.push_back('\n');
	}
	for(CFIndex i = 0; i < count; i++)
	{
		AppendIndent(ioText, inLevel + 1);
		ACFJSONWriteStatus status = AppendValue(ioText, ::CFArrayGetValueAtIndex(inArray, i), inLevel + 1);
		if(status != kACFJSONWriteOK)
			return status;
		ioText.append((i + 1 < count) ? ",\n" : "\n");
	}
	AppendIndent(ioText, inLevel);
	ioText.push_back(']');
	return kACFJSONWriteOK;
}

ACFJSONWriteStatus
AppendDictionary(std::string &ioText, CFDictionaryRef inDict, size_t inLevel)
{
	CFIndex count = ::CFDictionaryGetCount(inDict);
	std::vector<const void *> keys((size_t)count);
	std::vector<const void *> values((size_t)count);
	if(count > 0)
		::CFDictionaryGetKeysAndValues(inDict, keys.data(), values.data());

	for(const void *key : keys)
	{
		if((key == nullptr) || (::CFGetTypeID((CFTypeRef)key) != ::CFStringGetTypeID()))
			return kACFJSONWriteUnrepresentable;
	}

	// sorted as NSJSONWritingSortedKeys does: numeric, case-insensitive, forced ordering, in the
	// system locale (so "9" comes before "10", and punctuation before digits, by ICU collation).
	// The sort is CF's own, as Foundation's: this comparison is not transitive for keys that mix
	// digits of different scripts (ASCII, fullwidth, Arabic-Indic), so only the same algorithm gives
	// the same order, and std::sort requires a strict weak ordering. The array holds pointers into
	// keys (not retained), so each sorted entry gives back its index.
	std::vector<size_t> order((size_t)count);
	if(count > 1)
	{
		CFObj<CFMutableArrayRef> sorted( ::CFArrayCreateMutable(kCFAllocatorDefault, count, nullptr) );
		for(const void *&key : keys)
			::CFArrayAppendValue(sorted, &key);
		::CFArraySortValues(sorted, CFRangeMake(0, count), CompareKeyEntries, (void *)::CFLocaleGetSystem());
		for(size_t i = 0; i < order.size(); i++)
			order[i] = (size_t)((const void * const *)::CFArrayGetValueAtIndex(sorted, (CFIndex)i) - keys.data());
	}
	else if(count == 1)
	{
		order[0] = 0;
	}

	ioText.append("{\n");
	if(count == 0)
	{
		ioText.push_back('\n');
	}
	for(size_t i = 0; i < order.size(); i++)
	{
		AppendIndent(ioText, inLevel + 1);
		ACFJSONWriteStatus status = AppendString(ioText, (CFStringRef)keys[order[i]]);
		if(status != kACFJSONWriteOK)
			return status;
		ioText.append(" : ");
		status = AppendValue(ioText, (CFTypeRef)values[order[i]], inLevel + 1);
		if(status != kACFJSONWriteOK)
			return status;
		ioText.append((i + 1 < order.size()) ? ",\n" : "\n");
	}
	AppendIndent(ioText, inLevel);
	ioText.push_back('}');
	return kACFJSONWriteOK;
}

ACFJSONWriteStatus
AppendValue(std::string &ioText, CFTypeRef inValue, size_t inLevel)
{
	if(inValue == nullptr)
		return kACFJSONWriteUnrepresentable;

	CFTypeID typeID = ::CFGetTypeID(inValue);
	if(typeID == ::CFStringGetTypeID())
		return AppendString(ioText, (CFStringRef)inValue);
	if(typeID == ::CFBooleanGetTypeID())
	{
		ioText.append(::CFBooleanGetValue((CFBooleanRef)inValue) ? "true" : "false");
		return kACFJSONWriteOK;
	}
	if(typeID == ::CFNumberGetTypeID())
		return AppendNumber(ioText, (CFNumberRef)inValue);
	if(typeID == ::CFNullGetTypeID())
	{
		ioText.append("null");
		return kACFJSONWriteOK;
	}
	if(typeID == ::CFArrayGetTypeID())
		return AppendArray(ioText, (CFArrayRef)inValue, inLevel);
	if(typeID == ::CFDictionaryGetTypeID())
		return AppendDictionary(ioText, (CFDictionaryRef)inValue, inLevel);
	return kACFJSONWriteUnrepresentable;
}

} // namespace

CFPropertyListRef
ACFJSONCreatePropertyList(CFDataRef inData, CFPropertyListMutabilityOptions inMutability, CFStringRef *outError)
{
	if(outError != nullptr)
		*outError = nullptr;
	if(inData == nullptr)
	{
		SetError(outError, ::CFStringCreateCopy(kCFAllocatorDefault, CFSTR("no JSON data")));
		return nullptr;
	}

	const UInt8 *bytes = ::CFDataGetBytePtr(inData);
	size_t length = (size_t)::CFDataGetLength(inData);
	size_t skip = 0;
	CFStringEncoding encoding = (length > 0) ? DetectEncoding(bytes, length, &skip) : kCFStringEncodingUTF8;

	std::string converted;
	const char *text = (const char *)bytes + skip;
	size_t textLength = length - skip;
	if(encoding != kCFStringEncodingUTF8)
	{
		if(!ConvertToUTF8(bytes + skip, length - skip, encoding, converted))
		{
			SetError(outError, ::CFStringCreateCopy(kCFAllocatorDefault, CFSTR("JSON text is not valid UTF-16 or UTF-32")));
			return nullptr;
		}
		text = converted.data();
		textLength = converted.size();
	}

	yyjson_read_err readError;
	yyjson_doc *doc = yyjson_read_opts((char *)text, textLength, YYJSON_READ_ALLOW_TRAILING_COMMAS, nullptr, &readError);
	if(doc == nullptr)
	{
		SetError(outError, CreateErrorString(readError.msg, readError.pos));
		return nullptr;
	}

	bool mutableContainers = (inMutability != kCFPropertyListImmutable);
	CFTypeRef result = CreateCFValue(yyjson_doc_get_root(doc), 0, mutableContainers);
	yyjson_doc_free(doc);
	if(result == nullptr)
		SetError(outError, ::CFStringCreateCopy(kCFAllocatorDefault, CFSTR("JSON text is nested in more than 512 arrays and objects")));
	return result;
}

CFDataRef
ACFJSONCreateData(CFPropertyListRef inValue, ACFJSONWriteStatus *outStatus)
{
	std::string text;
	ACFJSONWriteStatus status = AppendValue(text, inValue, 0);
	if(outStatus != nullptr)
		*outStatus = status;
	if(status != kACFJSONWriteOK)
		return nullptr;
	return ::CFDataCreate(kCFAllocatorDefault, (const UInt8 *)text.data(), (CFIndex)text.size());
}

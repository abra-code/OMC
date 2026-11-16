//
//  OMCURLParse.cpp
//  Abracode
//
//  See OMCURLParse.h. Replaces OMCCommandExecutor.mm's use of NSURLComponents, as part of the
//  Phase 5 app shell (Linux has no NSURLComponents with Apple's rules).
//

#include "OMCURLParse.h"
#include "CFObj.h"
#include <cstdint>
#include <string>

namespace
{

bool IsAlpha(unsigned char c) { return ((c >= 'a') && (c <= 'z')) || ((c >= 'A') && (c <= 'Z')); }
bool IsDigit(unsigned char c) { return (c >= '0') && (c <= '9'); }
bool IsHexDigit(unsigned char c) { return IsDigit(c) || ((c >= 'a') && (c <= 'f')) || ((c >= 'A') && (c <= 'F')); }

int HexValue(unsigned char c)
{
	if(IsDigit(c))
		return c - '0';
	if((c >= 'a') && (c <= 'f'))
		return c - 'a' + 10;
	return c - 'A' + 10;
}

// ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
bool IsScheme(const std::string &inText)
{
	if( inText.empty() || !IsAlpha((unsigned char)inText[0]) )
		return false;
	for(unsigned char c : inText)
	{
		if( !IsAlpha(c) && !IsDigit(c) && (c != '+') && (c != '-') && (c != '.') )
			return false;
	}
	return true;
}

// A host name: unreserved characters, sub-delimiters, "%" escapes, and non-ASCII characters
bool IsHostName(const std::string &inText)
{
	for(size_t i = 0; i < inText.size(); i++)
	{
		unsigned char c = (unsigned char)inText[i];
		if(c >= 0x80)
			continue;
		if( IsAlpha(c) || IsDigit(c) )
			continue;
		switch(c)
		{
			case '-': case '.': case '_': case '~':											// unreserved
			case '!': case '$': case '&': case '\'': case '(': case ')':
			case '*': case '+': case ',': case ';': case '=':									// sub-delims
				continue;
			case '%':
				if( (i + 2 < inText.size()) && IsHexDigit((unsigned char)inText[i + 1]) && IsHexDigit((unsigned char)inText[i + 2]) )
				{
					i += 2;
					continue;
				}
				return false;
			default:
				return false;
		}
	}
	return true;
}

bool IsAllDigits(const std::string &inText)
{
	for(unsigned char c : inText)
	{
		if(!IsDigit(c))
			return false;
	}
	return true;
}

// The text with each "%" and two hex digits decoded, any other "%" kept, as UTF-8 text; NULL
// when the bytes are not UTF-8 (the caller releases it). inKeepEscapedNul keeps "%00" as it is,
// as NSURLComponents does in a host (not in a query)
CFStringRef CreateDecodedString(const std::string &inText, bool inKeepEscapedNul)
{
	std::string bytes;
	bytes.reserve(inText.size());
	for(size_t i = 0; i < inText.size(); i++)
	{
		unsigned char c = (unsigned char)inText[i];
		if( (c == '%') && (i + 2 < inText.size()) && IsHexDigit((unsigned char)inText[i + 1]) && IsHexDigit((unsigned char)inText[i + 2]) )
		{
			char decoded = (char)((HexValue((unsigned char)inText[i + 1]) << 4) | HexValue((unsigned char)inText[i + 2]));
			if( (decoded == 0) && inKeepEscapedNul )
				bytes.append(inText, i, 3);
			else
				bytes.push_back(decoded);
			i += 2;
		}
		else
		{
			bytes.push_back((char)c);
		}
	}
	return ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)bytes.data(), (CFIndex)bytes.size(), kCFStringEncodingUTF8, false);
}

// Whether the query holds a character a URL's query may not hold as it is: NSURLComponents then
// percent-encodes the whole query as text, every "%" included, so no "%" is an escape in it
bool QueryNeedsEncoding(const std::string &inQuery)
{
	for(size_t i = 0; i < inQuery.size(); i++)
	{
		unsigned char c = (unsigned char)inQuery[i];
		if( (c <= 0x20) || (c >= 0x7F) )
			return true;
		switch(c)
		{
			case '"': case '<': case '>': case '[': case ']': case '\\': case '^': case '`': case '{': case '|': case '}':
				return true;
			case '%':
				if( !((i + 2 < inQuery.size()) && IsHexDigit((unsigned char)inQuery[i + 1]) && IsHexDigit((unsigned char)inQuery[i + 2])) )
					return true;
				i += 2;
				break;
			default:
				break;
		}
	}
	return false;
}

// A name or value as text: decoded, unless the query is text as it is; when it does not decode
// to UTF-8, an empty name, or kCFNull for a value
CFTypeRef CreateQueryPart(const std::string &inText, bool inLiteral, bool inIsName)
{
	CFStringRef part = inLiteral
						? ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)inText.data(), (CFIndex)inText.size(), kCFStringEncodingUTF8, false)
						: CreateDecodedString(inText, false);
	if(part != nullptr)
		return part;
	return inIsName ? ::CFRetain(CFSTR("")) : ::CFRetain(kCFNull);
}

// The whole string as UTF-8: an embedded NUL is kept (ACFStringToUTF8 stops at one, and
// NSURLComponents parses past it), and a lone surrogate becomes U+FFFD, as NSURLComponents takes
// it (ACFStringToUTF8 gives an empty string for one)
std::string URLToUTF8(CFStringRef inURL)
{
	CFIndex length = ::CFStringGetLength(inURL);
	std::string text;
	text.reserve((size_t)length);
	CFStringInlineBuffer buffer;
	::CFStringInitInlineBuffer(inURL, &buffer, ::CFRangeMake(0, length));
	for(CFIndex i = 0; i < length; i++)
	{
		uint32_t codePoint = ::CFStringGetCharacterFromInlineBuffer(&buffer, i);
		if( (codePoint >= 0xD800) && (codePoint <= 0xDBFF) && (i + 1 < length) )
		{
			UniChar low = ::CFStringGetCharacterFromInlineBuffer(&buffer, i + 1);
			if( (low >= 0xDC00) && (low <= 0xDFFF) )
			{
				codePoint = 0x10000 + ((codePoint - 0xD800) << 10) + (low - 0xDC00);
				i++;
			}
		}
		if( (codePoint >= 0xD800) && (codePoint <= 0xDFFF) )
			codePoint = 0xFFFD;

		if(codePoint < 0x80)
		{
			text.push_back((char)codePoint);
		}
		else if(codePoint < 0x800)
		{
			text.push_back((char)(0xC0 | (codePoint >> 6)));
			text.push_back((char)(0x80 | (codePoint & 0x3F)));
		}
		else if(codePoint < 0x10000)
		{
			text.push_back((char)(0xE0 | (codePoint >> 12)));
			text.push_back((char)(0x80 | ((codePoint >> 6) & 0x3F)));
			text.push_back((char)(0x80 | (codePoint & 0x3F)));
		}
		else
		{
			text.push_back((char)(0xF0 | (codePoint >> 18)));
			text.push_back((char)(0x80 | ((codePoint >> 12) & 0x3F)));
			text.push_back((char)(0x80 | ((codePoint >> 6) & 0x3F)));
			text.push_back((char)(0x80 | (codePoint & 0x3F)));
		}
	}
	return text;
}

} // namespace

bool
OMCParseURL(CFStringRef inURL, CFObj<CFStringRef> &outHost, CFObj<CFArrayRef> &outQueryItems) noexcept
{
	outHost.Release();
	outQueryItems.Release();
	if(inURL == nullptr)
		return false;

	std::string text = URLToUTF8(inURL);

	// The fragment is no part of the rest; the query is what follows the first "?"
	std::string beforeFragment = text.substr(0, text.find('#'));
	size_t questionMark = beforeFragment.find('?');
	bool hasQuery = (questionMark != std::string::npos);
	std::string reference = beforeFragment.substr(0, questionMark);
	std::string query = hasQuery ? beforeFragment.substr(questionMark + 1) : std::string();

	// The scheme: up to the first ":" when that comes before any "/". What precedes it must be a
	// scheme, unless nothing does ("://host" has no scheme, and no host either)
	std::string rest = reference;
	size_t colon = reference.find(':');
	size_t slash = reference.find('/');
	if( (colon != std::string::npos) && (colon > 0) && ((slash == std::string::npos) || (colon < slash)) )
	{
		if( !IsScheme(reference.substr(0, colon)) )
			return false;
		rest = reference.substr(colon + 1);
	}

	// The authority, after "//": [user "@"] host [":" port], the user up to the last "@"
	CFObj<CFStringRef> host;
	if(rest.compare(0, 2, "//") == 0)
	{
		size_t authorityEnd = rest.find('/', 2);
		std::string authority = rest.substr(2, (authorityEnd == std::string::npos) ? std::string::npos : authorityEnd - 2);
		size_t at = authority.rfind('@');
		std::string hostAndPort = (at == std::string::npos) ? authority : authority.substr(at + 1);

		std::string hostText;
		std::string port;
		if( !hostAndPort.empty() && (hostAndPort[0] == '[') )
		{
			// A bracketed host (an IP address), kept with its brackets; only a port may follow it
			size_t closingBracket = hostAndPort.find(']');
			if(closingBracket == std::string::npos)
				return false;
			hostText = hostAndPort.substr(0, closingBracket + 1);
			std::string afterHost = hostAndPort.substr(closingBracket + 1);
			if(!afterHost.empty())
			{
				if(afterHost[0] != ':')
					return false;
				port = afterHost.substr(1);
			}
		}
		else
		{
			size_t portColon = hostAndPort.find(':');
			hostText = hostAndPort.substr(0, portColon);
			if(portColon != std::string::npos)
				port = hostAndPort.substr(portColon + 1);
			if( !IsHostName(hostText) )
				return false;
		}
		if( !IsAllDigits(port) )
			return false;
		// A bracketed host is kept as it is, as NSURLComponents keeps it
		if( !hostText.empty() && (hostText[0] == '[') )
			host.Adopt( ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)hostText.data(), (CFIndex)hostText.size(), kCFStringEncodingUTF8, false) );
		else
			host.Adopt( CreateDecodedString(hostText, true) );
	}

	CFObj<CFMutableArrayRef> queryItems( ::CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks) );
	if( hasQuery && !query.empty() )
	{
		bool literal = QueryNeedsEncoding(query);
		size_t start = 0;
		while(true)
		{
			size_t ampersand = query.find('&', start);
			std::string item = query.substr(start, (ampersand == std::string::npos) ? std::string::npos : ampersand - start);
			size_t equals = item.find('=');
			CFObj<CFTypeRef> name( CreateQueryPart(item.substr(0, equals), literal, true) );
			CFObj<CFTypeRef> value( (equals != std::string::npos) ? CreateQueryPart(item.substr(equals + 1), literal, false) : ::CFRetain(kCFNull) );
			CFTypeRef pair[2] = { name.Get(), value.Get() };
			CFObj<CFArrayRef> oneItem( ::CFArrayCreate(kCFAllocatorDefault, pair, 2, &kCFTypeArrayCallBacks) );
			::CFArrayAppendValue(queryItems, oneItem);
			if(ampersand == std::string::npos)
				break;
			start = ampersand + 1;
		}
	}

	outHost.Swap(host);
	outQueryItems.Adopt(queryItems.Detach());
	return true;
}

//
//  ACFPath.cpp
//
//  See ACFPath.h. The rules were measured against NSString on macOS (commit notes "OMCStrings to
//  C++" and "ACFPropertyList to C++"); they moved here from OMCStrings.cpp unchanged.
//

#include "ACFPath.h"
#include <vector>

namespace
{

std::vector<UniChar>
CopyCharacters(CFStringRef inStr)
{
	CFIndex length = ::CFStringGetLength(inStr);
	std::vector<UniChar> chars((size_t)length);
	if(length > 0)
		::CFStringGetCharacters(inStr, CFRangeMake(0, length), chars.data());
	return chars;
}

CFStringRef
CreateStringFromCharacters(const std::vector<UniChar> &inChars, size_t inStart, size_t inEnd)
{
	if(inEnd <= inStart)
		return ::CFStringCreateWithCharacters(kCFAllocatorDefault, nullptr, 0);
	return ::CFStringCreateWithCharacters(kCFAllocatorDefault, inChars.data() + inStart, (CFIndex)(inEnd - inStart));
}

std::vector<UniChar>
StandardizeSlashes(const std::vector<UniChar> &inChars)
{
	std::vector<UniChar> out;
	out.reserve(inChars.size());
	for(UniChar oneChar : inChars)
	{
		if((oneChar == '/') && !out.empty() && (out.back() == '/'))
			continue;
		out.push_back(oneChar);
	}
	if((out.size() > 1) && (out.back() == '/'))
		out.pop_back();
	return out;
}

// Where the extension of the last path component is, by NSString's pathExtension rules: trailing
// slashes are ignored, and there is none for a name without a dot, a name ending with a dot, a
// name whose part before the last dot is empty, "." or ".." (".bashrc", "..x", "...x"), or an
// extension containing a space or a bidirectional formatting character (U+061C, U+200E, U+200F,
// U+202A to U+202E, U+2066 to U+2069). On true, the extension is [*outDot + 1, *outEnd).
bool
FindExtension(const std::vector<UniChar> &chars, size_t *outDot, size_t *outEnd)
{
	size_t end = chars.size();
	while((end > 0) && (chars[end - 1] == '/'))
		end--;

	size_t start = end;
	while((start > 0) && (chars[start - 1] != '/'))
		start--;

	size_t dot = end;
	for(size_t i = end; i > start; i--)
	{
		if(chars[i - 1] == '.')
		{
			dot = i - 1;
			break;
		}
	}

	if(!((dot < end) && (dot + 1 < end)))
		return false;

	// the name before the extension may not be empty (".bashrc"), "." ("..x") or ".." ("...x");
	// a longer run of dots is an ordinary name ("....x" has the extension "x")
	size_t stemLength = dot - start;
	bool stemIsDotName = (stemLength == 0) ||
						((stemLength == 1) && (chars[start] == '.')) ||
						((stemLength == 2) && (chars[start] == '.') && (chars[start + 1] == '.'));
	if(stemIsDotName)
		return false;

	for(size_t i = dot + 1; i < end; i++)
	{
		UniChar oneChar = chars[i];
		bool isInvalid = (oneChar == ' ') || (oneChar == 0x061C) || (oneChar == 0x200E) || (oneChar == 0x200F) ||
						((oneChar >= 0x202A) && (oneChar <= 0x202E)) || ((oneChar >= 0x2066) && (oneChar <= 0x2069));
		if(isInvalid)
			return false;
	}

	*outDot = dot;
	*outEnd = end;
	return true;
}

} // namespace

CFStringRef
ACFPathCreateWithStandardSlashes(CFStringRef inPath)
{
	if(inPath == nullptr)
		return nullptr;
	std::vector<UniChar> standard = StandardizeSlashes(CopyCharacters(inPath));
	return CreateStringFromCharacters(standard, 0, standard.size());
}

CFStringRef
ACFPathCopyExtension(CFStringRef inPath)
{
	if(inPath == nullptr)
		return nullptr;
	std::vector<UniChar> chars = CopyCharacters(inPath);
	size_t dot = 0;
	size_t end = 0;
	if(!FindExtension(chars, &dot, &end))
		return ::CFStringCreateWithCharacters(kCFAllocatorDefault, nullptr, 0);
	return CreateStringFromCharacters(chars, dot + 1, end);
}

CFStringRef
ACFPathCreateDeletingExtension(CFStringRef inPath)
{
	if(inPath == nullptr)
		return nullptr;
	std::vector<UniChar> standard = StandardizeSlashes(CopyCharacters(inPath));
	size_t dot = 0;
	size_t end = 0;
	if(FindExtension(standard, &dot, &end))
		standard.erase(standard.begin() + (std::ptrdiff_t)dot, standard.begin() + (std::ptrdiff_t)end);
	return CreateStringFromCharacters(standard, 0, standard.size());
}

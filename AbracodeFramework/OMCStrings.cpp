#include "OMCStrings.h"
#include "OMCConstants.h"
#include "CFObj.h"
#include "ACFType.h"
#include "ACFPath.h"
#include <pwd.h>
#include <unistd.h>
#include <errno.h>
#include <string>
#include <vector>

// The path, case and escaping functions below used to call NSString. They are plain CF and POSIX
// now, so they build on Linux, and they reproduce what Foundation returned on macOS (checked
// against Foundation for every Unicode scalar and for all short strings over the characters that
// matter: see the commit note "OMCStrings to C++").

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

// Home folder from the password database, as NSString's tilde expansion does: $HOME is not consulted.
// An empty name means the current user. Returns NULL for an unknown user. Foundation's quirks are
// kept: a name is cut at an embedded NUL ("~root\0x" is root, "~\0" is unknown), and a name that
// has no UTF-8 form (a lone surrogate: "~root\uD800") means the current user.
CFStringRef
CreateHomeDirectoryForUser(CFStringRef inUserName)
{
	bool isCurrentUser = (inUserName == nullptr) || (::CFStringGetLength(inUserName) == 0);
	std::string userName;
	if(!isCurrentUser)
	{
		CFIndex maxSize = ::CFStringGetMaximumSizeForEncoding(::CFStringGetLength(inUserName), kCFStringEncodingUTF8) + 1;
		std::vector<char> nameBuf((size_t)maxSize);
		if(::CFStringGetCString(inUserName, nameBuf.data(), maxSize, kCFStringEncodingUTF8))
			userName = nameBuf.data();
		else
			isCurrentUser = true;
	}

	long bufSize = ::sysconf(_SC_GETPW_R_SIZE_MAX);
	if(bufSize <= 0)
		bufSize = 16384;

	while(true)
	{
		std::vector<char> buf((size_t)bufSize);
		struct passwd pwd;
		struct passwd *found = nullptr;
		int err = isCurrentUser
					? ::getpwuid_r(::getuid(), &pwd, buf.data(), buf.size(), &found)
					: ::getpwnam_r(userName.c_str(), &pwd, buf.data(), buf.size(), &found);
		if((err == ERANGE) && (bufSize < 1024 * 1024))
		{
			bufSize *= 4;
			continue;
		}
		if((err != 0) || (found == nullptr) || (found->pw_dir == nullptr))
			return nullptr;
		return ::CFStringCreateWithFileSystemRepresentation(kCFAllocatorDefault, found->pw_dir);
	}
}

bool
IsASCIIAlphanumeric(UTF32Char inChar)
{
	return ((inChar >= 'a') && (inChar <= 'z')) || ((inChar >= 'A') && (inChar <= 'Z')) || ((inChar >= '0') && (inChar <= '9'));
}

// The characters of NSCharacterSet's URLQueryAllowedCharacterSet; it has no others (none above ASCII).
bool
IsURLQueryAllowed(UTF32Char inChar)
{
	if(IsASCIIAlphanumeric(inChar))
		return true;
	static const char kOtherAllowed[] = "!$&'()*+,-./:;=?@_~";
	for(const char *allowed = kOtherAllowed; *allowed != 0; allowed++)
	{
		if((UTF32Char)*allowed == inChar)
			return true;
	}
	return false;
}

void
AppendUTF8(std::string &ioOut, UTF32Char inChar)
{
	if(inChar < 0x80)
	{
		ioOut.push_back((char)inChar);
	}
	else if(inChar < 0x800)
	{
		ioOut.push_back((char)(0xC0 | (inChar >> 6)));
		ioOut.push_back((char)(0x80 | (inChar & 0x3F)));
	}
	else if(inChar < 0x10000)
	{
		ioOut.push_back((char)(0xE0 | (inChar >> 12)));
		ioOut.push_back((char)(0x80 | ((inChar >> 6) & 0x3F)));
		ioOut.push_back((char)(0x80 | (inChar & 0x3F)));
	}
	else
	{
		ioOut.push_back((char)(0xF0 | (inChar >> 18)));
		ioOut.push_back((char)(0x80 | ((inChar >> 12) & 0x3F)));
		ioOut.push_back((char)(0x80 | ((inChar >> 6) & 0x3F)));
		ioOut.push_back((char)(0x80 | (inChar & 0x3F)));
	}
}

} // namespace

// "~" and "~user" at the start become that user's home folder; an unknown user leaves the tilde
// part as it is. Every result has its slashes standardized as NSString did
// (ACFPathCreateWithStandardSlashes).
CFStringRef CreatePathByExpandingTilde(CFStringRef inPath)
{
	if(inPath == nullptr)
		return nullptr;

	std::vector<UniChar> chars = CopyCharacters(inPath);
	if(chars.empty() || (chars[0] != '~'))
		return ACFPathCreateWithStandardSlashes(inPath);

	size_t firstSlash = 1;
	while((firstSlash < chars.size()) && (chars[firstSlash] != '/'))
		firstSlash++;

	CFObj<CFStringRef> userName( CreateStringFromCharacters(chars, 1, firstSlash) );
	CFObj<CFStringRef> homeDir( CreateHomeDirectoryForUser(userName) );
	if(homeDir == nullptr)
		return ACFPathCreateWithStandardSlashes(inPath);

	std::vector<UniChar> expanded = CopyCharacters(homeDir);
	expanded.insert(expanded.end(), chars.begin() + (std::ptrdiff_t)firstSlash, chars.end());
	CFObj<CFStringRef> expandedPath( CreateStringFromCharacters(expanded, 0, expanded.size()) );
	return ACFPathCreateWithStandardSlashes(expandedPath);
}

// The extension of the last path component, as NSString's pathExtension (rules in ACFPath.cpp).
CFStringRef CopyFilenameExtension(CFStringRef inFilePath)
{
	return ACFPathCopyExtension(inFilePath);
}

// Not localized, as NSString's lowercaseString.
CFStringRef CreateLowercaseString(CFStringRef inStr)
{
	if(inStr == nullptr)
		return nullptr;

	CFMutableStringRef lowercaseStr = ::CFStringCreateMutableCopy(kCFAllocatorDefault, 0, inStr);
	if(lowercaseStr != nullptr)
		::CFStringLowercase(lowercaseStr, nullptr);
	return lowercaseStr;
}

UInt32 StringToVersion(CFStringRef inString)
{
    if(inString == NULL)
        return 0;
    
    CFObj<CFArrayRef> numbersArr( ::CFStringCreateArrayBySeparatingStrings( kCFAllocatorDefault, inString, CFSTR(".") ) );
    if(numbersArr == NULL)
        return 0;
    
    CFIndex theCount = ::CFArrayGetCount(numbersArr);
    if(theCount > 3)
        theCount = 3;
    
    UInt8 versionNumbers[3];
    versionNumbers[0] = versionNumbers[1] = versionNumbers[2] = 0;
    for(CFIndex i = 0; i < theCount; i++)
    {
        CFStringRef oneNumString = (CFStringRef)::CFArrayGetValueAtIndex(numbersArr, i);
        if(oneNumString != NULL)
            versionNumbers[i] = (UInt8)::CFStringGetIntValue(oneNumString);
    }
    
    UInt32 outVersion = versionNumbers[0] * 10000 + versionNumbers[1] * 100 + versionNumbers[2];//new format
    /*
     UInt8 highestByte = 0;
     if(versionNumbers[0] > 9)
     {
     highestByte = versionNumbers[0]/10;
     versionNumbers[0] = versionNumbers[0] % 10;
     }
     
     UInt32 outVersion = ((UInt32)(highestByte & 0x0F) << 12) | ((UInt32)(versionNumbers[0] & 0x0F) << 8) |
     ((UInt32)(versionNumbers[1] & 0x0F) << 4) | ((UInt32)versionNumbers[2] & 0x0F);
     */
    return outVersion;
}

CFStringRef CreateVersionString(UInt32 inVersion)
{
    //    inVersion = ::CFSwapInt32HostToBig(inVersion);
    
    /*
     int higestByte = (inVersion & 0xF000) >> 12;
     int majorVersion = (inVersion & 0x0F00) >> 8;
     int minorVersion = (inVersion & 0x00F0) >> 4;
     int veryMinorVersion = (inVersion & 0x000F);
     */
    //new format
    int majorVersion = inVersion/10000;
    inVersion -= (10000 * majorVersion);
    int minorVersion = inVersion/100;
    inVersion -= (100 * minorVersion);
    int veryMinorVersion = inVersion;
    
    CFObj<CFStringRef> veryMinorStr;
    CFObj<CFStringRef> mainStr( CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d.%d"), majorVersion, minorVersion) );
    
    if(veryMinorVersion != 0)
        veryMinorStr.Adopt( CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR(".%d"), veryMinorVersion) );
    
    CFMutableStringRef wholeStr = ::CFStringCreateMutable( kCFAllocatorDefault, 0);
    
    if(mainStr != NULL)
        ::CFStringAppend( wholeStr, mainStr );
    
    if(veryMinorStr != NULL)
        ::CFStringAppend( wholeStr, veryMinorStr );
    
    return wholeStr;
}

// As NSString's stringByAddingPercentEncodingWithAllowedCharacters with URLQueryAllowedCharacterSet
// (escapeAll false) or alphanumericCharacterSet (escapeAll true): every other character becomes
// %XX for each byte of its UTF-8, in upper case. That method encodes every non-ASCII character
// whatever the set says, so "escape all" keeps exactly ASCII letters and digits, not the Unicode
// letters alphanumericCharacterSet holds. A string with a lone surrogate gives NULL, as there.
CFStringRef CreateStringByAddingPercentEscapes(CFStringRef inStr, bool escapeAll)
{
	if(inStr == nullptr)
		return nullptr;

	static const char kHexDigits[] = "0123456789ABCDEF";
	std::vector<UniChar> chars = CopyCharacters(inStr);
	std::string escaped;
	escaped.reserve(chars.size() * 3);

	for(size_t i = 0; i < chars.size(); i++)
	{
		UTF32Char oneChar = chars[i];
		if(::CFStringIsSurrogateHighCharacter(chars[i]))
		{
			if((i + 1 >= chars.size()) || !::CFStringIsSurrogateLowCharacter(chars[i + 1]))
				return nullptr;
			oneChar = ::CFStringGetLongCharacterForSurrogatePair(chars[i], chars[i + 1]);
			i++;
		}
		else if(::CFStringIsSurrogateLowCharacter(chars[i]))
		{
			return nullptr;
		}

		bool isAllowed = escapeAll ? IsASCIIAlphanumeric(oneChar) : IsURLQueryAllowed(oneChar);
		if(isAllowed)
		{
			AppendUTF8(escaped, oneChar);
			continue;
		}

		std::string utf8;
		AppendUTF8(utf8, oneChar);
		for(unsigned char oneByte : utf8)
		{
			escaped.push_back('%');
			escaped.push_back(kHexDigits[oneByte >> 4]);
			escaped.push_back(kHexDigits[oneByte & 0x0F]);
		}
	}

	return ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)escaped.data(), (CFIndex)escaped.size(), kCFStringEncodingUTF8, false);
}

//replaces \r, \n, \t, \\ with real values
void
ReplaceWhitespaceEscapesWithCharacters(CFMutableStringRef inStrRef)
{
    if(inStrRef == NULL)
        return;
    
    CFIndex idx = 0;
    CFIndex    charCount = ::CFStringGetLength(inStrRef);
    if(charCount < 2)//0 or 1 characters cannot be a pair of escapers
        return;
    
    UniChar currChar = ::CFStringGetCharacterAtIndex( inStrRef, 0 );
    UniChar nextChar = 0;
    while(idx < charCount )
    {
        //going backwards we get 2 characters at a time to looks for \r \n \t \\ pairs
        if( (idx+1) < charCount)
            nextChar = ::CFStringGetCharacterAtIndex( inStrRef, idx+1 );
        
        if( (currChar == '\\') &&
           ((nextChar == 'r') || (nextChar == 'n') || (nextChar == 't') || (nextChar == '\\') ) )
        {
            CFStringRef replacementString = NULL;
            switch(nextChar)
            {
                case 'r':
                    replacementString = CFSTR("\r");
                    break;
                    
                case 'n':
                    replacementString = CFSTR("\n");
                    break;
                    
                case 't':
                    replacementString = CFSTR("\t");
                    break;
                    
                case '\\':
                    replacementString = CFSTR("\\");
                    break;
            }
            
            assert(replacementString != NULL);
            CFStringReplace(inStrRef, CFRangeMake(idx, 2), replacementString);
            charCount--;//the string is now shorter
            nextChar = 0; //we swallowed the next char
            
            if( (idx+1) < charCount )
            {
                //replacement disturbed the loop by changing 2 characters into 1,
                //prepare the next loop iteration
                //we fetch new nextChar after the replaced range
                //and it will be assigned to currChar right below for new iteration
                nextChar = ::CFStringGetCharacterAtIndex( inStrRef, idx+1 );
            }
        }
        
        idx++;
        currChar = nextChar;
        nextChar = 0;
    }
}

void
ReplaceWhitespaceCharactersWithEscapes(CFMutableStringRef inStrRef)
{
    if(inStrRef == NULL)
        return;
    
    CFIndex    idx = ::CFStringGetLength(inStrRef) - 1;
    UniChar currChar = 0;
    while(idx >= 0)
    {
        currChar = ::CFStringGetCharacterAtIndex( inStrRef, idx );
        if( (currChar == '\r') || (currChar == '\n') || (currChar == '\t') || (currChar == '\\') )
        {
            CFStringRef replacementString = NULL;
            switch(currChar)
            {
                case '\r':
                    replacementString = CFSTR("\\r");
                    break;
                    
                case '\n':
                    replacementString = CFSTR("\\n");
                    break;
                    
                case '\t':
                    replacementString = CFSTR("\\t");
                    break;
                    
                case '\\':
                    replacementString = CFSTR("\\\\");
                    break;
            }
            
            assert(replacementString != NULL);
            CFStringReplace(inStrRef, CFRangeMake(idx, 1), replacementString);
        }
        idx--;
    }
    
}

static inline void
ReplaceSpecialCharsWithEscapesForAppleScript(CFMutableStringRef inStrRef)
{
	if(inStrRef == nullptr)
		return;

  	//replace double quotes & backslashes only
  	CFIndex	idx = ::CFStringGetLength(inStrRef) - 1;
  	UniChar currChar = 0;
	while(idx >= 0)
	{
 		currChar = ::CFStringGetCharacterAtIndex( inStrRef, idx);
 		if( (currChar == '\"') || (currChar == '\\') )
 		{
	 		::CFStringInsert( inStrRef, idx, CFSTR("\\") );
		}
		idx--;
	}
}


/* ReplaceSpecialCharsWithBackslashEscapes modifies path so the special characters in filename
will not be interpreted by shell.

As a test, I created in Finder a folder named:

	#`~!@$%^&*()_+={}[-]|\;'",.<>?/

This function created an escaped version of it:
	#\`~\!@\$%^\&\*\(\)_+=\{\}\[-\]\|\\\;\'\",.\<\>\?:

and it works fine in Terminal.

By the way: note that the '/' in Finder is represented as ':' in Terminal
You may create a file with ':' char in name in Terminal, but not in Finder
and you can create a file with '/' char in name in Finder but not in Terminal.
	
*/
static inline void
ReplaceSpecialCharsWithBackslashEscapes(CFMutableStringRef inStrRef)
{
	if(inStrRef == nullptr)
		return;

  	//replace spaces in path with backslash + space
  	CFIndex	idx = ::CFStringGetLength(inStrRef) - 1;
  	UniChar currChar = 0;
	while(idx >= 0)
	{
 		currChar = ::CFStringGetCharacterAtIndex( inStrRef, idx);
 		if( (currChar == ' ') || (currChar == '\\') || (currChar == '*') || (currChar == '?') || (currChar == '\t') ||
 			(currChar == '$') || (currChar == '\'') || (currChar == '\"') || (currChar == '!') || (currChar == '&') ||
 			(currChar == '(') || (currChar == ')') || (currChar == '{') || (currChar == '}') || (currChar == '[') ||
 			(currChar == ']') || (currChar == '|') || (currChar == ';') || (currChar == '<') || (currChar == '>') ||
 			(currChar == '`') || (currChar == 0x0A) || (currChar == 0x0D) )
 		{
	 		::CFStringInsert( inStrRef, idx, CFSTR("\\") );
		}
		idx--;
	}
}


//replaces all single quotes with '\'' sequence and adds ' at the beginning and end
static inline void
WrapWithSingleQuotesForShell(CFMutableStringRef inStrRef)
{
	if(inStrRef == nullptr)
		return;
  	CFIndex	idx = ::CFStringGetLength(inStrRef) - 1;
	CFIndex lastCharIndex = idx;
  	UniChar currChar = 0;
	Boolean addInFront = true;
	Boolean addAtEnd = true;
	while(idx >= 0)
	{
 		currChar = ::CFStringGetCharacterAtIndex( inStrRef, idx);
 		if( currChar == '\'' )
 		{
			if(idx == lastCharIndex)
			{
				::CFStringAppend( inStrRef, CFSTR("\\'") );//append \' after existing '
				addAtEnd = false;
			}
			else if(idx == 0)
			{
				::CFStringInsert( inStrRef, idx, CFSTR("\\'") );//insert \' before existing '
				addInFront = false;
			}
			else
				::CFStringInsert( inStrRef, idx, CFSTR("'\\'") );//insert '\' before existing '
		}
		idx--;
	}

	if(addInFront)
		::CFStringInsert( inStrRef, 0, CFSTR("'") );//at the beginning

	if(addAtEnd)
		::CFStringAppend( inStrRef, CFSTR("'") );//at the end
}


//this function always creates a copy of string so you may release original string when not needed
CFStringRef
CreateEscapedStringCopy(CFStringRef inStrRef, UInt16 escSpecialCharsMode)
{
	if(inStrRef == nullptr)
  		return nullptr;

	switch(escSpecialCharsMode)
	{
		case kEscapeWithBackslash:
		{
			CFMutableStringRef escapedStr = ::CFStringCreateMutableCopy(kCFAllocatorDefault, 0, inStrRef);
			ReplaceSpecialCharsWithBackslashEscapes(escapedStr);
			return escapedStr;
		}

		case kEscapeWithPercent:
		{
			return CreateStringByAddingPercentEscapes(inStrRef, false /*escapeAll*/);
		}
	
		case kEscapeWithPercentAll:
		{
			//escape all illegal URL chars and all non-alphanumeric legal chars
			//legal chars need to be escaped in order ot prevent conflicts in shell execution
			return CreateStringByAddingPercentEscapes(inStrRef, true /*escapeAll*/);
		}
		
		case kEscapeForAppleScript:
		{
			CFMutableStringRef escapedStr = ::CFStringCreateMutableCopy(kCFAllocatorDefault, 0, inStrRef);
			ReplaceSpecialCharsWithEscapesForAppleScript(escapedStr);
			return escapedStr;
		}

		case kEscapeWrapWithSingleQuotesForShell:
		{
			CFMutableStringRef escapedStr = ::CFStringCreateMutableCopy(kCFAllocatorDefault, 0, inStrRef);
			WrapWithSingleQuotesForShell(escapedStr);
			return escapedStr;
		}
	
		case kEscapeNone:
		default:
		break;
	}

	::CFRetain(inStrRef);
	return inStrRef;
}


CFStringRef
CreateCombinedString( CFArrayRef inStringsArray, CFStringRef inSeparator, CFStringRef inPrefix, CFStringRef inSuffix, UInt16 escSpecialCharsMode )
{
    if(inStringsArray == NULL)
        return NULL;

    CFIndex itemCount = ::CFArrayGetCount(inStringsArray);

    CFMutableStringRef mutableStr = ::CFStringCreateMutable(kCFAllocatorDefault, 0);
    for(CFIndex i = 0; i < itemCount; i++)
    {
        CFTypeRef oneItem = ::CFArrayGetValueAtIndex(inStringsArray,i);
        CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( oneItem );
        if(oneString != NULL)
        {
            CFObj<CFStringRef> escapedString( CreateEscapedStringCopy(oneString, escSpecialCharsMode) );

            if(inPrefix != NULL)
            {
                ::CFStringAppend( mutableStr, inPrefix );
            }
            
            ::CFStringAppend( mutableStr, escapedString );
            
            if(inSuffix != NULL)
            {
                ::CFStringAppend( mutableStr, inSuffix );
            }

            if( (inSeparator != NULL) && i < (itemCount-1) )
            {//add separator, but not after the last item
                ::CFStringAppend( mutableStr, inSeparator );
            }
        }
    }
    return mutableStr;
}

CFStringRef
CreatePathFromCFURL(CFURLRef inPathURL, UInt16 escSpecialCharsMode)
{
    if(inPathURL == nullptr)
        return nullptr;

    CFObj<CFURLRef> absURL = CFURLCopyAbsoluteURL(inPathURL);
    CFObj<CFStringRef> pathStr = CFURLCopyFileSystemPath(absURL, kCFURLPOSIXPathStyle);
    CFObj<CFStringRef> escapedPathStr = CreateEscapedStringCopy(pathStr, escSpecialCharsMode);
    return escapedPathStr.Detach();
}

CFStringRef
CreateParentPathFromCFURL(CFURLRef inPathURL, UInt16 escSpecialCharsMode)
{
    if(inPathURL == nullptr)
        return nullptr;

    CFObj<CFURLRef> absURL = CFURLCopyAbsoluteURL(inPathURL);
    CFObj<CFURLRef> newURL = CFURLCreateCopyDeletingLastPathComponent(kCFAllocatorDefault, absURL);
    CFObj<CFStringRef> pathStr = CFURLCopyFileSystemPath(newURL, kCFURLPOSIXPathStyle);
    CFObj<CFStringRef> escapedPathStr = CreateEscapedStringCopy(pathStr, escSpecialCharsMode);
    return escapedPathStr.Detach();
}

CFStringRef
CreateNameFromCFURL(CFURLRef inPathURL, UInt16 escSpecialCharsMode)
{
    if(inPathURL == nullptr)
        return nullptr;

    CFObj<CFStringRef> pathStr = CFURLCopyLastPathComponent(inPathURL);
    CFObj<CFStringRef> escapedPathStr = CreateEscapedStringCopy(pathStr, escSpecialCharsMode);
    return escapedPathStr.Detach();
}

CFStringRef
CreateNameNoExtensionFromCFURL(CFURLRef inPathURL, UInt16 escSpecialCharsMode)
{
    if(inPathURL == nullptr)
        return nullptr;

    CFObj<CFURLRef> newURL = CFURLCreateCopyDeletingPathExtension(kCFAllocatorDefault, inPathURL);
    if(newURL == nullptr)
        return nullptr;

    CFObj<CFStringRef> pathStr = CFURLCopyLastPathComponent(newURL);
    CFObj<CFStringRef> escapedPathStr = CreateEscapedStringCopy(pathStr, escSpecialCharsMode);
    return escapedPathStr.Detach();
}

CFStringRef
CreateExtensionOnlyFromCFURL(CFURLRef inPathURL, UInt16 escSpecialCharsMode)
{
    if(inPathURL == nullptr)
        return nullptr;

    CFObj<CFStringRef> pathStr = CFURLCopyPathExtension(inPathURL);
    CFObj<CFStringRef> escapedPathStr = CreateEscapedStringCopy(pathStr, escSpecialCharsMode);
    return escapedPathStr.Detach();
}

CFStringRef
CreateStringFromCFURLArray(CFArrayRef inURLArray, CFURLToStringProc inProc, 
                          CFStringRef inSeparator, CFStringRef inPrefix, 
                          CFStringRef inSuffix, UInt16 escSpecialCharsMode)
{
    if(inURLArray == nullptr || inProc == nullptr)
        return nullptr;

    CFIndex count = CFArrayGetCount(inURLArray);
    if(count == 0)
        return nullptr;

    CFObj<CFMutableArrayRef> stringArray(CFArrayCreateMutable(kCFAllocatorDefault, count, &kCFTypeArrayCallBacks));
    if(stringArray == nullptr)
        return nullptr;

    for(CFIndex i = 0; i < count; i++)
    {
        CFURLRef url = (CFURLRef)CFArrayGetValueAtIndex(inURLArray, i);
        CFObj<CFStringRef> str( inProc(url, escSpecialCharsMode) );
        if(str != nullptr)
            CFArrayAppendValue(stringArray, str);
    }

    return CreateCombinedString(stringArray, inSeparator, inPrefix, inSuffix, escSpecialCharsMode);
}


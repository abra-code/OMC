#import <Foundation/Foundation.h>
#include "OMCStrings.h"
#include "OMCConstants.h"
#include "CFObj.h"
#include "ACFType.h"

CFStringRef CreatePathByExpandingTilde(CFStringRef inPath)
{
    NSString *expandedString = [(__bridge NSString *)inPath stringByExpandingTildeInPath];
    return (CFStringRef)CFBridgingRetain(expandedString);
}

CFStringRef CopyFilenameExtension(CFStringRef inFilePath)
{
    NSString *pathExtension = [(__bridge NSString*)inFilePath pathExtension];
    return (CFStringRef)CFBridgingRetain(pathExtension);
}

CFStringRef CreateLowercaseString(CFStringRef inStr)
{
    NSString *lowercaseString = [(__bridge NSString*)inStr lowercaseString];
    return (CFStringRef)CFBridgingRetain(lowercaseString);
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
    
    //    CFStringRef higestStr = NULL;
    CFStringRef veryMinorStr = NULL;
    
    //    if(higestByte != 0)
    //        higestStr = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d"), higestByte);
    
    CFStringRef mainStr = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d.%d"), majorVersion, minorVersion);
    
    if(veryMinorVersion != 0)
        veryMinorStr = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR(".%d"), veryMinorVersion);
    
    CFMutableStringRef wholeStr = ::CFStringCreateMutable( kCFAllocatorDefault, 0);
    //    if(higestStr != NULL)
    //    {
    //        ::CFStringAppend( wholeStr, higestStr );
    //        ::CFRelease(higestStr);
    //    }
    
    if(mainStr != NULL)
    {
        ::CFStringAppend( wholeStr, mainStr );
        ::CFRelease(mainStr);
    }
    
    if(veryMinorStr != NULL)
    {
        ::CFStringAppend( wholeStr, veryMinorStr );
        ::CFRelease(veryMinorStr);
    }
    
    return wholeStr;
}

CFStringRef CreateStringByAddingPercentEscapes(CFStringRef inStr, bool escapeAll)
{
    NSString *escapedString = [(__bridge NSString *)inStr stringByAddingPercentEncodingWithAllowedCharacters:
                                        escapeAll ? [NSCharacterSet alphanumericCharacterSet] : [NSCharacterSet URLQueryAllowedCharacterSet]];
    return (CFStringRef)CFBridgingRetain(escapedString);
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

bool
WriteStringToFile(CFStringRef inContentStr, CFStringRef inFilePath)
{
	if((inContentStr == NULL) || (inFilePath == NULL))
		return false;

    NSError *error = nil;
    NSString *__weak contentStr = (__bridge NSString *)inContentStr;
    BOOL succeed = [contentStr writeToFile:(__bridge NSString *)inFilePath
                                atomically:NO
                                  encoding:NSUTF8StringEncoding
                                     error:&error];
    return (bool)succeed;
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


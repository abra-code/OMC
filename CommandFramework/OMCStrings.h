
#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

CFStringRef    CreatePathByExpandingTilde(CFStringRef inPath);
CFStringRef    CopyFilenameExtension(CFStringRef inFilePath);

CFStringRef    CreateLowercaseString(CFStringRef inStr);

UInt32         StringToVersion(CFStringRef inString);
CFStringRef    CreateVersionString(UInt32 inVersion);

CFStringRef    CreateStringByAddingPercentEscapes(CFStringRef inStr, bool escapeAll);
void		   ReplaceWhitespaceEscapesWithCharacters(CFMutableStringRef ioStrRef);
void		   ReplaceWhitespaceCharactersWithEscapes(CFMutableStringRef ioStrRef);

CFStringRef    CreateEscapedStringCopy(CFStringRef inStrRef, UInt16 escSpecialCharsMode);

// For text typed into an interactive shell (Terminal, iTerm): a copy without the control
// characters a terminal and a line editor take as editing keys, tab turned into a space
// (see OMCStrings.cpp)
CFStringRef    CreateCopyWithoutTerminalControlCharacters(CFStringRef inStr);


CFStringRef    CreateCombinedString(CFArrayRef inStringsArray, CFStringRef inSeparator, CFStringRef inPrefix, CFStringRef inSuffix, UInt16 escSpecialCharsMode);

typedef CFStringRef (*CFURLToStringProc)(CFURLRef inPath, UInt16 escSpecialCharsMode);

CFStringRef    CreatePathFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode);
CFStringRef    CreateParentPathFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode);
CFStringRef    CreateNameFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode);
CFStringRef    CreateNameNoExtensionFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode);
CFStringRef    CreateExtensionOnlyFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode);

CFStringRef    CreateStringFromCFURLArray(CFArrayRef inURLArray, CFURLToStringProc inProc, 
                                          CFStringRef inSeparator, CFStringRef inPrefix, 
                                          CFStringRef inSuffix, UInt16 escSpecialCharsMode);

#ifdef __cplusplus
}
#endif


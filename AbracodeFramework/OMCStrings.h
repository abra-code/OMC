
#pragma once

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

bool		   WriteStringToFile(CFStringRef inContentStr, CFStringRef inFilePath);

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


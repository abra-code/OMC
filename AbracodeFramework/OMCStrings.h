
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

CFStringRef			CreatePathByExpandingTilde(CFStringRef inPath);
CFStringRef			CopyFilenameExtension(CFStringRef inFilePath);

CFStringRef			CreateLowercaseString(CFStringRef inStr);

UInt32				StringToVersion(CFStringRef inString);
CFStringRef			CreateVersionString(UInt32 inVersion);

CFStringRef         CreateStringByAddingPercentEscapes(CFStringRef inStr, bool escapeAll);
void				ReplaceWhitespaceEscapesWithCharacters(CFMutableStringRef ioStrRef);
void				ReplaceWhitespaceCharactersWithEscapes(CFMutableStringRef ioStrRef);


#ifdef __cplusplus
}
#endif


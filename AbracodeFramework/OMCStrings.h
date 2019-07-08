
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

UInt32				StringToVersion(CFStringRef inString);
CFStringRef			CreateVersionString(UInt32 inVersion);
CFStringRef			CreatePathByExpandingTilde(CFStringRef inPath);

void				ReplaceWhitespaceEscapesWithCharacters(CFMutableStringRef ioStrRef);
void				ReplaceWhitespaceCharactersWithEscapes(CFMutableStringRef ioStrRef);

#ifdef __cplusplus
}
#endif


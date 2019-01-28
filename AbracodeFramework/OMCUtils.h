
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

SInt32				GetSpecialWordID(CFStringRef inStr);
SInt32				GetSpecialEnvironWordID(CFStringRef inStr);

UInt32				StringToVersion(CFStringRef inString);
CFStringRef			CreateVersionString(UInt32 inVersion);
CFStringRef			CreatePathByExpandingTilde(CFStringRef inPath);
UInt8				GetEscapingMode(CFStringRef theStr);
CFStringRef			GetEscapingModeString(UInt8 inEscapeMode);
void				ReplaceWhitespaceEscapesWithCharacters(CFMutableStringRef ioStrRef);
void				ReplaceWhitespaceCharactersWithEscapes(CFMutableStringRef ioStrRef);

#ifdef __cplusplus
}
#endif


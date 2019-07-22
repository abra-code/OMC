#include "OMCStrings.h"
#include "CFObj.h"
#import <Foundation/Foundation.h>

CFStringRef CreatePathByExpandingTilde(CFStringRef inPath)
{
    if(inPath == NULL)
        return NULL;
    
    @autoreleasepool
    {
        NSString *expandedString = [(NSString *)inPath stringByExpandingTildeInPath];
        [expandedString retain];
        return (CFStringRef)expandedString;
    }
}

CFStringRef CreateStringByAddingPercentEscapes(CFStringRef inStr, bool escapeAll)
{
    @autoreleasepool
    {
        NSString *escapedString = [(NSString *)inStr stringByAddingPercentEncodingWithAllowedCharacters:
                                            escapeAll ? [NSCharacterSet alphanumericCharacterSet] : [NSCharacterSet URLQueryAllowedCharacterSet]];
        return (CFStringRef)[escapedString retain];
    }
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

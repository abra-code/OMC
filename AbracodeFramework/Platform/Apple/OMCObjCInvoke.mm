//
//  OMCObjCInvoke.mm
//  Abracode
//
//  omc_dialog_control's INVOKE on macOS (Platform/OMCInvoke.h, Platform/Apple/OMCObjCInvoke.h): each
//  message is a selector and its arguments as strings, sent through NSInvocation with every argument
//  converted to the type the method takes. Moved from OMCWindowController.mm (Phase 5, step 8c), so
//  that the portable ActionUI window can reach it through the window host's native window.
//

#import <Cocoa/Cocoa.h>
#include "OMCInvoke.h"
#include "OMCObjCInvoke.h"
#include "CFObj.h"
#include "ACFType.h"
#include <string>
#include <vector>

/*
 Method argument types. (Deprecated. These constants are used internally by NSInvocation - you should not use them directly.)
 
 enum _NSObjCValueType {
 NSObjCNoType = 0,
 NSObjCVoidType = 'v',
 NSObjCCharType = 'c',
 NSObjCShortType = 's',
 NSObjCLongType = 'l',
 NSObjCLonglongType = 'q',
 NSObjCFloatType = 'f',
 NSObjCDoubleType = 'd',
 
 NSObjCBoolType = 'B',
 
 NSObjCSelectorType = ':',
 NSObjCObjectType = '@',
 NSObjCStructType = '{',
 NSObjCPointerType = '^',
 NSObjCStringType = '*',
 NSObjCArrayType = '[',
 NSObjCUnionType = '(',
 NSObjCBitfield = 'b'
 };
 
 
 argument types:
 @ = id
 : = selector
 c = signed char
 C = unsigned char
 s = signed short
 S = unsigned short
 i = signed int
 I = unsigned int, some enums too
 q = long long
 Q = unsigned long long
 f = float
 d = double
 ^@ = *id
 v = void
 ^v  = void *
 {_NSRange=II} = NSRange {unsigned int, unsigned int}
 {_NSPoint=ff} = NSPoint {float, float}
 {_NSRect={_NSPoint=ff}{_NSSize=ff}}
 r* = const char *
 r^^{_NSRect} = const NSRect **
 */

typedef enum ObjCSelectorArgumentType
{
    kObjCArgNoType = 0,
    kObjCArgVoidType = 'v',
    kObjCArgCharType = 'c',
    kObjCArgUCharType = 'C',
    kObjCArgShortType = 's',
    kObjCArgUShortType = 'S',
    kObjCArgIntType = 'i',
    kObjCArgUIntType = 'I',
    kObjCArgLongType = 'l',
    kObjCArgULongType = 'L',
    kObjCArgLonglongType = 'q',
    kObjCArgULonglongType = 'Q',
    kObjCArgFloatType = 'f',
    kObjCArgDoubleType = 'd',
    
    kObjCArgBoolType = 'B',
    
    kObjCArgSelectorType = ':',
    kObjCArgObjectType = '@',
    kObjCArgStructType = '{',
    kObjCArgPointerType = '^',
    kObjCArgStringType = '*',
    kObjCArgArrayType = '[',
    kObjCArgUnionType = '(',
    kObjCArgBitfield = 'b'
} ObjCSelectorArgumentType;

// The structures an INVOKE argument can carry. On 64-bit macOS the AppKit geometry types are the
// CG ones, so their type encodings name CGPoint, CGSize and CGRect ("{CGRect={CGPoint=dd}{CGSize=dd}}"),
// while NSRange keeps "{_NSRange=QQ}". The NS spellings are accepted too, for 32-bit-era encodings.
typedef enum ObjCStructKind
{
    kObjCStructUnsupported = 0,
    kObjCStructRange,
    kObjCStructPoint,
    kObjCStructSize,
    kObjCStructRect
} ObjCStructKind;

static ObjCStructKind
FindStructKind(const char *argTypeStr)
{
    if(argTypeStr == NULL)
        return kObjCStructUnsupported;
    if(argTypeStr[0] == 'r')//const - skip it
        argTypeStr++;
    if(argTypeStr[0] != '{')
        return kObjCStructUnsupported;

    //the structure name runs from after '{' to the first '=' or '}'
    const char *nameStart = argTypeStr + 1;
    size_t nameLength = strcspn(nameStart, "=}");
    std::string structName(nameStart, nameLength);

    if( (structName == "_NSRange") || (structName == "NSRange") )
        return kObjCStructRange;
    if( (structName == "CGPoint") || (structName == "_NSPoint") || (structName == "NSPoint") )
        return kObjCStructPoint;
    if( (structName == "CGSize") || (structName == "_NSSize") || (structName == "NSSize") )
        return kObjCStructSize;
    if( (structName == "CGRect") || (structName == "_NSRect") || (structName == "NSRect") )
        return kObjCStructRect;
    return kObjCStructUnsupported;
}

static ObjCSelectorArgumentType
FindArgumentType(const char *argTypeStr)
{
    if(argTypeStr == NULL)
        return kObjCArgNoType;
    if(argTypeStr[0] == 'r')//const - skip it
        return (ObjCSelectorArgumentType)argTypeStr[1];
    return (ObjCSelectorArgumentType)argTypeStr[0];
}

static void SendObjCMessage(CFArrayRef oneObjCMessage, id messageTarget)
{
    CFObj<CFLocaleRef> currentLocale;
    CFObj<CFNumberFormatterRef> numberFormatter;

    @try
    {
        //TODO:
        //check if object responds to given message
        //obtain NSMethodSignature, check argument types
        //create NSInvocation and invoke on object
        CFIndex elementCount = CFArrayGetCount(oneObjCMessage);
        if( elementCount == 0 )
            return;

        NSMutableString *methodName = [NSMutableString string];
        for(CFIndex i = 0; i < elementCount; i+=2)
        {//first obtain method name
            CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(oneObjCMessage, i);
            CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
            if(oneString != NULL)
            {
                [methodName appendString:(__bridge NSString *)oneString];
            }
        }

        SEL methodSelector = NSSelectorFromString(methodName);
        NSMethodSignature *methodSig = [messageTarget methodSignatureForSelector:methodSelector];
        if( methodSig != nil )
        {//good news - object has this method implemented
            
            //const char *returnType = [methodSig methodReturnType];
            //NSLog(@"methodReturnType=%s\n", returnType);

            NSInvocation *messageInvocation = [NSInvocation invocationWithMethodSignature:methodSig];
            if(messageInvocation != NULL)
            {
                BOOL okToAddArgument = YES;
                [messageInvocation setTarget:messageTarget];
                [messageInvocation setSelector:methodSelector];
                alignas(16) char stackBuff[128];//128 bytes should be enough for most structures; aligned for the doubles and CGFloats written into it
                NSUInteger argCount = [methodSig numberOfArguments] - 2;//count only real arguments, skip self and selector
                for(NSUInteger argIndex = 0; argIndex < argCount; argIndex++)
                {
                    const char *argTypeStr = [methodSig getArgumentTypeAtIndex:2+argIndex];
    #if DEBUG
                    NSLog(@"argument %d type=%s\n", (int)argIndex+1, argTypeStr);
    #endif
                    //set argument
                    if( (argIndex*2 + 1) < elementCount )
                    {
                        CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(oneObjCMessage, argIndex*2 + 1);
                        CFStringRef argString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
                        if(argString != NULL)
                        {
                            ObjCSelectorArgumentType argType = FindArgumentType(argTypeStr);
                            okToAddArgument = YES;
                            
                            switch(argType)
                            {
                                case kObjCArgCharType:
                                {//this is also BOOL that's why we check for YES/NO true/false
                                    char charVal = 0;
                                    if( (kCFCompareEqualTo == ::CFStringCompare( CFSTR("YES"), argString, kCFCompareCaseInsensitive)) ||
                                       (kCFCompareEqualTo == ::CFStringCompare( CFSTR("true"), argString, kCFCompareCaseInsensitive)) )
                                    {
                                        charVal = 1;
                                    }
                                    else if( (kCFCompareEqualTo == ::CFStringCompare( CFSTR("NO"), argString, kCFCompareCaseInsensitive)) ||
                                            (kCFCompareEqualTo == ::CFStringCompare( CFSTR("false"), argString, kCFCompareCaseInsensitive)) )
                                    {
                                        charVal = 0;
                                    }
                                    else
                                    {
                                        charVal = (char)CFStringGetIntValue(argString);
                                    }
                                    
                                    *(char *)stackBuff = charVal;
                                }
                                break;
                                
                                case kObjCArgUCharType:
                                {
                                    *(unsigned char *)stackBuff = (unsigned char)CFStringGetIntValue(argString);
                                }
                                break;
                                
                                case kObjCArgShortType:
                                {
                                    *(short *)stackBuff = (short)CFStringGetIntValue(argString);
                                }
                                break;
                                    
                                case kObjCArgUShortType:
                                {
                                    *(unsigned short *)stackBuff = (unsigned short)CFStringGetIntValue(argString);
                                }
                                break;

                                case kObjCArgIntType:
                                {
                                    *(int *)stackBuff = (int)CFStringGetIntValue(argString);
                                }
                                break;

                                case kObjCArgLongType:
                                {
                                    *(long *)stackBuff = (long)CFStringGetIntValue(argString);
                                }
                                break;
                                    
                                case kObjCArgULongType:
                                case kObjCArgUIntType:
                                case kObjCArgLonglongType:
                                case kObjCArgULonglongType:
                                {
                                    if(currentLocale == NULL)
                                        currentLocale.Adopt( CFLocaleCopyCurrent() );
                                    
                                    if(numberFormatter == NULL)
                                        numberFormatter.Adopt( CFNumberFormatterCreate(kCFAllocatorDefault, currentLocale, kCFNumberFormatterDecimalStyle) );

                                    long long longlongVal = 0;
                                    okToAddArgument = CFNumberFormatterGetValueFromString(numberFormatter, argString, NULL, kCFNumberLongLongType, &longlongVal);
                                    if(okToAddArgument)
                                    {
                                        if(argType == kObjCArgULongType)
                                        {
                                            *(unsigned long *)stackBuff = (unsigned long)longlongVal;
                                        }
                                        else if(argType == kObjCArgUIntType)
                                        {
                                            *(unsigned int *)stackBuff = (unsigned int)longlongVal;
                                        }
                                        else if(argType == kObjCArgLonglongType)
                                        {
                                            *(long long *)stackBuff = longlongVal;
                                        }
                                        else if(argType == kObjCArgULonglongType)
                                        {
                                            *(unsigned long long *)stackBuff = (unsigned long long)longlongVal;
                                        }
                                    }
                                }
                                break;
                                
                                case kObjCArgFloatType:
                                {
                                    *(float *)stackBuff = (float)CFStringGetDoubleValue(argString);
                                }
                                break;
                                    
                                case kObjCArgDoubleType:
                                {
                                    *(double *)stackBuff = (double)CFStringGetDoubleValue(argString);
                                }
                                break;
                                
                                case kObjCArgBoolType:
                                {
                                    BOOL boolVal = NO;
                                    if( (kCFCompareEqualTo == ::CFStringCompare( CFSTR("YES"), argString, kCFCompareCaseInsensitive)) ||
                                        (kCFCompareEqualTo == ::CFStringCompare( CFSTR("true"), argString, kCFCompareCaseInsensitive)) )
                                    {
                                        boolVal = YES;
                                    }
                                    else if( (kCFCompareEqualTo == ::CFStringCompare( CFSTR("NO"), argString, kCFCompareCaseInsensitive)) ||
                                            (kCFCompareEqualTo == ::CFStringCompare( CFSTR("false"), argString, kCFCompareCaseInsensitive)) )
                                    {
                                        boolVal = NO;
                                    }
                                    else
                                    {
                                        SInt32 intVal = CFStringGetIntValue(argString);
                                        boolVal = (BOOL)intVal;
                                    }
                                    *(BOOL *)stackBuff = boolVal;
                                }
                                break;

                                case kObjCArgObjectType:
                                {//only NSString */CFStringRef supported as id/NSObject *
                                    if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("omc_nil"), argString, kCFCompareCaseInsensitive) )
                                    {
                                        *(CFTypeRef *)stackBuff = nil;
                                    }
                                    else
                                    {
                                        *(CFStringRef *)stackBuff = argString;
                                    }
                                }
                                break;
                                    
                                case kObjCArgStructType:
                                {
                                    memset(stackBuff, 0, sizeof(stackBuff));
                                    
                                    //the members are comma-separated numbers: "location,length", "x,y", "width,height", "x,y,width,height"
                                    CFObj<CFArrayRef> numberArray( CFStringCreateArrayBySeparatingStrings( kCFAllocatorDefault, argString, CFSTR(",") ) );
                                    CFIndex numberCount = (numberArray != NULL) ? CFArrayGetCount(numberArray) : 0;
                                    ObjCStructKind structKind = FindStructKind(argTypeStr);
                                    CFIndex requiredCount = (structKind == kObjCStructRect) ? 4 : 2;
                                    
                                    if(structKind == kObjCStructUnsupported)
                                    {
                                        okToAddArgument = NO;
                                        NSLog(@"OMC INVOKE: structure type %s unsupported for argument %d for \"%@\" selector", argTypeStr, (int)argIndex+1, methodName);
                                    }
                                    else if(numberCount < requiredCount)
                                    {
                                        okToAddArgument = NO;
                                        NSLog(@"OMC INVOKE: structure argument %d for \"%@\" selector needs %d comma-separated numbers", (int)argIndex+1, methodName, (int)requiredCount);
                                    }
                                    else
                                    {
                                        CFStringRef members[4] = { NULL, NULL, NULL, NULL };
                                        for(CFIndex i = 0; i < requiredCount; i++)
                                        {
                                            members[i] = ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(numberArray, i) );
                                            if(members[i] == NULL)
                                                okToAddArgument = NO;
                                        }
                                        
                                        if(okToAddArgument)
                                        {
                                            switch(structKind)
                                            {
                                                case kObjCStructRange:
                                                {
                                                    NSRange *theRange = (NSRange *)stackBuff;
                                                    theRange->location = ::CFStringGetIntValue(members[0]);
                                                    theRange->length = ::CFStringGetIntValue(members[1]);
                                                }
                                                break;
                                                
                                                case kObjCStructPoint:
                                                {
                                                    NSPoint *thePoint = (NSPoint *)stackBuff;
                                                    thePoint->x = (CGFloat)::CFStringGetDoubleValue(members[0]);
                                                    thePoint->y = (CGFloat)::CFStringGetDoubleValue(members[1]);
                                                }
                                                break;
                                                
                                                case kObjCStructSize:
                                                {
                                                    NSSize *theSize = (NSSize *)stackBuff;
                                                    theSize->width = (CGFloat)::CFStringGetDoubleValue(members[0]);
                                                    theSize->height = (CGFloat)::CFStringGetDoubleValue(members[1]);
                                                }
                                                break;
                                                
                                                case kObjCStructRect:
                                                {
                                                    NSRect *theRect = (NSRect *)stackBuff;
                                                    theRect->origin.x = (CGFloat)::CFStringGetDoubleValue(members[0]);
                                                    theRect->origin.y = (CGFloat)::CFStringGetDoubleValue(members[1]);
                                                    theRect->size.width = (CGFloat)::CFStringGetDoubleValue(members[2]);
                                                    theRect->size.height = (CGFloat)::CFStringGetDoubleValue(members[3]);
                                                }
                                                break;
                                                
                                                case kObjCStructUnsupported:
                                                break;
                                            }
                                        }
                                    }
                                }
                                break;
                                    
                                case kObjCArgPointerType:
                                case kObjCArgStringType:
                                case kObjCArgArrayType:
                                case kObjCArgUnionType:
                                case kObjCArgBitfield:
                                {
                                    if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("omc_nil"), argString, kCFCompareCaseInsensitive) )
                                    {
                                        *(CFTypeRef *)stackBuff = nil;
                                    }
                                    else
                                    {
                                        okToAddArgument = NO;
                                        NSLog(@"OMC INVOKE: unsupported argument type for argument %d for \"%@\" selector", (int)argIndex+1, methodName);
                                    }
                                }
                                break;
                                
                                case kObjCArgNoType:
                                case kObjCArgVoidType:
                                case kObjCArgSelectorType:
                                default:
                                {
                                    okToAddArgument = NO;
                                    NSLog(@"OMC INVOKE: invalid argument %d for \"%@\" selector", (int)argIndex+1, methodName);
                                }
                                break;
                            }
                            
                            if(okToAddArgument)
                            {
                                [messageInvocation setArgument:(void *)stackBuff atIndex:2+argIndex];
                            }
                            else
                            {
                                break;//we will not be able to process this comamnd
                            }
                        }
                    }
                    else
                    {
                        NSLog(@"OMC INVOKE: argument count mismatch for \"%@\" selector", methodName);
                    }
                }
                
                if(okToAddArgument)
                    [messageInvocation invoke];
            }
        }
        else
        {
            NSLog(@"OMC INVOKE: target object does not respond to \"%@\" selector", methodName);
        }
    }
    @catch (NSException *localException)
    {
        NSLog(@"OMC INVOKE received exception while trying to invoke a custom message: %@", localException);
    }
}

void
OMCSendObjCMessages(id inTarget, CFArrayRef inMessages) noexcept
{
	if( (inTarget == nil) || (inMessages == NULL) )
		return;

	CFIndex messageCount = ::CFArrayGetCount(inMessages);
	for(CFIndex msgIndex = 0; msgIndex < messageCount; msgIndex++)
	{
		CFArrayRef oneObjCMessage = ACFType<CFArrayRef>::DynamicCast( ::CFArrayGetValueAtIndex(inMessages, msgIndex) );
		if(oneObjCMessage != NULL)
			SendObjCMessage(oneObjCMessage, inTarget);
	}
}

void
OMCInvokeMessages(OMCInvokeTarget inTarget, void *inNativeWindow, CFArrayRef inMessages) noexcept
{
	id target = nil;
	switch(inTarget)
	{
		case OMCInvokeTarget::window:
			target = (__bridge id)inNativeWindow;
		break;

		case OMCInvokeTarget::application:
			target = [NSApplication sharedApplication];
		break;

		case OMCInvokeTarget::workspace:
			target = [NSWorkspace sharedWorkspace];
		break;
	}
	OMCSendObjCMessages(target, inMessages);
}

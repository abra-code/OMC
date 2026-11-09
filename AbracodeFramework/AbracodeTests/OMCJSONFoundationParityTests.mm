//
//  OMCJSONFoundationParityTests.mm
//  AbracodeTests
//
//  Common/ACFJSON.cpp replaces NSJSONSerialization (Linux has none) for Command.json and the
//  .json files plister reads and writes. Scripts see the results, so it must read exactly what
//  Foundation read and write exactly the bytes Foundation wrote with NSJSONWritingPrettyPrinted |
//  NSJSONWritingSortedKeys. Foundation is the oracle: each test compares both over the same
//  inputs. The rules and the deliberate differences are in ACFJSON.h.
//
//  ACFJSON and yyjson are not exported from Abracode.framework, so they compile into this bundle
//  (ACFJSON.cpp here, yyjson.c through OMCTestsYYJSON.c).
//

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#include <cmath>
#include <string>
#include <vector>

#include "../../Common/ACFJSON.cpp"

@interface OMCJSONFoundationParityTests : XCTestCase
@end

@implementation OMCJSONFoundationParityTests
{
    long _checks;
    long _mismatches;
    NSMutableArray<NSString *> *_firstMismatches;
}

- (void)setUp
{
    [super setUp];
    _checks = 0;
    _mismatches = 0;
    _firstMismatches = [NSMutableArray array];
}

- (void)report:(NSString *)what
{
    _mismatches++;
    if(_firstMismatches.count < 20)
        [_firstMismatches addObject:what];
}

- (void)assertNoMismatches
{
    XCTAssertGreaterThan(_checks, 0);
    XCTAssertEqual(_mismatches, 0L, @"%ld of %ld results differ from Foundation; first ones:\n%@",
                   _mismatches, _checks, [_firstMismatches componentsJoinedByString:@"\n"]);
}

static NSString *ShowBytes(NSData *d)
{
    NSMutableString *s = [NSMutableString string];
    const unsigned char *b = (const unsigned char *)d.bytes;
    for(NSUInteger i = 0; (i < d.length) && (i < 80); i++)
        [s appendFormat:((b[i] >= 0x20) && (b[i] < 0x7F)) ? @"%c" : @"\\x%02x", b[i]];
    return s;
}

static NSString *ShowObject(id obj)
{
    return (obj == nil) ? @"error" : [[obj description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
}

// Strict equality: same kinds, integers and floats kept apart, -0.0 and 0.0 kept apart.
static bool SameValue(id a, CFTypeRef b)
{
    if((a == nil) || (b == NULL))
        return (a == nil) && (b == NULL);
    CFTypeRef ca = (__bridge CFTypeRef)a;
    if((CFGetTypeID(ca) == CFBooleanGetTypeID()) || (CFGetTypeID(b) == CFBooleanGetTypeID()))
        return (CFGetTypeID(ca) == CFGetTypeID(b)) && CFEqual(ca, b);
    if([a isKindOfClass:[NSDecimalNumber class]])
    {   // deliberate difference (ACFJSON.h): a number beyond 64 bits reads as a double
        if((CFGetTypeID(b) != CFNumberGetTypeID()) || !CFNumberIsFloatType((CFNumberRef)b))
            return false;
        double value = 0;
        CFNumberGetValue((CFNumberRef)b, kCFNumberFloat64Type, &value);
        return value == [a doubleValue];
    }
    if([a isKindOfClass:[NSNumber class]])
    {
        if(CFGetTypeID(b) != CFNumberGetTypeID())
            return false;
        bool aIsFloat = CFNumberIsFloatType((CFNumberRef)ca);
        if(aIsFloat != (bool)CFNumberIsFloatType((CFNumberRef)b))
            return false;
        if(aIsFloat)
        {
            double x = 0, y = 0;
            CFNumberGetValue((CFNumberRef)ca, kCFNumberFloat64Type, &x);
            CFNumberGetValue((CFNumberRef)b, kCFNumberFloat64Type, &y);
            return (x == y) && (std::signbit(x) == std::signbit(y));
        }
        return (CFNumberCompare((CFNumberRef)ca, (CFNumberRef)b, NULL) == kCFCompareEqualTo) &&
               [[a description] isEqualToString:[(__bridge id)b description]];
    }
    if([a isKindOfClass:[NSString class]])
        return (CFGetTypeID(b) == CFStringGetTypeID()) && [a isEqualToString:(__bridge NSString *)b];
    if(a == [NSNull null])
        return b == kCFNull;
    if([a isKindOfClass:[NSArray class]])
    {
        if((CFGetTypeID(b) != CFArrayGetTypeID()) || ([a count] != (NSUInteger)CFArrayGetCount((CFArrayRef)b)))
            return false;
        for(NSUInteger i = 0; i < [a count]; i++)
        {
            if(!SameValue(a[i], CFArrayGetValueAtIndex((CFArrayRef)b, (CFIndex)i)))
                return false;
        }
        return true;
    }
    if([a isKindOfClass:[NSDictionary class]])
    {
        if((CFGetTypeID(b) != CFDictionaryGetTypeID()) || ([a count] != (NSUInteger)CFDictionaryGetCount((CFDictionaryRef)b)))
            return false;
        for(NSString *key in a)
        {
            const void *value = CFDictionaryGetValue((CFDictionaryRef)b, (__bridge CFStringRef)key);
            if((value == NULL) || !SameValue(a[key], value))
                return false;
        }
        return true;
    }
    return false;
}

- (void)checkRead:(NSData *)data
{
    for(int isMutable = 0; isMutable <= 1; isMutable++)
    {
        _checks++;
        NSJSONReadingOptions options = NSJSONReadingAllowFragments | (isMutable ? NSJSONReadingMutableContainers : 0);
        id expected = [NSJSONSerialization JSONObjectWithData:data options:options error:NULL];
        CFObj<CFStringRef> error;
        CFObj<CFPropertyListRef> actual( ACFJSONCreatePropertyList((__bridge CFDataRef)data,
                                        isMutable ? kCFPropertyListMutableContainers : kCFPropertyListImmutable, &error) );
        if(!SameValue(expected, actual))
            [self report:[NSString stringWithFormat:@"read%@ [%@]: Foundation %@, ACFJSON %@ (%@)", isMutable ? @" mutable" : @"",
                          ShowBytes(data), ShowObject(expected), ShowObject((__bridge id)actual.Get()), (error != NULL) ? (__bridge NSString *)error.Get() : @""]];
        if((actual == NULL) && (error == NULL))
            [self report:[NSString stringWithFormat:@"read [%@]: failed without an error description", ShowBytes(data)]];
    }
}

// What WritePropertyList got from Foundation: a container through isValidJSONObject, a string,
// null or number root through the fragments option, anything else refused.
static NSData *FoundationWrite(id obj)
{
    @try
    {
        bool isContainer = [obj isKindOfClass:[NSArray class]] || [obj isKindOfClass:[NSDictionary class]];
        if(isContainer && ![NSJSONSerialization isValidJSONObject:obj])
            return nil;
        if(!isContainer && !([obj isKindOfClass:[NSString class]] || (obj == [NSNull null]) || [obj isKindOfClass:[NSNumber class]]))
            return nil;
        NSJSONWritingOptions options = NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys | NSJSONWritingFragmentsAllowed;
        return [NSJSONSerialization dataWithJSONObject:obj options:options error:NULL];
    }
    @catch(NSException *exception)
    {
        return nil;//a non-finite number as a root
    }
}

- (void)checkWrite:(id)obj label:(NSString *)label
{
    _checks++;
    NSData *expected = FoundationWrite(obj);
    ACFJSONWriteStatus status = kACFJSONWriteOK;
    CFObj<CFDataRef> actual( ACFJSONCreateData((__bridge CFPropertyListRef)obj, &status) );
    bool same = ((expected == nil) && (actual == NULL)) ||
                ((expected != nil) && (actual != NULL) && [expected isEqualToData:(__bridge NSData *)actual.Get()]);
    if(!same)
        [self report:[NSString stringWithFormat:@"write %@: Foundation [%@], ACFJSON [%@] status %d", label,
                      expected ? ShowBytes(expected) : @"nil", (actual != NULL) ? ShowBytes((__bridge NSData *)actual.Get()) : @"NULL", (int)status]];
    if((actual == NULL) == (status == kACFJSONWriteOK))
        [self report:[NSString stringWithFormat:@"write %@: status %d does not match the result", label, (int)status]];
}

- (void)checkReadsOfAllStringsOver:(const char *)alphabet maxLength:(size_t)maxLength current:(std::string &)current
{
    [self checkRead:[NSData dataWithBytes:current.data() length:current.size()]];
    if(current.size() == maxLength)
        return;
    for(const char *c = alphabet; *c != 0; c++)
    {
        current.push_back(*c);
        [self checkReadsOfAllStringsOver:alphabet maxLength:maxLength current:current];
        current.pop_back();
    }
}

static NSArray<NSString *> *SampleDocuments(void)
{
    return @[ @"1", @"1.0", @"1e2", @"-0", @"-0.0", @"0.1", @"12345678901234567890", @"123456789012345678901234567890",
              @"9223372036854775807", @"-9223372036854775808", @"9223372036854775808", @"18446744073709551615",
              @"18446744073709551616", @"1.7976931348623157e309", @"1.7976931348623157e308", @"5e-324", @"1.5e-400",
              @"true", @"false", @"null", @"\"\\u00e9\\ud83d\\ude00\"", @"\"\\ud800\"", @"{\"a\":1,\"a\":2}", @"{\"a\":1,\"a\":2,\"a\":3}",
              @"[1,]", @"{\"a\":1,}", @"{\"a\":[1,],}", @"// c\n1", @"\uFEFF[1]", @"\uFEFF1", @"NaN", @"[1] x", @"  [1]  ",
              @"\"a\\/b\"", @"01", @"[1e400]", @"\"a\\u0000b\"", @"[\"\t\"]", @"1E5", @"1.5E+3", @"-01", @".5", @"1.e5",
              @"\"\\u00E9\"", @"[true false]", @"\"\x7F\"", @"{\"b\":{\"c\":[1,{\"d\":null}]},\"a\":\"x\"}",
              @"[1.25,-3,\"s\",true,null,{}]", @"\"\\b\\f\\n\\r\\t\\\"\\\\\"", @"\"\u00e9\u65e5\"" ];
}

// Every input of up to 5 characters over the characters JSON syntax turns on: accept or refuse
// exactly what Foundation does, and read the same values (about a million comparisons).
- (void)testReadingAcceptsAndRefusesWhatFoundationDoes
{
    std::string current;
    [self checkReadsOfAllStringsOver:"[]{}\",:1-.e t" maxLength:5 current:current];
    [self assertNoMismatches];
}

// Number types, duplicate keys, escapes, byte order marks and the UTF-16 and UTF-32 forms of each sample.
- (void)testReadingSampleDocumentsInEveryEncoding
{
    const NSStringEncoding encodings[] = { NSUTF8StringEncoding, NSUTF16LittleEndianStringEncoding, NSUTF16BigEndianStringEncoding,
                                           NSUTF16StringEncoding, NSUTF32LittleEndianStringEncoding, NSUTF32BigEndianStringEncoding,
                                           NSUTF32StringEncoding };
    for(NSString *document in SampleDocuments())
    {
        for(NSStringEncoding encoding : encodings)
            [self checkRead:[document dataUsingEncoding:encoding]];
    }

    const char *odd[] = { "1\0", "\xEF\xBB\xBF", "\xFF\xFE" "1\0", "\"\xE9\"", "\xC3\x28", "\0\0\0" "1", "1\0" "2\0",
                          "\0\0\xFE\xFF\0\0\0" "1", "\xFE\xFF\0[\0" "1\0]" };
    const size_t oddLength[] = { 2, 3, 4, 3, 2, 4, 4, 8, 8 };
    for(size_t i = 0; i < sizeof(oddLength) / sizeof(oddLength[0]); i++)
        [self checkRead:[NSData dataWithBytes:odd[i] length:oddLength[i]]];
    [self assertNoMismatches];
}

// A value may be nested in at most 512 containers, an empty innermost array one deeper.
- (void)testReadingNestingLimit
{
    for(size_t depth = 510; depth <= 515; depth++)
    {
        std::string emptyArrays = std::string(depth, '[') + std::string(depth, ']');
        [self checkRead:[NSData dataWithBytes:emptyArrays.data() length:emptyArrays.size()]];
        std::string arrays = std::string(depth, '[') + "1" + std::string(depth, ']');
        [self checkRead:[NSData dataWithBytes:arrays.data() length:arrays.size()]];
        std::string objects;
        for(size_t i = 0; i < depth; i++)
            objects += "{\"k\":";
        objects += "1" + std::string(depth, '}');
        [self checkRead:[NSData dataWithBytes:objects.data() length:objects.size()]];
    }
    [self assertNoMismatches];
}

// Every UTF-16 unit as a one-character string, as a value and as a key: escapes, raw UTF-8,
// and lone surrogates refused.
- (void)testWritingEveryCharacter
{
    for(unsigned c = 0; c < 0x10000; c++)
    {
        unichar unit = (unichar)c;
        NSString *s = [NSString stringWithCharacters:&unit length:1];
        [self checkWrite:s label:[NSString stringWithFormat:@"char %04x", c]];
        [self checkWrite:@{s: @1} label:[NSString stringWithFormat:@"key %04x", c]];
    }
    unichar pair[] = {0xD83D, 0xDE00};
    unichar reversed[] = {0xDE00, 0xD83D};
    [self checkWrite:@[[NSString stringWithCharacters:pair length:2]] label:@"surrogate pair"];
    [self checkWrite:@[[NSString stringWithCharacters:reversed length:2]] label:@"reversed pair"];
    [self assertNoMismatches];
}

// Numbers of every CF type, key order, layout of nested and empty containers, values JSON cannot hold.
- (void)testWritingNumbersKeysAndLayout
{
    NSArray *numbers = @[ @0.1, @1.5, @1e20, @1e-7, @(1.0 / 3.0), @100.0, @-0.0, @0.0, @(INT64_MIN), @(INT64_MAX), @3.0f, @0.1f,
                          @1e16, @1e15, @1e21, @1e-5, @1e-4, @5e-324, @1.7976931348623157e308, @2.5e-10, @((short)-7), @((char)65),
                          @((unsigned char)200), @4000000000U, @YES, @NO, @(NAN), @(INFINITY), @(-INFINITY) ];
    for(NSNumber *number in numbers)
    {
        [self checkWrite:number label:[NSString stringWithFormat:@"number %@", number]];
        [self checkWrite:@[number] label:[NSString stringWithFormat:@"number in array %@", number]];
    }

    // integers above INT64_MAX as CF's own property list reader makes them
    NSData *plist = [@"<plist version=\"1.0\"><array><integer>18446744073709551615</integer><integer>9223372036854775808</integer>"
                      "<integer>-9223372036854775808</integer></array></plist>" dataUsingEncoding:NSUTF8StringEncoding];
    id bigIntegers = [NSPropertyListSerialization propertyListWithData:plist options:0 format:NULL error:NULL];
    XCTAssertNotNil(bigIntegers);
    [self checkWrite:bigIntegers label:@"big integers from a property list"];

    NSArray *keys = @[ @"a", @"A", @"aa", @"b", @"B", @"_", @"1", @"10", @"9", @"", @" ", @"\u00e9", @"e\u0301", @"\U0001F600",
                       @"\uFFFF", @"z", @"Z", @"\u00c5", @"\u212b", @"ab", @"aB", @"a b", @"x2", @"x10", @"x02" ];
    NSMutableDictionary *many = [NSMutableDictionary dictionary];
    for(NSUInteger i = 0; i < keys.count; i++)
        many[keys[i]] = @(i);
    [self checkWrite:many label:@"key order"];

    // keys mixing digits of several scripts, for which the key comparison is not transitive, so
    // only Foundation's own sort algorithm gives its order
    const unichar mixedDigits[] = { '0', '1', '9', 'a', ' ', 0x0301, 0x200B, 0xFF11, 0x0661, 0x00B2 };
    const NSUInteger mixedCount = sizeof(mixedDigits) / sizeof(mixedDigits[0]);
    NSMutableDictionary *mixed = [NSMutableDictionary dictionary];
    for(NSUInteger first = 0; first < mixedCount; first++)
        for(NSUInteger second = 0; second < mixedCount; second++)
            for(NSUInteger third = 0; third < mixedCount; third++)
            {
                unichar chars[] = { mixedDigits[first], mixedDigits[second], mixedDigits[third] };
                mixed[[NSString stringWithCharacters:chars length:3]] = @0;
            }
    [self checkWrite:mixed label:@"key order with mixed-script digits"];
    [self checkWrite:@{@"b": @{@"y": @[], @"x": @{}}, @"a": @[@[@[]], @{}], @"c": [NSNull null]} label:@"nested empties"];
    [self checkWrite:@[] label:@"empty array"];
    [self checkWrite:@{} label:@"empty dictionary"];
    [self checkWrite:@"x/y" label:@"string root"];
    [self checkWrite:[NSNull null] label:@"null root"];
    [self checkWrite:@[[NSDate date]] label:@"date"];
    [self checkWrite:@[[NSData data]] label:@"data"];
    [self checkWrite:@{@1: @2} label:@"number key"];
    [self checkWrite:[NSDate date] label:@"date root"];
    [self checkWrite:@{@"a": @[@{@"b": [NSData data]}]} label:@"nested data"];
    [self assertNoMismatches];
}

// What Foundation read from the sample documents, written by both.
- (void)testWritingWhatFoundationRead
{
    for(NSString *document in SampleDocuments())
    {
        id obj = [NSJSONSerialization JSONObjectWithData:[document dataUsingEncoding:NSUTF8StringEncoding]
                                                 options:NSJSONReadingAllowFragments error:NULL];
        // an NSDecimalNumber has no CF counterpart (ACFJSON.h), and never reaches the writer
        // from OMC's own code
        if((obj != nil) && ![obj isKindOfClass:[NSDecimalNumber class]])
            [self checkWrite:obj label:[NSString stringWithFormat:@"round trip %@", document]];
    }
    [self assertNoMismatches];
}

// Read, write, read again ends where Foundation's own round trip ends. Not always where it
// started: Foundation writes the double 1.0 as "1", which reads back as an integer, and so does ACFJSON.
- (void)testRoundTripEndsWhereFoundationsDoes
{
    for(NSString *document in SampleDocuments())
    {
        NSData *data = [document dataUsingEncoding:NSUTF8StringEncoding];
        id foundationFirst = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:NULL];
        if((foundationFirst == nil) || [foundationFirst isKindOfClass:[NSDecimalNumber class]])
            continue;
        NSData *foundationWritten = FoundationWrite(foundationFirst);
        id expected = (foundationWritten != nil) ? [NSJSONSerialization JSONObjectWithData:foundationWritten
                                                                                    options:NSJSONReadingAllowFragments error:NULL] : nil;
        _checks++;
        CFObj<CFPropertyListRef> first( ACFJSONCreatePropertyList((__bridge CFDataRef)data, kCFPropertyListImmutable, NULL) );
        CFObj<CFDataRef> written( (first != NULL) ? ACFJSONCreateData(first, NULL) : NULL );
        CFObj<CFPropertyListRef> second( (written != NULL) ? ACFJSONCreatePropertyList(written, kCFPropertyListImmutable, NULL) : NULL );
        if(!SameValue(expected, second))
            [self report:[NSString stringWithFormat:@"round trip of %@: Foundation %@, ACFJSON %@", document,
                          ShowObject(expected), ShowObject((__bridge id)second.Get())]];
    }
    [self assertNoMismatches];
}

@end

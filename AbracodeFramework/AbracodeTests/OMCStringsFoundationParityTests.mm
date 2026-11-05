//
//  OMCStringsFoundationParityTests.mm
//  AbracodeTests
//
//  OMCStrings.cpp reimplements, in plain CF and POSIX so it builds on Linux, four functions that
//  used to call NSString: tilde expansion, path extension, lowercasing and percent escaping.
//  Common/ACFPath.cpp holds the path rules, and also stringByDeletingPathExtension, which
//  ACFPropertyList uses to find an applet's command file.
//  Scripts see their results (paths, the escaping modes of special words), so they must keep
//  returning exactly what Foundation returns on macOS. Foundation is the oracle here: every test
//  compares the C++ function with the NSString call it replaced, over exhaustive inputs.
//
//  The functions are not exported from Abracode.framework, so the sources compile directly into
//  this test bundle, as OMCEngineTempDir.h does for its tests.
//
#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#include <string>
#include <vector>

#include "../OMCStrings.cpp"
#include "ACFType.cp"
#include "ACFPath.h"//compiled by OMCTestsACFPath.cpp

@interface OMCStringsFoundationParityTests : XCTestCase
@end

@implementation OMCStringsFoundationParityTests
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

static NSString *DescribeString(CFStringRef s)
{
    if(s == NULL)
        return @"(NULL)";
    NSString *ns = (__bridge NSString *)s;
    NSMutableString *out = [NSMutableString stringWithString:@"["];
    for(NSUInteger i = 0; i < ns.length; i++)
    {
        unichar c = [ns characterAtIndex:i];
        if((c >= 0x20) && (c < 0x7F))
            [out appendFormat:@"%C", c];
        else
            [out appendFormat:@"\\u%04X", c];
    }
    [out appendString:@"]"];
    return out;
}

// Takes ownership of both results.
- (void)compare:(NSString *)what input:(CFStringRef)input foundation:(CFStringRef)expected ported:(CFStringRef)actual
{
    CFObj<CFStringRef> expectedOwner(expected);
    CFObj<CFStringRef> actualOwner(actual);
    _checks++;
    bool same = ((expected == NULL) && (actual == NULL)) ||
                ((expected != NULL) && (actual != NULL) && (CFStringCompare(expected, actual, 0) == kCFCompareEqualTo));
    if(!same)
    {
        _mismatches++;
        if(_firstMismatches.count < 20)
            [_firstMismatches addObject:[NSString stringWithFormat:@"%@ %@: Foundation %@, OMCStrings %@",
                                         what, DescribeString(input), DescribeString(expected), DescribeString(actual)]];
    }
}

- (void)checkPaths:(CFStringRef)s
{
    NSString *ns = (__bridge NSString *)s;
    [self compare:@"tilde" input:s foundation:(CFStringRef)CFBridgingRetain(ns.stringByExpandingTildeInPath)
           ported:CreatePathByExpandingTilde(s)];
    [self compare:@"extension" input:s foundation:(CFStringRef)CFBridgingRetain(ns.pathExtension)
           ported:CopyFilenameExtension(s)];
    // ACFPropertyList's CopyCommandFileURLInBundle relies on this one
    [self compare:@"deleting extension" input:s foundation:(CFStringRef)CFBridgingRetain(ns.stringByDeletingPathExtension)
           ported:ACFPathCreateDeletingExtension(s)];
}

- (void)checkCaseAndEscapes:(CFStringRef)s
{
    NSString *ns = (__bridge NSString *)s;
    [self compare:@"lowercase" input:s foundation:(CFStringRef)CFBridgingRetain(ns.lowercaseString)
           ported:CreateLowercaseString(s)];
    NSString *query = [ns stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    [self compare:@"percent" input:s foundation:(CFStringRef)CFBridgingRetain(query)
           ported:CreateStringByAddingPercentEscapes(s, false)];
    NSString *all = [ns stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
    [self compare:@"percentAll" input:s foundation:(CFStringRef)CFBridgingRetain(all)
           ported:CreateStringByAddingPercentEscapes(s, true)];
}

- (void)assertNoMismatches
{
    XCTAssertGreaterThan(_checks, 0);
    XCTAssertEqual(_mismatches, 0L, @"%ld of %ld results differ from Foundation; first ones:\n%@",
                   _mismatches, _checks, [_firstMismatches componentsJoinedByString:@"\n"]);
}

static std::vector<UniChar> Characters(NSString *s)
{
    std::vector<UniChar> v(s.length);
    if(s.length > 0)
        [s getCharacters:v.data() range:NSMakeRange(0, s.length)];
    return v;
}

static CFStringRef CreateFromCharacters(const std::vector<UniChar> &chars)
{
    return CFStringCreateWithCharacters(kCFAllocatorDefault, chars.data(), (CFIndex)chars.size());
}

// Every string of up to inMaxLength characters from inAlphabet, after inPrefix.
- (void)checkPathsWithPrefix:(const std::vector<UniChar> &)inPrefix alphabet:(const std::vector<UniChar> &)inAlphabet
                   maxLength:(size_t)inMaxLength current:(std::vector<UniChar> &)ioCurrent
{
    std::vector<UniChar> whole = inPrefix;
    whole.insert(whole.end(), ioCurrent.begin(), ioCurrent.end());
    CFObj<CFStringRef> s( CreateFromCharacters(whole) );
    [self checkPaths:s];
    if(ioCurrent.size() == inMaxLength)
        return;
    for(UniChar c : inAlphabet)
    {
        ioCurrent.push_back(c);
        [self checkPathsWithPrefix:inPrefix alphabet:inAlphabet maxLength:inMaxLength current:ioCurrent];
        ioCurrent.pop_back();
    }
}

// Every Unicode scalar, alone and between two ASCII letters.
- (void)testCaseAndEscapesMatchFoundationForEveryScalar
{
    for(UTF32Char c = 0; c < 0x110000; c++)
    {
        if((c >= 0xD800) && (c <= 0xDFFF))
            continue;
        UniChar pair[2];
        CFIndex count = CFStringGetSurrogatePairForLongCharacter(c, pair) ? 2 : 1;
        if(count == 1)
            pair[0] = (UniChar)c;
        std::vector<UniChar> chars = {'A'};
        chars.insert(chars.end(), pair, pair + count);
        chars.push_back('b');
        CFObj<CFStringRef> mixed( CreateFromCharacters(chars) );
        [self checkCaseAndEscapes:mixed];
        CFObj<CFStringRef> alone( CFStringCreateWithCharacters(kCFAllocatorDefault, pair, count) );
        [self checkCaseAndEscapes:alone];
    }
    [self assertNoMismatches];
}

// Context-dependent case mapping, lone surrogates (percent escaping gives NULL), empty and NULL input.
- (void)testSpecialStringsMatchFoundation
{
    NSArray<NSString *> *specials = @[ @"", @"\u03A3", @"\u039F\u03A3", @"\u039F\u03A3 \u039F", @"\u0130", @"I\u0307",
                                       @"\u1E9E", @"\u00DF", @"\uFB03", @"I\u0130\u0131", @"\U0001F600x", @"e\u0301t\u00E9",
                                       @"a=b&c=d e#f%g", @"https://example.com/a b?q=1&r=[2]",
                                       @"Za\u017C\u00F3\u0142\u0107 g\u0119\u015Bl\u0105 ja\u017A\u0144" ];
    for(NSString *s in specials)
    {
        [self checkPaths:(__bridge CFStringRef)s];
        [self checkCaseAndEscapes:(__bridge CFStringRef)s];
    }

    const UniChar loneHigh[] = {'a', 0xD800, 'b'};
    const UniChar loneLow[] = {'a', 0xDC00};
    const UniChar reversedPair[] = {0xDC00, 0xD800};
    // a user name with no UTF-8 form means the current user; one cut to "" by a NUL is unknown
    const UniChar loneInUserName[] = {'~', 'r', 'o', 'o', 't', 0xD800, '/', 'b'};
    const UniChar nulUserName[] = {'~', 0, '/', 'a'};
    const UniChar *broken[] = {loneHigh, loneLow, reversedPair, loneInUserName, nulUserName};
    const CFIndex brokenLengths[] = {3, 2, 2, 8, 4};
    for(size_t i = 0; i < 5; i++)
    {
        CFObj<CFStringRef> s( CFStringCreateWithCharacters(kCFAllocatorDefault, broken[i], brokenLengths[i]) );
        [self checkPaths:s];
        [self checkCaseAndEscapes:s];
    }

    XCTAssertTrue(CreatePathByExpandingTilde(NULL) == NULL);
    XCTAssertTrue(CopyFilenameExtension(NULL) == NULL);
    XCTAssertTrue(CreateLowercaseString(NULL) == NULL);
    XCTAssertTrue(ACFPathCreateDeletingExtension(NULL) == NULL);
    XCTAssertTrue(CreateStringByAddingPercentEscapes(NULL, false) == NULL);
    [self assertNoMismatches];
}

// Every short string over the characters the path rules depend on, alone and after "~", "~user"
// (known and unknown) and slash prefixes.
- (void)testPathsMatchFoundationForAllShortStrings
{
    std::vector<UniChar> current;
    [self checkPathsWithPrefix:{} alphabet:Characters(@"a./ ~\t\u00E9:") maxLength:5 current:current];

    NSString *me = NSUserName();
    NSArray<NSString *> *prefixes = @[ @"~", @"~/", @"~root", @"~root/", @"~nosuchuser_omc", @"~nosuchuser_omc/", @"/", @"//",
                                       [@"~" stringByAppendingString:me] ];
    for(NSString *prefix in prefixes)
        [self checkPathsWithPrefix:Characters(prefix) alphabet:Characters(@"a./ ") maxLength:4 current:current];

    NSArray<NSString *> *real = @[ @"/Users/me/Documents/Report final.pdf", @"~/Library/Application Support/OnMyCommand/x.omc",
                                   @"/tmp/x.tar.gz/", @"\u65E5\u672C\u8A9E.txt", @"..", @"...x", @"....x", @"a...b",
                                   @"x.\u061C", @"x.a\u200Eb", @"x.\u200F", @"x.a\u202A", @"x.\u202E", @"x.\u2066", @"x.\u2069",
                                   @"x.\u2065", @"x.\u206A", @"x.\u2029", @"x\u202E.a" ];
    for(NSString *s in real)
        [self checkPaths:(__bridge CFStringRef)s];
    [self assertNoMismatches];
}

@end

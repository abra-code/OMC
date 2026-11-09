//
//  OMCURLParseParityTests.mm
//  AbracodeTests
//
//  OMCURLParse.cpp replaces NSURLComponents (Linux has none with Apple's rules) for the URLs sent to
//  an applet: whether the string is a URL, its host and its query's items decide what the URL may
//  run (OMCCommandRunner.cpp). Foundation is the oracle: each case compares
//  +[NSURLComponents componentsWithString:], its host and its queryItems with OMCParseURL, over fixed
//  cases (the rules in OMCURLParse.h) and strings generated from the characters that matter.
//
//  OMCURLParse is not exported from Abracode.framework, so it compiles into this bundle.
//

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#include <string>
#include <vector>

#include "../OMCURLParse.cpp"

@interface OMCURLParseParityTests : XCTestCase
@end

@implementation OMCURLParseParityTests

// The host as the runner sees it: exactly when it is plain ASCII; otherwise only whether it is
// "exe" (Foundation turns a non-ASCII host into punycode, which the portable parser does not)
static NSString *HostDescription(NSString *inHost)
{
	if (inHost == nil)
		return @"null";
	BOOL plainASCII = [inHost canBeConvertedToEncoding:NSASCIIStringEncoding] && ([inHost rangeOfString:@"xn--"].location == NSNotFound);
	if (plainASCII)
		return [NSString stringWithFormat:@"[%@]", inHost];
	return ([inHost caseInsensitiveCompare:@"exe"] == NSOrderedSame) ? @"[exe]" : @"<not ascii, not exe>";
}

// One parse as text: "invalid", or the host and the items, so two parses compare as strings
static NSString *FoundationParse(NSString *inURL)
{
	NSURLComponents *components = [NSURLComponents componentsWithString:inURL];
	if (components == nil)
		return @"invalid";
	NSMutableString *description = [NSMutableString stringWithFormat:@"host=%@", HostDescription(components.host)];
	for (NSURLQueryItem *item in components.queryItems)
		[description appendFormat:@" (%@|%@)", item.name ? [NSString stringWithFormat:@"[%@]", item.name] : @"null",
								  item.value ? [NSString stringWithFormat:@"[%@]", item.value] : @"null"];
	return description;
}

static NSString *PartDescription(CFTypeRef inPart)
{
	if ((inPart == nullptr) || (CFGetTypeID(inPart) != CFStringGetTypeID()))
		return @"null";
	return [NSString stringWithFormat:@"[%@]", (__bridge NSString *)inPart];
}

static NSString *PortableParse(NSString *inURL)
{
	CFObj<CFStringRef> host;
	CFObj<CFArrayRef> items;
	if (!OMCParseURL((__bridge CFStringRef)inURL, host, items))
		return @"invalid";
	NSMutableString *description = [NSMutableString stringWithFormat:@"host=%@", HostDescription((__bridge NSString *)host.Get())];
	CFIndex count = (items != nullptr) ? CFArrayGetCount(items) : 0;
	for (CFIndex i = 0; i < count; i++)
	{
		CFArrayRef item = (CFArrayRef)CFArrayGetValueAtIndex(items, i);
		[description appendFormat:@" (%@|%@)", PartDescription(CFArrayGetValueAtIndex(item, 0)), PartDescription(CFArrayGetValueAtIndex(item, 1))];
	}
	return description;
}

// The known differences (OMCURLParse.h): a host with a non-ASCII character (Foundation applies
// the rules of internationalized domain names) or a bracketed one. Only the host is looked at, so
// a user or port is still compared; the authority is scanned by character because
// rangeOfCharacterFromSet: steps over the character after a lone surrogate.
static BOOL HasKnownDifference(NSString *inURL)
{
	NSRange slashes = [inURL rangeOfString:@"//"];
	if (slashes.location == NSNotFound)
		return NO;
	NSUInteger end = NSMaxRange(slashes);
	NSUInteger hostStart = end;
	for (; end < inURL.length; end++)
	{
		unichar c = [inURL characterAtIndex:end];
		if ((c == '/') || (c == '?') || (c == '#'))
			break;
		if (c == '@')
			hostStart = end + 1;
	}
	NSString *host = [inURL substringWithRange:NSMakeRange(hostStart, end - hostStart)];
	if ([host hasPrefix:@"["])
		return YES;
	NSRange colon = [host rangeOfString:@":"];
	if (colon.location != NSNotFound)
		host = [host substringToIndex:colon.location];
	return ![host canBeConvertedToEncoding:NSASCIIStringEncoding];
}

// Compares every case and fails once with the first differences
- (void)assertParityOver:(NSArray<NSString *> *)inCases
{
	NSMutableArray<NSString *> *differences = [NSMutableArray array];
	NSUInteger compared = 0;
	for (NSString *url in inCases)
	{
		if (HasKnownDifference(url))
			continue;
		compared++;
		NSString *expected = FoundationParse(url);
		NSString *actual = PortableParse(url);
		if (![expected isEqualToString:actual])
			[differences addObject:[NSString stringWithFormat:@"'%@': Foundation %@, OMCParseURL %@", url, expected, actual]];
	}
	XCTAssertGreaterThan(compared, inCases.count * 3 / 4, @"most cases are compared, not skipped as known differences");
	XCTAssertEqual(differences.count, 0u, @"%lu of %lu differ, the first: %@", (unsigned long)differences.count,
				   (unsigned long)inCases.count, [[differences subarrayWithRange:NSMakeRange(0, MIN(differences.count, (NSUInteger)15))] componentsJoinedByString:@"\n"]);
}

- (void)testTheRulesCases
{
	[self assertParityOver:@[
		@"omc://exe?commandID=a&text=hello%20world%26more", @"omc://exe?commandID=a&text=hello world", @"omc://exe?text=a+b",
		@"omc://exe?text=%zz", @"omc://exe?text=%E9", @"omc://exe?text=%C3%A9", @"omc://exe?a&b=&=c&&d=1=2",
		@"omc://EXE?x=1", @"omc://e%78e?x=1", @"omc://exe", @"omc:exe?x=1", @"omc:///path?x=1", @"omc://exe?x=<>",
		@"omc://exe?x=\"q\"", @"omc://exe?x=a#frag", @"omc://exe?x=a|b", @"omc://exe?x={}", @"omc://exe?x=\u00e9",
		@"omc://ex e?x=1", @"omc://exe:80?x=1", @"omc://user@exe?x=1", @"omc://[::1]?x=1", @"1omc://exe?x=1", @"://exe?x=1",
		@"omc://exe?x=%", @"omc://exe?x=%2", @"omc://exe?x=a%2Bb", @"omc://exe/?commandID=a", @"omc://exe?commandID=a;b",
		@"omc://exe?x=\\", @"omc://exe?x=^", @"omc://exe?x=`", @"omc://%zz?x=1", @"omc://exe?", @"omc://exe?&",
		@"omc://\u00e9?x=1", @"omc://ex%41?x=1", @"omc://a:b@exe?x=1", @"omc://exe:abc?x=1", @"omc://exe:?x=1", @"//exe?x=1",
		@"omc://exe?x=1?y=2", @"omc://ex%C3%A9e?x=1", @"omc://ex%E9e?x=1", @"omc://[zz]?x=1", @"a b?x=1", @"omc:/ /x?y=1",
		@"omc://exe/a b?x=1", @"omc://e_x~e?x=1", @"omc://e!x$e?x=1", @"omc://exe@@h?x=1", @"omc://a@b@c?x=1",
		@"omc://[::1]:8?x=1", @"omc://[::1]x?x=1", @"OMC://exe?x=1", @"o+.-:x?y=1", @"omc://exe?x=%41%42", @"omc://ex[e?x=1",
		@"omc://exe?x=1#a#b", @"omc://ex%20e?x=1", @"omc://%41?x=1", @"omc://exe%?x=1", @"omc:?x", @"omc://e<e?x=1",
		@"omc://exe\\x?x=1", @"omc://exe?x=\t", @"omc://exe?x=\n",
		// The whole string is parsed, past a NUL; "%00" stays in a host; a lone surrogate is U+FFFD
		@"omc://exe?commandID=%66oo&x=\0", @"omc://exe?commandID=foo\0&commandID=bar", @"omc://ex%65\0?commandID=foo",
		@"omc://exe/\0?commandID=%66oo", @"omc:/\0/exe?commandID=x", @"omc://exe%00?x=1", @"omc://e%00x%41?x=1",
		[NSString stringWithFormat:@"omc://exe?commandID=x%C", (unichar)0xD800],
		[NSString stringWithFormat:@"omc://exe?commandID=x#%C", (unichar)0xDC00],
		[NSString stringWithFormat:@"omc://exe/%C?commandID=x", (unichar)0xD800],
		[NSString stringWithFormat:@"%Comc://exe?commandID=x", (unichar)0xD800],
		// A user or port is compared even when it is not ASCII or holds a bracket
		@"omc://[@exe?commandID=x", @"omc://\u00e9@exe?commandID=x", @"omc://exe:\u0668\u0660?commandID=x",
	]];
}

// URLs put together from the pieces that matter, from a fixed seed so a failure repeats. Each
// starts with a scheme, as every URL the system sends an applet does (it routes them by scheme).
- (void)testGeneratedStrings
{
	NSArray<NSString *> *pieces = @[
		@"//", @"exe", @"EXE", @"x", @"1", @"a b", @"?", @"&", @"=", @"#", @"@", @":", @"/", @"[", @"]",
		@"[::1]", @"%", @"%4", @"%41", @"%2B", @"%26", @"%3D", @"%E9", @"%C3%A9", @"%zz", @"+", @"<", @">", @"\"", @"|",
		@"\\", @"^", @"`", @"{", @"}", @";", @"!", @"~", @"_", @"-", @".", @"*", @"'", @"(", @")", @",", @"$", @"\u00e9", @"\u2603",
		@"\t", @" ", @"commandID", @"text", @"file", @"80", @"user",
		@"\0", @"%00", @"%3F", @"%23", @"%2F", @"%40", @"%3A", @"\u0668", [NSString stringWithFormat:@"%C", (unichar)0xD800],
	];
	uint64_t state = 0x9E3779B97F4A7C15ULL;
	auto next = [&state]() -> uint64_t {
		state ^= state << 13;
		state ^= state >> 7;
		state ^= state << 17;
		return state;
	};
	NSMutableArray<NSString *> *cases = [NSMutableArray array];
	for (int i = 0; i < 20000; i++)
	{
		NSMutableString *url = [NSMutableString stringWithString:((next() % 4) != 0) ? @"omc://" : @"omc:"];
		int count = 1 + (int)(next() % 9);
		for (int j = 0; j < count; j++)
			[url appendString:pieces[next() % pieces.count]];
		[cases addObject:url];
	}
	[self assertParityOver:cases];
}

@end

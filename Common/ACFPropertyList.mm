#include "ACFPropertyList.h"
#include "CFObj.h"
#import <Foundation/Foundation.h>
#include <math.h>//isfinite, for the non-finite number check below

// What the file name extension says about the format. Only ".json" and ".plist" are
// meaningful; everything else is unknown and leaves the decision to the content.
static ACFPropertyListFormat FormatFromExtension(CFURLRef url)
{
    if (url == NULL)
        return kACFPropertyListFormat_unknown;

    CFObj<CFStringRef> ext(::CFURLCopyPathExtension(url));
    if (ext == NULL)
        return kACFPropertyListFormat_unknown;

    if (::CFStringCompare(ext, CFSTR("json"), kCFCompareCaseInsensitive) == kCFCompareEqualTo)
        return kACFPropertyListFormat_json;

    if (::CFStringCompare(ext, CFSTR("plist"), kCFCompareCaseInsensitive) == kCFCompareEqualTo)
        return kACFPropertyListFormat_xml;

    return kACFPropertyListFormat_unknown;
}

// What the first few bytes say about the format. Returns unknown rather than guessing when
// nothing recognizable is there; the caller falls back to trying both parsers.
static ACFPropertyListFormat FormatFromContent(NSData *data)
{
    if (data == nil)
        return kACFPropertyListFormat_unknown;

    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSUInteger length = data.length;
    if ((bytes == NULL) || (length == 0))
        return kACFPropertyListFormat_unknown;

    if ((length >= 8) && (memcmp(bytes, "bplist00", 8) == 0))
        return kACFPropertyListFormat_binary;

    NSUInteger i = 0;
    if ((length >= 3) && (bytes[0] == 0xEF) && (bytes[1] == 0xBB) && (bytes[2] == 0xBF))
        i = 3;//UTF-8 BOM

    while ((i < length) && ((bytes[i] == ' ') || (bytes[i] == '\t') || (bytes[i] == '\n') || (bytes[i] == '\r')))
        i++;

    if (i >= length)
        return kACFPropertyListFormat_unknown;

    switch (bytes[i])
    {
        case '<': // an XML declaration or a <plist> element
            return kACFPropertyListFormat_xml;

        //A JSON array or a quoted string. Neither can open an old-style plist, so these
        //two are unambiguous.
        case '[': case '"':
            return kACFPropertyListFormat_json;

        //A JSON object - but an old-style OpenStep dictionary opens with '{' too, so this
        //answer is a preference, not a certainty. The reader falls back when it is wrong.
        case '{':
            return kACFPropertyListFormat_json;

        //Deliberately NOT sniffed: a bare true/false/null/number at the root. Each is a
        //legal JSON fragment and equally a legal unquoted old-style plist string, and the
        //old-style reading is what this file has always returned for them. Calling them
        //JSON would silently change the type "get type" reports for a one-word file -
        //"true" becoming a bool, "42" an integer - which is a behavior change nobody asked
        //for, on the one input where the format genuinely cannot be told. They still parse:
        //the plist reader takes them, as it always did.
    }

    return kACFPropertyListFormat_unknown;
}

static CFPropertyListRef CreateFromJSONData(NSData *data, CFPropertyListMutabilityOptions mutabilityOptions, NSError **outError)
{
    NSJSONReadingOptions options = NSJSONReadingAllowFragments;
    if (mutabilityOptions != kCFPropertyListImmutable)
        options |= NSJSONReadingMutableContainers;

    id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:options error:outError];
    if (jsonObject == nil)
        return NULL;

    return (__bridge_retained CFTypeRef)jsonObject;
}

static CFPropertyListRef CreateFromPlistData(NSData *data, CFPropertyListMutabilityOptions mutabilityOptions)
{
    return ::CFPropertyListCreateWithData(kCFAllocatorDefault, (__bridge CFDataRef)data, mutabilityOptions, NULL, NULL);
}

CFPropertyListRef CreatePropertyListAndFormat(CFURLRef plistURL, CFPropertyListMutabilityOptions mutabilityOptions,
												ACFPropertyListFormat *outFormat)
{
    ACFPropertyListFormat extFormat = FormatFromExtension(plistURL);

    //The fallback answer, used for a file that does not exist or does not parse: whatever the
    //extension implies, and XML when it implies nothing. Never "unknown", so a caller can hand
    //it straight to WritePropertyList when creating the file.
    ACFPropertyListFormat fallbackFormat = (extFormat != kACFPropertyListFormat_unknown) ? extFormat : kACFPropertyListFormat_xml;
    if (outFormat != NULL)
        *outFormat = fallbackFormat;

    if (plistURL == NULL)
        return NULL;

    NSData *data = [NSData dataWithContentsOfURL:(__bridge NSURL *)plistURL];
    if (data == nil)
        return NULL;//nothing to sniff; the caller keeps the extension-derived format

    ACFPropertyListFormat contentFormat = FormatFromContent(data);

    //The extension decides the family whenever it says anything, so no existing .json or
    //.plist behavior changes. Content decides only for an extension we do not know - and,
    //within the plist family, refines XML to binary so a write-back preserves what was read.
    ACFPropertyListFormat format = extFormat;
    if (extFormat == kACFPropertyListFormat_unknown)
        format = contentFormat;
    else if ((extFormat == kACFPropertyListFormat_xml) && (contentFormat == kACFPropertyListFormat_binary))
        format = kACFPropertyListFormat_binary;

    CFPropertyListRef result = NULL;
    if (format == kACFPropertyListFormat_json)
    {
        NSError *jsonError = nil;
        result = CreateFromJSONData(data, mutabilityOptions, &jsonError);
        if (result == NULL)
        {
            if (extFormat == kACFPropertyListFormat_json)
            {//the name promised JSON, so a parse failure is the whole answer
                fprintf(stderr, "Error: failed to parse JSON: %s\n", jsonError.localizedDescription.UTF8String);
            }
            else
            {//it only looked like JSON - an old-style plist dictionary opens with '{' as well
                result = CreateFromPlistData(data, mutabilityOptions);
                if (result != NULL)
                    format = kACFPropertyListFormat_xml;
                else
                    fprintf(stderr, "Error: failed to parse JSON: %s\n", jsonError.localizedDescription.UTF8String);
            }
        }
    }
    else
    {
        result = CreateFromPlistData(data, mutabilityOptions);
        if (result != NULL)
        {
            if (format != kACFPropertyListFormat_binary)
                format = kACFPropertyListFormat_xml;//XML, old-style, or anything else CF understood
        }
        else if (extFormat == kACFPropertyListFormat_unknown)
        {//unknown extension and unrecognizable content: JSON is the remaining candidate
            NSError *jsonError = nil;
            result = CreateFromJSONData(data, mutabilityOptions, &jsonError);
            if (result != NULL)
                format = kACFPropertyListFormat_json;
        }
    }

    if (result == NULL)
        format = fallbackFormat;

    if (outFormat != NULL)
        *outFormat = format;

    return result;
}

CFPropertyListRef CreatePropertyList(CFURLRef plistURL, CFPropertyListMutabilityOptions mutabilityOptions)
{
    return CreatePropertyListAndFormat(plistURL, mutabilityOptions, NULL);
}

CFURLRef CopyCommandFileURLInBundle(CFBundleRef inBundle, CFStringRef inFileName)
{
    if (inBundle == NULL)
        return NULL;

    NSString *baseName = nil;
    if (inFileName != NULL)
        baseName = [(__bridge NSString *)inFileName stringByDeletingPathExtension];
    if (baseName.length == 0)
        baseName = @"Command";

    // JSON preferred, plist fallback — an applet may ship either format.
    for (NSString *ext in @[@"json", @"plist"])
    {
        CFURLRef url = CFBundleCopyResourceURL(inBundle, (__bridge CFStringRef)baseName, (__bridge CFStringRef)ext, NULL);
        if (url != NULL)
            return url; // +1, caller releases
    }
    return NULL;
}

//A CFBoolean and a non-finite CFNumber both bridge to NSNumber, so an
//isKindOfClass check alone lets NaN and +/-infinity into the scalar-fragment
//path - where dataWithJSONObject THROWS exactly as it does for a container
//holding one, and the branch that reports "a non-finite number" by name can
//never see it. JSON has no spelling for either value, so they belong with the
//other unrepresentable types.
static bool
ACFIsJSONWritableNumber(id numberObject)
{
    CFNumberRef numberRef = (__bridge CFNumberRef)numberObject;
    if (CFGetTypeID(numberRef) == CFBooleanGetTypeID())
        return true;//true and false are perfectly good JSON
    if (!CFNumberIsFloatType(numberRef))
        return true;//an integer cannot be non-finite

    double value = 0.0;
    if (!CFNumberGetValue(numberRef, kCFNumberDoubleType, &value))
        return false;
    return isfinite(value);
}

bool
WritePropertyList(CFPropertyListRef propertyList, CFURLRef plistURL, ACFPropertyListFormat plistFormat)
{
    if ((propertyList == NULL) || (plistURL == NULL))
        return false;

    ACFPropertyListFormat format = plistFormat;
    if (format == kACFPropertyListFormat_unknown)
    {
        format = FormatFromExtension(plistURL);
        if (format == kACFPropertyListFormat_unknown)
            format = kACFPropertyListFormat_xml;//a new file with an extension we do not know
    }

	bool isOK = false;
    if (format == kACFPropertyListFormat_json)
    {
        id jsonObject = (__bridge id)propertyList;
        NSError* error = nil;
        NSData* jsonData = nil;

        if ([NSJSONSerialization isValidJSONObject:jsonObject])
        {
            jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
        }
        else if ([jsonObject isKindOfClass:[NSString class]] ||
                 [jsonObject isKindOfClass:[NSNull class]] ||
                 ([jsonObject isKindOfClass:[NSNumber class]] && ACFIsJSONWritableNumber(jsonObject)))
        {
            // Scalar fragment root: NSJSONWritingFragmentsAllowed = (1UL << 2), available macOS 13+
            NSJSONWritingOptions fragOpts = NSJSONWritingPrettyPrinted | (NSJSONWritingOptions)(1UL << 2);
            jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject
                                                       options:fragOpts
                                                         error:&error];
        }
        else
        {
            // isValidJSONObject is false for a scalar root, which the branch above
            // handles - and also, at any depth, for a type JSON has no spelling
            // for: CFData, CFDate, a non-finite number, or a dictionary keyed by
            // anything but a string. Those must be reported here, because
            // dataWithJSONObject THROWS on them rather than returning nil, so the
            // nil check below never runs and an uncaught NSInvalidArgumentException
            // takes the process down. Reachable through
            // "plister insert X copy src.plist /Data dest.json /".
            fprintf(stderr, "Error: this value has no JSON representation (data, a date, a non-finite number, or a non-string dictionary key)\n");
            return false;
        }

        if (jsonData == nil)
        {
            fprintf(stderr, "Error: failed to serialize JSON: %s\n", error.localizedDescription.UTF8String);
            return false;
        }
        isOK = (bool)[jsonData writeToURL:(__bridge NSURL *)plistURL
                                  options:NSDataWritingAtomic
                                    error:NULL];
        return isOK;
    }

    CFPropertyListFormat cfFormat = (format == kACFPropertyListFormat_binary) ? kCFPropertyListBinaryFormat_v1_0
                                                                             : kCFPropertyListXMLFormat_v1_0;
    CFDataRef plistData = ::CFPropertyListCreateData(kCFAllocatorDefault, propertyList, cfFormat, 0, NULL);
    if(plistData != NULL)
	{
        NSData *__strong nsData = (NSData *)CFBridgingRelease(plistData);
        isOK = (bool)[nsData writeToURL:(__bridge NSURL *)plistURL
                                options:NSDataWritingAtomic
                                  error:NULL];
	}
	return isOK;
}

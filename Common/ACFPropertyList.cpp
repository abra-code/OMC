#include "ACFPropertyList.h"
#include "ACFJSON.h"
#include "ACFPath.h"
#include "CFObj.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <string>
#include <vector>

// Plain CF and POSIX: this file used NSData, NSJSONSerialization and NSString before, and is
// shared by Abracode.framework and plister. JSON goes through ACFJSON (see ACFJSON.h for how
// closely it follows NSJSONSerialization); file reading and the atomic write reproduce NSData.

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
static ACFPropertyListFormat FormatFromContent(CFDataRef data)
{
    if (data == NULL)
        return kACFPropertyListFormat_unknown;

    const unsigned char *bytes = ::CFDataGetBytePtr(data);
    size_t length = (size_t)::CFDataGetLength(data);
    if ((bytes == NULL) || (length == 0))
        return kACFPropertyListFormat_unknown;

    if ((length >= 8) && (memcmp(bytes, "bplist00", 8) == 0))
        return kACFPropertyListFormat_binary;

    size_t i = 0;
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

// A file URL's path for the POSIX calls; false for any other URL (CF would give an http URL's
// path too, and NSData did not read or write a URL without a scheme either).
static bool GetFilePath(CFURLRef url, char (&outPath)[PATH_MAX])
{
    if (url == NULL)
        return false;
    CFObj<CFStringRef> scheme( ::CFURLCopyScheme(url) );//a relative URL's comes from its base
    if ((scheme == NULL) || (::CFStringCompare(scheme, CFSTR("file"), kCFCompareCaseInsensitive) != kCFCompareEqualTo))
        return false;
    return ::CFURLGetFileSystemRepresentation(url, true, (UInt8 *)outPath, PATH_MAX);
}

// The whole content of a regular file (symbolic links followed), as NSData dataWithContentsOfURL
// gave: NULL for a missing or unreadable file, and for anything but a regular file (a folder, a
// FIFO, a device). O_NONBLOCK keeps open() from waiting for a FIFO's writer; it does not change
// reading a regular file.
static CFDataRef CreateDataWithContentsOfFile(CFURLRef url)
{
    char path[PATH_MAX];
    if (!GetFilePath(url, path))
        return NULL;

    int fd = ::open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0)
        return NULL;

    struct stat info;
    if ((::fstat(fd, &info) != 0) || !S_ISREG(info.st_mode))
    {
        (void)::close(fd);
        return NULL;
    }

    std::vector<UInt8> bytes;
    if (info.st_size > 0)
        bytes.reserve((size_t)info.st_size);
    UInt8 buffer[65536];
    bool isOK = true;
    while (true)
    {
        ssize_t count = ::read(fd, buffer, sizeof(buffer));
        if (count > 0)
        {
            bytes.insert(bytes.end(), buffer, buffer + count);
            continue;
        }
        if ((count < 0) && (errno == EINTR))
            continue;
        isOK = (count == 0);
        break;
    }
    (void)::close(fd);
    if (!isOK)
        return NULL;

    return ::CFDataCreate(kCFAllocatorDefault, bytes.data(), (CFIndex)bytes.size());
}

// As NSData writeToURL:options:NSDataWritingAtomic: the bytes go to a new file beside the target,
// which then replaces it by rename(). As there:
//  - a new file gets mode 0666 less the umask;
//  - an existing file keeps its mode (taken with lstat, so a symbolic link's own mode), set
//    after writing, since a write clears the set-user-ID and set-group-ID bits;
//  - a symbolic link at the path is replaced by the file, and its target is left alone;
//  - a hard link is broken (the other names keep the old content);
//  - a folder that is not writable, or missing, makes the write fail, and nothing is left behind;
//  - a name of any length the file system allows can be written (the temporary name is
//    shortened to fit NAME_MAX).
static bool WriteDataAtomically(CFDataRef data, CFURLRef url)
{
    char path[PATH_MAX];
    if ((data == NULL) || !GetFilePath(url, path))
        return false;

    std::string target(path);
    size_t slash = target.rfind('/');
    std::string folderPrefix = (slash == std::string::npos) ? std::string() : target.substr(0, slash + 1);
    std::string name = (slash == std::string::npos) ? target : target.substr(slash + 1);

    // lstat, as NSData: a symbolic link at the path gives the link's own mode, 0755 on macOS.
    // LINUX PORT: a symbolic link's mode is 0777 there, which would make the new file
    // world-writable; the Linux build must take the mode with stat (the target's) or not keep it
    // for a link (Private/linux_port_plan.md, Phase 7).
    struct stat existing;
    bool hasExisting = (::lstat(path, &existing) == 0);

    // ".<name>.omc-<8 hex digits>", with the name cut on a UTF-8 character boundary when the
    // whole would be longer than a file name may be
    const size_t kAddedLength = 1 + 5 + 8;
    std::string stem = name;
    if (stem.size() + kAddedLength > NAME_MAX)
    {
        size_t keep = NAME_MAX - kAddedLength;
        while ((keep > 0) && (((unsigned char)stem[keep] & 0xC0) == 0x80))
            keep--;
        stem.resize(keep);
    }

    int fd = -1;
    std::string temporary;
    for (int attempt = 0; (attempt < 100) && (fd < 0); attempt++)
    {
        char suffix[16];
        snprintf(suffix, sizeof(suffix), "%08x", (unsigned)::arc4random());
        temporary = folderPrefix + "." + stem + ".omc-" + suffix;
        fd = ::open(temporary.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0666);//the umask applies
        if ((fd < 0) && (errno != EEXIST))
            return false;
    }
    if (fd < 0)
        return false;

    bool isOK = true;
    const UInt8 *bytes = ::CFDataGetBytePtr(data);
    size_t remaining = (size_t)::CFDataGetLength(data);
    while (isOK && (remaining > 0))
    {
        ssize_t written = ::write(fd, bytes, remaining);
        if (written > 0)
        {
            bytes += written;
            remaining -= (size_t)written;
        }
        else if ((written < 0) && (errno == EINTR))
        {
            continue;
        }
        else
        {
            isOK = false;
        }
    }

    if (isOK && hasExisting)
        isOK = (::fchmod(fd, existing.st_mode & 07777) == 0);
    if (::close(fd) != 0)
        isOK = false;
    if (isOK)
        isOK = (::rename(temporary.c_str(), path) == 0);
    if (!isOK)
        (void)::unlink(temporary.c_str());
    return isOK;
}

static void PrintJSONError(const char *inPrefix, CFStringRef inError)
{
    char message[1024] = "unknown error";
    if (inError != NULL)
        (void)::CFStringGetCString(inError, message, sizeof(message), kCFStringEncodingUTF8);
    fprintf(stderr, "Error: %s: %s\n", inPrefix, message);
}

static CFPropertyListRef CreateFromPlistData(CFDataRef data, CFPropertyListMutabilityOptions mutabilityOptions)
{
    return ::CFPropertyListCreateWithData(kCFAllocatorDefault, data, mutabilityOptions, NULL, NULL);
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

    CFObj<CFDataRef> data( CreateDataWithContentsOfFile(plistURL) );
    if (data == NULL)
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

    CFObj<CFPropertyListRef> result;
    if (format == kACFPropertyListFormat_json)
    {
        CFObj<CFStringRef> jsonError;
        result.Adopt( ACFJSONCreatePropertyList(data, mutabilityOptions, &jsonError) );
        if (result == NULL)
        {
            if (extFormat == kACFPropertyListFormat_json)
            {//the name promised JSON, so a parse failure is the whole answer
                PrintJSONError("failed to parse JSON", jsonError);
            }
            else
            {//it only looked like JSON - an old-style plist dictionary opens with '{' as well
                result.Adopt( CreateFromPlistData(data, mutabilityOptions) );
                if (result != NULL)
                    format = kACFPropertyListFormat_xml;
                else
                    PrintJSONError("failed to parse JSON", jsonError);
            }
        }
    }
    else
    {
        result.Adopt( CreateFromPlistData(data, mutabilityOptions) );
        if (result != NULL)
        {
            if (format != kACFPropertyListFormat_binary)
                format = kACFPropertyListFormat_xml;//XML, old-style, or anything else CF understood
        }
        else if (extFormat == kACFPropertyListFormat_unknown)
        {//unknown extension and unrecognizable content: JSON is the remaining candidate
            result.Adopt( ACFJSONCreatePropertyList(data, mutabilityOptions, NULL) );
            if (result != NULL)
                format = kACFPropertyListFormat_json;
        }
    }

    if (result == NULL)
        format = fallbackFormat;

    if (outFormat != NULL)
        *outFormat = format;

    return result.Detach();
}

CFPropertyListRef CreatePropertyList(CFURLRef plistURL, CFPropertyListMutabilityOptions mutabilityOptions)
{
    return CreatePropertyListAndFormat(plistURL, mutabilityOptions, NULL);
}

CFURLRef CopyCommandFileURLInBundle(CFBundleRef inBundle, CFStringRef inFileName)
{
    if (inBundle == NULL)
        return NULL;

    //as NSString's stringByDeletingPathExtension (ACFPath.h)
    CFObj<CFStringRef> baseName;
    if (inFileName != NULL)
        baseName.Adopt( ACFPathCreateDeletingExtension(inFileName) );
    if ((baseName == NULL) || (::CFStringGetLength(baseName) == 0))
        baseName.Adopt( CFSTR("Command"), kCFObjRetain );

    // JSON preferred, plist fallback - an applet may ship either format.
    const CFStringRef kExtensions[] = { CFSTR("json"), CFSTR("plist") };
    for (CFStringRef ext : kExtensions)
    {
        CFObj<CFURLRef> url( CFBundleCopyResourceURL(inBundle, baseName, ext, NULL) );
        if (url != NULL)
            return url.Detach(); // +1, caller releases
    }
    return NULL;
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

    if (format == kACFPropertyListFormat_json)
    {
        // A container, or a string, null or number at the root, written pretty-printed with
        // sorted keys. CFData, CFDate, a non-finite number, or a dictionary keyed by anything but
        // a string has no JSON spelling at any depth (reachable through
        // "plister insert X copy src.plist /Data dest.json /"), and neither has a string with a
        // lone surrogate.
        ACFJSONWriteStatus status = kACFJSONWriteOK;
        CFObj<CFDataRef> jsonData( ACFJSONCreateData(propertyList, &status) );
        if (status == kACFJSONWriteUnrepresentable)
        {
            fprintf(stderr, "Error: this value has no JSON representation (data, a date, a non-finite number, or a non-string dictionary key)\n");
            return false;
        }
        if (jsonData == NULL)
        {
            fprintf(stderr, "Error: failed to serialize JSON: a string contains a lone surrogate, which has no UTF-8 form\n");
            return false;
        }
        return WriteDataAtomically(jsonData, plistURL);
    }

    CFPropertyListFormat cfFormat = (format == kACFPropertyListFormat_binary) ? kCFPropertyListBinaryFormat_v1_0
                                                                             : kCFPropertyListXMLFormat_v1_0;
    CFObj<CFDataRef> plistData( ::CFPropertyListCreateData(kCFAllocatorDefault, propertyList, cfFormat, 0, NULL) );
    if (plistData == NULL)
        return false;
    return WriteDataAtomically(plistData, plistURL);
}

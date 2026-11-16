//
//  OMCLog.h
//  Abracode
//
//  A message to the system log, from portable code. macOS: Platform/Apple/OMCLog.mm (NSLog, so it
//  reaches Console and stderr as before); a Linux implementation can write to stderr or the journal.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// printf-style; a CFString argument can be passed as a C string with OMCLogCString below.
void OMCLogMessage(const char *inFormat, ...) __attribute__((format(printf, 1, 2)));

#ifdef __cplusplus
}

#include <string>
#include <vector>

// A CFString as UTF-8 for OMCLogMessage's %s; "(null)" for NULL.
inline std::string OMCLogCString(CFStringRef inString)
{
	if(inString == NULL)
		return "(null)";
	CFIndex maxSize = CFStringGetMaximumSizeForEncoding(CFStringGetLength(inString), kCFStringEncodingUTF8) + 1;
	std::vector<char> buffer((size_t)maxSize);
	if(!CFStringGetCString(inString, buffer.data(), maxSize, kCFStringEncodingUTF8))
		return "(unprintable)";
	return std::string(buffer.data());
}
#endif

//
//  ACFJSON.h
//
//  JSON to and from CF property list objects, in C++ over CF and the vendored yyjson
//  (ThirdParty/yyjson), so it builds on macOS and Linux. It replaces NSJSONSerialization and
//  reproduces what OMC got from it on macOS; OMCJSONFoundationParityTests holds it to that.
//  Measured behaviors and the reasons for each rule: Private/json-port-design.md.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Reads JSON as NSJSONSerialization did with NSJSONReadingAllowFragments, and with
// NSJSONReadingMutableContainers when inMutability is not kCFPropertyListImmutable (containers
// mutable, strings immutable). Accepts UTF-8 (with or without a byte order mark), UTF-16 and
// UTF-32 (little-endian UTF-32 only without a byte order mark, as there), trailing commas, and a
// value nested in at most 512 containers; for a repeated key the first value wins in an
// immutable result and the last in a mutable one, also as there.
// Returns the value, retained, or NULL; then *outError, when outError is not NULL, is a retained
// description of the problem.
// Deliberate differences: an integer that does not fit 64 bits reads as a double (Foundation
// made an NSDecimalNumber, which CF has no counterpart for); UTF-16 text with characters outside
// the Basic Multilingual Plane reads correctly (Foundation fails on it).
CFPropertyListRef ACFJSONCreatePropertyList(CFDataRef inData, CFPropertyListMutabilityOptions inMutability, CFStringRef *outError);

typedef enum ACFJSONWriteStatus
{
	kACFJSONWriteOK = 0,
	kACFJSONWriteUnrepresentable,	// CFData, CFDate, a non-finite number, a non-string key, or another type JSON cannot hold
	kACFJSONWriteInvalidString		// a string with a lone surrogate, which has no UTF-8 form
} ACFJSONWriteStatus;

// Writes inValue (a container or a single value) as NSJSONSerialization did with
// NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys and fragments allowed: two-space indent,
// "key" : value, keys in NSJSONWritingSortedKeys order, "/" escaped, doubles with 17 significant digits,
// no trailing newline. Returns the UTF-8 text, retained, or NULL with *outStatus saying why.
// outStatus may be NULL.
CFDataRef ACFJSONCreateData(CFPropertyListRef inValue, ACFJSONWriteStatus *outStatus);

#ifdef __cplusplus
}
#endif

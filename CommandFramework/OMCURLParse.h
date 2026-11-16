//
//  OMCURLParse.h
//  Abracode
//
//  The parts of a URL sent to an applet that OMCRunCommandForURL (OMCCommandRunner.h) decides on:
//  whether it is a URL at all, its host, and its query's items. Portable C++ on CF, held to what
//  NSURLComponents (componentsWithString:, host, queryItems) gives on macOS by
//  OMCURLParseParityTests, so applets keep its exact rules:
//  - characters a URL may not hold are taken as if percent-encoded, except in the host, where any
//    but an unreserved character, a sub-delimiter, a "%" escape or a non-ASCII one makes the
//    string no URL; a port must be digits; a scheme starts with a letter, and a string whose first
//    ":" (before any "/", "?" or "#") follows something that is not a scheme is no URL either;
//  - the host is percent-decoded (NULL when that is not UTF-8) but for "%00", which it keeps,
//    keeps its case, and drops the user and the port; a bracketed host keeps its brackets; with no
//    "//" there is no host;
//  - the query is what follows the first "?" up to "#"; an empty query has no items; items are
//    separated by "&", a name from its value by the first "="; names and values are
//    percent-decoded, unless the query holds a character a query may not hold as it is (a space,
//    a control, " < > [ ] \ ^ ` { | }, a non-ASCII character, or a "%" without two hex digits):
//    then the whole query is text as it is, every "%" included; a name that does not decode to
//    UTF-8 is empty, a value kCFNull, as is the value of an item with no "="; "+" stays "+";
//  - the whole string is parsed, past any NUL; a lone surrogate is taken as U+FFFD;
//  - the rules are held for URLs that start with a scheme, which every URL sent to an applet does
//    (the system routes it by its scheme).
//  Known differences: a non-ASCII host is taken as it is, where NSURLComponents applies the rules
//  of internationalized domain names (punycode, mapping, and refusing some, such as a label that
//  starts with "-"); a bracketed host's contents are not checked. Neither host is "exe" here, so
//  such a URL goes to the applet's omc.app.handle-url command, as any other URL that is not an
//  "exe" one does, even where NSURLComponents refuses it, or maps it to "exe" (fullwidth letters,
//  or "exe" with a soft hyphen or zero-width space in it): such a link runs no command.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include "CFObj.h"

// Returns whether inURL is a URL. When it is: outHost is its host or NULL, and outQueryItems the
// query's items in order, each a CFArray of two: the name and the value, each a CFString or kCFNull.
// When it is not, both are NULL.
bool OMCParseURL(CFStringRef inURL, CFObj<CFStringRef> &outHost, CFObj<CFArrayRef> &outQueryItems) noexcept;

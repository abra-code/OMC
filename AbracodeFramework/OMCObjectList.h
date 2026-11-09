//
//  OMCObjectList.h
//  Abracode
//
//  Walking a list of file URLs (the context files, a file dialog's choice) with a handler per URL.
//  Portable: CoreFoundation only. The Apple event form of the same walk is CMUtils::ProcessObjectList
//  (CMUtils/CMUtilsObjectList.cp), macOS only, with the same flags.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <stddef.h>

// Called for each URL in the list; returns noErr when the URL is taken, userCanceledErr (-128) to
// stop the walk, any other error to skip it
typedef OSStatus (*CFURLHandlerProc)( CFURLRef inURLRef, size_t index, void *ioData );

enum
{
	kListClear					= 0x00000000,

	kProcDirectiveMask			= 0x00FF0000,
	kProcBreakOnFirst			= 0x00010000,	// stop after the first URL the handler takes

	kListOutFlagsMask			= 0xFF000000,
	kListOutMultipleObjects		= 0x01000000,	// the list has more than one item
	kListOutErrorsOccurred		= 0x02000000	// the handler refused at least one URL
};

// Calls inProcPtr for each CFURL in fileList (other items are skipped) and returns how many it took.
// ioFlags carries kProc* directives in and kListOut* results out.
size_t OMCProcessObjectList(CFArrayRef fileList, UInt32 &ioFlags, CFURLHandlerProc inProcPtr, void *inProcData = nullptr);

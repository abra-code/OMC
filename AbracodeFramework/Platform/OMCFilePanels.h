//
//  OMCFilePanels.h
//  Abracode
//
//  Created by Tomasz Kukielka on 5/25/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//
//  The save and open panels. The engine calls CreateCFURLFromSaveAsDialog and
//  CreateCFURLsFromOpenDialog (OMCFilePanels.cpp, portable): in a test launch they are answered by
//  the test host from the answers a test queued (OMCTestHost.h), otherwise they show the system's
//  panels through the OMCPlatformRun* functions, implemented per platform: Platform/Apple/OMCFilePanels.mm
//  (NSSavePanel, NSOpenPanel); a Linux implementation can use ActionUI's panels
//  (actionUIAppRunSavePanel, actionUIAppRunOpenPanel). Each call blocks until the user answers.
//  The dialog settings from Command.plist are parsed by GetNavDialogParams (OMCNavigationDialogs.h).
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif //__cplusplus

enum
{
	kOMCFilePanelAllowInvisibleItems	= 0x01,
	kOMCFilePanelCanChooseFiles			= 0x02,
	kOMCFilePanelCanChooseDirectories	= 0x04,
	kOMCFilePanelAllowMultipleItems		= 0x08,
	kOMCFilePanelUseCachedPath			= 0x10 //subcommands may reuse the path already obtained by the main command or another subcommand
};

// inAllowedContentTypes: array of UTI strings (e.g. "public.image", "public.audio") or NULL.
// Each returns the chosen URL(s), retained (caller releases), or NULL when the user cancels.
CFURLRef CreateCFURLFromSaveAsDialog( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inAdditonalFlags);
CFArrayRef CreateCFURLsFromOpenDialog( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inAdditonalFlags);

// The platform's panels, with the same arguments and results. Called only by the two above.
CFURLRef OMCPlatformRunSavePanel( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inAdditonalFlags);
CFArrayRef OMCPlatformRunOpenPanel( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inAdditonalFlags);

#ifdef __cplusplus
}
#endif //__cplusplus

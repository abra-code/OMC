//
//  OMCFilePanels.h
//  Abracode
//
//  Created by Tomasz Kukielka on 5/25/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

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

CFURLRef CreateCFURLFromSaveAsDialog( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inAdditonalFlags);
CFArrayRef CreateCFURLsFromOpenDialog( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inAdditonalFlags);

// Parse shared navigation dialog options from a dialog settings dictionary (CHOOSE_FILE_DIALOG, OPEN_OBJECT_DIALOG, etc.)
// Returns additional flags (kOMCFilePanelAllowInvisibleItems, kOMCFilePanelAllowMultipleItems, kOMCFilePanelUseCachedPath)
// outAllowedContentTypes: array of UTI strings (e.g. "public.image", "public.audio") or NULL
UInt32 CopyNavDialogParams(CFDictionaryRef inParams, CFStringRef *outMessage, CFArrayRef *outDefaultName, CFArrayRef *outDefaultLocation, CFStringRef *outIdentifier, CFStringRef *outPrompt, CFArrayRef *outAllowedContentTypes);

#ifdef __cplusplus
}
#endif //__cplusplus

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

CFURLRef CreateCFURLFromSaveAsDialog( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, UInt32 inAdditonalFlags);
CFArrayRef CreateCFURLsFromOpenDialog( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, UInt32 inAdditonalFlags);

#ifdef __cplusplus
}
#endif //__cplusplus

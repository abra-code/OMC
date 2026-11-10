//
//  OMCAppShell.mm
//  Abracode
//
//  The macOS implementation of Platform/OMCAppShell.h's calls (moved from OMCHostInfo.mm). The
//  rest of the macOS app shell is in EntryPoints/Apple.
//

#import <Cocoa/Cocoa.h>
#include "OMCAppShell.h"
#import "OMCCommandExecutor.h" // OMCNoteRecentDocumentURL

void ActivateThisApp(void)
{
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
}

void QuitThisApp(void)
{
    [[NSApplication sharedApplication] terminate:nil];
}

void NoteRecentDocument(CFURLRef fileURL)
{
    OMCNoteRecentDocumentURL((__bridge NSURL *)fileURL);
}

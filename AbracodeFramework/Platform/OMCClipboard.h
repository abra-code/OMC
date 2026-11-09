//
//  OMCClipboard.h
//  Abracode
//
//  The clipboard as the engine uses it: the text a command gets as its clipboard context, and
//  SIMULATE_PASTE, which pastes into the front app once a command has finished. In an OMC test
//  launch the clipboard is the run's own pasteboard (OMCTestHost.h), so a test never touches the
//  user's clipboard.
//
//  macOS: Platform/Apple/OMCClipboard.cp (Pasteboard Manager, CGEvent). Linux (later): the
//  desktop's clipboard through ActionUI, and no paste into another app.
//
//  Main thread only.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

// Whether the clipboard holds plain text
bool OMCIsTextInClipboard();

// The clipboard's plain text, its line endings changed as inReplaceOption says (kTextReplace* in
// OMCConstants.h); NULL when there is none. The caller releases it.
CFStringRef OMCCopyClipboardText(long inReplaceOption);

// Pastes the clipboard into the app in front, as Command-V would (SIMULATE_PASTE)
void OMCPasteIntoFrontApp();

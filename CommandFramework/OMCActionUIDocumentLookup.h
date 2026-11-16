//
//  OMCActionUIDocumentLookup.h
//  Abracode
//
//  Where an ActionUI command window's document is: ACTIONUI_WINDOW's JSON_NAME, and the document an
//  omc_dialog_control omc_present_modal names. Portable (CFBundle).
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

// inNameOrPath: an absolute path, used as is; else a resource name, with or without ".json", looked
// up (each bundle's Resources folder and its localized folders, as the bundle orders them) in the
// command's extern bundle, then the main bundle, then OMC's framework bundle; either bundle may be
// NULL. Returns a file URL (the caller releases it), or NULL when there is no such document.
CFURLRef OMCCopyActionUIDocumentURL(CFStringRef inNameOrPath, CFBundleRef inExternBundle, CFBundleRef inFrameworkBundle) noexcept;

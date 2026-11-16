//
//  OMCAboutWindow.h
//  Abracode
//
//  The applet's About window, the same on macOS and Linux: a built-in
//  ActionUI document (BuiltInDocuments/command_about.json) in a window of the window host
//  (Platform/OMCWindowHost.h), showing from the app's bundle:
//  - its icon: the file CFBundleIconFile names (OMCCopyBundleIconURL, Platform/OMCHostInfo.h);
//  - its name: CFBundleDisplayName, else CFBundleName, else the bundle's file name;
//  - "Version <CFBundleShortVersionString> (<CFBundleVersion>)", or one of them when the other is
//    missing or the same;
//  - Resources/Credits.md, as Markdown in a RichText element (the ActionUIRichText add-on), in a
//    scroll area of fixed height;
//  - NSHumanReadableCopyright.
//  Whatever the bundle lacks is left out of the window. Credits.rtf, .rtfd and .html are not read:
//  Markdown is the one format, on every platform (owner, 2026-11-15).
//  One About window at a time: showing it again brings the open one to the front.
//  The menus open it: macOS, the About item of the menu bar (OMCMainMenuController); Linux, the
//  About item of the header bar's menu (OMCAppletMenu.cpp).
//
//  Main thread only.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Shows the About window of the app in inBundle (NULL: the main bundle), or brings the open one to
// the front. An open window of another bundle is closed first. Nothing when the document cannot be
// loaded (logged).
void OMCShowAboutWindow(CFBundleRef inBundle);

// The open About window's UUID, for ActionUI's C calls (tests); NULL when none is open
CFStringRef OMCCopyAboutWindowUUID(void);

// Closes the About window, if one is open
void OMCCloseAboutWindow(void);

#ifdef __cplusplus
}
#endif

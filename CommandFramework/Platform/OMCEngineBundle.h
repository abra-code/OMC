//
//  OMCEngineBundle.h
//  Abracode
//
//  The engine's own bundle, Command.framework: its Info.plist (the engine version), its localized
//  strings (Private.strings) and its built-in ActionUI documents. The one way the engine finds it.
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>

// Command.framework's bundle identifier (CFBundleIdentifier in its Info.plist). A C string, not a
// file-scope CFSTR, which does not compile on Linux.
#define OMC_ENGINE_BUNDLE_IDENTIFIER "com.abracode.Command"

#ifdef __cplusplus
extern "C" {
#endif

// The engine's bundle, found once on first use (from any thread) and kept for the life of the
// process: do not release it. NULL when it cannot be found. macOS: the loaded framework, by its
// bundle identifier. Linux: CoreFoundation knows only the main bundle and the bundles created, so
// the engine creates its framework's bundle: the folder holding libCommand.so when the engine is a
// shared library, else the applet's Frameworks/Command.framework.
CFBundleRef OMCGetEngineBundle(void);

#ifdef __cplusplus
}
#endif

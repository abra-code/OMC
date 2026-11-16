//
//  OMCHostInfo.h
//  Abracode
//
//  What the engine asks about the process it runs in and the desktop around it: the host app, the
//  front app, the OS version, the modifier keys held down, and bringing this process to the front.
//  macOS: Platform/Apple/OMCHostInfo.mm (NSWorkspace, NSRunningApplication, CGEvent). Linux:
//  Platform/Linux/OMCHostInfo.cpp, where the front app is known only while it is the applet, and
//  other answers may be "not available" (NULL, 0, false), which callers handle.
//
//  Main thread only.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <unistd.h>

#ifdef __cplusplus
extern "C" {
#endif

// The host app's display name (CFBundleDisplayName, else CFBundleName); NULL when unknown
CFStringRef OMCCopyHostAppName();

// The front app's name, bundle identifier and process ID; NULL or 0 when unknown
CFStringRef OMCCopyFrontAppName();
CFStringRef OMCCopyFrontAppBundleIdentifier();
pid_t OMCGetFrontAppPID();
CFStringRef OMCCopyAppNameForPID(pid_t pid);

// Whether this process is a regular app with a menu bar and Dock icon (not a background agent),
// which decides whether a floating window can show
bool OMCRunningInRegularGUIApp();

// Tells the file manager a file changed, so a window showing it updates; nothing where unsupported
void OMCRefreshFileInFinder(CFStringRef filePath);

// The macOS version: true with it, or false, the outputs untouched, on a system that is not macOS,
// where a command's macOS version requirements (REQUIRED_MAC_OS_MIN_VERSION, _MAX_VERSION) mean
// nothing and are ignored
bool OMCGetMacOSVersion(long* outMajorVersion, long* outMinorVersion, long* outPatchVersion);

// The modifier keys held down now, as a mask of kOMCModifier* values
typedef uint32_t OMCModifierKeys;
enum
{
	kOMCModifierCapsLock	= 1u << 0,
	kOMCModifierShift		= 1u << 1,
	kOMCModifierControl		= 1u << 2,
	kOMCModifierOption		= 1u << 3,
	kOMCModifierCommand		= 1u << 4
};
OMCModifierKeys OMCGetKeyboardModifiers();

// OMCActivateThisApp, OMCQuitThisApp and OMCNoteRecentDocument are the app shell's: Platform/OMCAppShell.h

#ifdef __cplusplus
}

// Brings this process to the front if it is not there already; with inRestore, the app that was in
// front is brought back when the scope ends
class StSwitchToFront
{
public:
	StSwitchToFront(bool inRestore = true) noexcept;
	~StSwitchToFront() noexcept;

private:
	pid_t mPreviousFrontAppPID { 0 };
};
#endif

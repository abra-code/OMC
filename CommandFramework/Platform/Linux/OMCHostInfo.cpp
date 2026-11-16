//
//  OMCHostInfo.cpp (Linux)
//  Abracode
//
//  The Linux implementation of Platform/OMCHostInfo.h,
//  for an applet, the one host the engine has on Linux:
//  - The host app is the applet: its bundle's display name (CFBundleDisplayName, else CFBundleName),
//    as on macOS, else GLib's application name.
//  - The front app is the applet while one of its windows has the keyboard focus, else unknown
//    (NULL, 0): a Wayland desktop does not tell an app about other apps' windows. A process's name
//    is the applet's for its own process, else the kernel's command name (/proc/<pid>/comm).
//  - The modifier keys held down, from GDK's keyboard (on Wayland only while one of the applet's
//    windows has the focus, else none), mapped by role rather than by name: Ctrl, the key of
//    Linux's shortcuts (Ctrl+O where macOS has Command-O), is kOMCModifierCommand; Alt is Option;
//    Super is kOMCModifierControl. So a command chosen with a Ctrl shortcut is not taken for the
//    debug request macOS reads from Control held alone (OnMyCommand.cpp), which on Linux is Super
//    held alone.
//  - StSwitchToFront does nothing: a Wayland app cannot bring itself to the front unasked (a
//    dialog shows over the applet's active window, OMCModalLoop.h).
//  - There is no macOS version: OMCGetMacOSVersion answers false, and a command's macOS version
//    requirements are ignored (owner, 2026-11-11: a macOS version means nothing on Linux).
//  Main thread only.
//

#include "OMCHostInfo.h"
#include "ACFString.h"
#include "CFObj.h"
#include <gtk/gtk.h>
#include <string>

namespace
{

CFStringRef
CopyBundleString(CFStringRef inKey)
{
	CFBundleRef bundle = CFBundleGetMainBundle();
	CFTypeRef value = (bundle != nullptr) ? CFBundleGetValueForInfoDictionaryKey(bundle, inKey) : nullptr;
	if((value == nullptr) || (CFGetTypeID(value) != CFStringGetTypeID()) || (CFStringGetLength((CFStringRef)value) == 0))
		return nullptr;
	return (CFStringRef)CFRetain(value);
}

// Whether one of the applet's windows has the keyboard focus
bool
AppletIsFront()
{
	if(!gtk_is_initialized())
		return false;
	GApplication *app = g_application_get_default();
	if(!GTK_IS_APPLICATION(app))
		return false;
	GtkWindow *window = gtk_application_get_active_window(GTK_APPLICATION(app)); // the last active, focused or not
	return (window != nullptr) && gtk_window_is_active(window);
}

} // namespace

CFStringRef
OMCCopyHostAppName()
{
	CFStringRef name = CopyBundleString(CFSTR("CFBundleDisplayName"));
	if(name == nullptr)
		name = CopyBundleString(kCFBundleNameKey);
	if(name == nullptr)
	{
		const char *applicationName = g_get_application_name();
		if((applicationName != nullptr) && (applicationName[0] != 0))
			name = CFStringCreateWithCString(kCFAllocatorDefault, applicationName, kCFStringEncodingUTF8);
	}
	return name;
}

CFURLRef
OMCCopyBundleIconURL(CFBundleRef inBundle)
{
	if(inBundle == nullptr)
		return nullptr;
	CFTypeRef iconFile = CFBundleGetValueForInfoDictionaryKey(inBundle, CFSTR("CFBundleIconFile"));
	if((iconFile == nullptr) || (CFGetTypeID(iconFile) != CFStringGetTypeID()) || (CFStringGetLength((CFStringRef)iconFile) == 0))
		return nullptr;
	// "AppIcon" or "AppIcon.icns": the name without its extension
	CFObj<CFStringRef> name((CFStringRef)CFRetain(iconFile));
	CFRange dot = CFStringFind(name, CFSTR("."), kCFCompareBackwards);
	if((dot.location != kCFNotFound) && (dot.location > 0))
		name.Adopt(CFStringCreateWithSubstring(kCFAllocatorDefault, name, CFRangeMake(0, dot.location)));
	CFURLRef url = CFBundleCopyResourceURL(inBundle, name, CFSTR("svg"), nullptr);
	if(url == nullptr)
		url = CFBundleCopyResourceURL(inBundle, name, CFSTR("png"), nullptr);
	return url;
}

CFStringRef
OMCCopyFrontAppName()
{
	return AppletIsFront() ? OMCCopyHostAppName() : nullptr;
}

CFStringRef
OMCCopyFrontAppBundleIdentifier()
{
	if(!AppletIsFront())
		return nullptr;
	CFBundleRef bundle = CFBundleGetMainBundle();
	CFStringRef identifier = (bundle != nullptr) ? CFBundleGetIdentifier(bundle) : nullptr;
	return (identifier != nullptr) ? (CFStringRef)CFRetain(identifier) : nullptr;
}

pid_t
OMCGetFrontAppPID()
{
	return AppletIsFront() ? getpid() : 0;
}

CFStringRef
OMCCopyAppNameForPID(pid_t pid)
{
	if(pid <= 0)
		return nullptr;
	if(pid == getpid())
		return OMCCopyHostAppName();
	std::string path = "/proc/" + std::to_string((long)pid) + "/comm";
	char *contents = nullptr;
	gsize length = 0;
	if(!g_file_get_contents(path.c_str(), &contents, &length, nullptr) || (contents == nullptr))
		return nullptr;
	std::string name(contents, length);
	g_free(contents);
	while(!name.empty() && ((name.back() == '\n') || (name.back() == '\r')))
		name.pop_back();
	if(name.empty())
		return nullptr;
	return CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)name.data(), (CFIndex)name.size(), kCFStringEncodingUTF8, false);
}

// The engine runs only in applets on Linux (no contextual menu plugin, no Services host)
bool
OMCRunningInRegularGUIApp()
{
	return true;
}

void
OMCRefreshFileInFinder(CFStringRef filePath)
{
	(void)filePath; // a Linux file manager watches its folders itself
}

bool
OMCGetMacOSVersion(long* outMajorVersion, long* outMinorVersion, long* outPatchVersion)
{
	(void)outMajorVersion; (void)outMinorVersion; (void)outPatchVersion;
	return false; // not macOS (see the header)
}

OMCModifierKeys
OMCGetKeyboardModifiers()
{
	if(!gtk_is_initialized())
		return 0;
	GdkDisplay *display = gdk_display_get_default();
	GdkSeat *seat = (display != nullptr) ? gdk_display_get_default_seat(display) : nullptr;
	GdkDevice *keyboard = (seat != nullptr) ? gdk_seat_get_keyboard(seat) : nullptr;
	if(keyboard == nullptr)
		return 0;
	GdkModifierType state = gdk_device_get_modifier_state(keyboard);
	OMCModifierKeys modifiers = 0;
	if((state & GDK_LOCK_MASK) != 0)
		modifiers |= kOMCModifierCapsLock;
	if((state & GDK_SHIFT_MASK) != 0)
		modifiers |= kOMCModifierShift;
	if((state & GDK_CONTROL_MASK) != 0)
		modifiers |= kOMCModifierCommand; // by role: Linux's shortcut key (see the header)
	if((state & GDK_ALT_MASK) != 0)
		modifiers |= kOMCModifierOption;
	if((state & GDK_SUPER_MASK) != 0)
		modifiers |= kOMCModifierControl;
	return modifiers;
}

StSwitchToFront::StSwitchToFront(bool inRestore) noexcept
{
	(void)inRestore;
	(void)mPreviousFrontAppPID;
}

StSwitchToFront::~StSwitchToFront() noexcept
{
}

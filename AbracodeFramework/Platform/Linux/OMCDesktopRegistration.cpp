//
//  OMCDesktopRegistration.cpp (Linux)
//  Abracode
//
//  See OMCDesktopRegistration.h. The applet's install-applet.sh decides and does the work; this file
//  only runs it (GSubprocess, so the window is not held up while it reads the applet's Info.plist),
//  and asks the user when the script says the applet is not on the app list.
//

#include "Linux/OMCDesktopRegistration.h"
#include "OMCAlerts.h"
#include "OMCTestHost.h"
#include "OMCLog.h"
#include "ACFString.h"
#include "CFObj.h"
#include <gio/gio.h>
#include <string>

namespace
{

// The environment variable that turns the check off (AppletBuilder's Run)
const char *kNoPromptVariable = "COMMAND_ENGINE_NO_DESKTOP_PROMPT";

// The applet bundle's path, or empty
std::string
BundlePath()
{
	CFBundleRef bundle = CFBundleGetMainBundle();
	if(bundle == nullptr)
		return std::string();
	CFObj<CFURLRef> bundleURL(CFBundleCopyBundleURL(bundle));
	if(bundleURL == nullptr)
		return std::string();
	char path[4096];
	if(!CFURLGetFileSystemRepresentation(bundleURL, true, (UInt8 *)path, sizeof(path)))
		return std::string();
	return std::string(path);
}

// The applet's name for the alert: its CFBundleName, else the bundle's name without ".app"
CFStringRef
CopyAppletName(const std::string &inBundlePath)
{
	CFBundleRef bundle = CFBundleGetMainBundle();
	CFTypeRef value = (bundle != nullptr) ? CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleNameKey) : nullptr;
	if((value != nullptr) && (CFGetTypeID(value) == CFStringGetTypeID()) && (CFStringGetLength((CFStringRef)value) > 0))
		return (CFStringRef)CFRetain(value);
	std::string name = inBundlePath.substr(inBundlePath.find_last_of('/') + 1);
	if((name.size() > 4) && (name.compare(name.size() - 4, 4, ".app") == 0))
		name.resize(name.size() - 4);
	return CFStringCreateWithCString(kCFAllocatorDefault, name.c_str(), kCFStringEncodingUTF8);
}

// Whether the applet has a file service, by command-services.py's rule (the services it lists for the
// file managers): an NSServices item that sends files, by NSSendFileTypes or by NSSendTypes naming
// NSFilenamesPboardType or public.file-url. A text service is not for a file manager.
bool
AppletHasFileServices()
{
	CFBundleRef bundle = CFBundleGetMainBundle();
	CFTypeRef services = (bundle != nullptr) ? CFBundleGetValueForInfoDictionaryKey(bundle, CFSTR("NSServices")) : nullptr;
	if((services == nullptr) || (CFGetTypeID(services) != CFArrayGetTypeID()))
		return false;
	CFIndex count = CFArrayGetCount((CFArrayRef)services);
	for(CFIndex i = 0; i < count; i++)
	{
		CFTypeRef item = CFArrayGetValueAtIndex((CFArrayRef)services, i);
		if((item == nullptr) || (CFGetTypeID(item) != CFDictionaryGetTypeID()))
			continue;
		CFTypeRef fileTypes = CFDictionaryGetValue((CFDictionaryRef)item, CFSTR("NSSendFileTypes"));
		if((fileTypes != nullptr) && (CFGetTypeID(fileTypes) == CFArrayGetTypeID()) && (CFArrayGetCount((CFArrayRef)fileTypes) > 0))
			return true;
		CFTypeRef sendTypes = CFDictionaryGetValue((CFDictionaryRef)item, CFSTR("NSSendTypes"));
		if((sendTypes == nullptr) || (CFGetTypeID(sendTypes) != CFArrayGetTypeID()))
			continue;
		CFRange all = CFRangeMake(0, CFArrayGetCount((CFArrayRef)sendTypes));
		if(CFArrayContainsValue((CFArrayRef)sendTypes, all, CFSTR("NSFilenamesPboardType")) ||
		   CFArrayContainsValue((CFArrayRef)sendTypes, all, CFSTR("public.file-url")))
			return true;
	}
	return false;
}

// The script, carried with the subprocess callbacks
struct InstallerRun
{
	std::string script;
	std::string mode;
};

// Starts the script with inMode, or logs why it could not; the caller owns the process
GSubprocess *
StartInstaller(const std::string &inScript, const char *inMode, GSubprocessFlags inFlags)
{
	GError *error = nullptr;
	GSubprocess *process = g_subprocess_new(inFlags, &error, inScript.c_str(), inMode, nullptr);
	if(process == nullptr)
	{
		OMCLogMessage("install-applet.sh %s could not start: %s", inMode, (error != nullptr) ? error->message : "unknown error");
		g_clear_error(&error);
	}
	return process;
}

// A finished --register or --decline, logged when it failed
void
OnInstallerDone(GObject *inSource, GAsyncResult *inResult, gpointer inData)
{
	InstallerRun *run = static_cast<InstallerRun *>(inData);
	GSubprocess *process = G_SUBPROCESS(inSource);
	GError *error = nullptr;
	if(!g_subprocess_wait_check_finish(process, inResult, &error))
		OMCLogMessage("install-applet.sh %s failed: %s", run->mode.c_str(), (error != nullptr) ? error->message : "unknown error");
	g_clear_error(&error);
	g_object_unref(process);
	delete run;
}

// Runs the script with inMode in the background (--register, --decline). Its output goes where the
// applet's own goes (the log's place, OMCLog.cpp), not through a pipe: the applet may quit while it
// runs, and a pipe whose reader is gone would cut the script off at its next line of output.
void
RunInstaller(const std::string &inScript, const char *inMode)
{
	GSubprocess *process = StartInstaller(inScript, inMode, G_SUBPROCESS_FLAGS_NONE);
	if(process == nullptr)
		return;
	InstallerRun *run = new InstallerRun{inScript, inMode};
	g_subprocess_wait_check_async(process, nullptr, OnInstallerDone, run);
}

// The answer of --status: registers a moved copy, asks for one not on the app list
void
OnStatus(GObject *inSource, GAsyncResult *inResult, gpointer inData)
{
	InstallerRun *run = static_cast<InstallerRun *>(inData);
	std::string script = run->script;
	GSubprocess *process = G_SUBPROCESS(inSource);
	gchar *output = nullptr;
	GError *error = nullptr;
	bool communicated = g_subprocess_communicate_utf8_finish(process, inResult, &output, nullptr, &error);
	bool succeeded = communicated && g_subprocess_get_successful(process);
	std::string state = (output != nullptr) ? output : "";
	if(!communicated)
		OMCLogMessage("install-applet.sh --status did not finish: %s", (error != nullptr) ? error->message : "unknown error");
	else if(!succeeded)
		OMCLogMessage("install-applet.sh --status failed: %s", state.c_str());
	g_clear_error(&error);
	g_free(output);
	g_object_unref(process);
	delete run;
	if(!succeeded)
		return;
	while(!state.empty() && ((state.back() == '\n') || (state.back() == ' ')))
		state.pop_back();

	if(state == "moved")
	{
		OMCLogMessage("the applet's desktop entry ran a copy that is no longer there: adding this copy");
		RunInstaller(script, "--register");
		return;
	}
	if(state != "none")
		return; // this, other, declined

	std::string bundlePath = BundlePath();
	CFObj<CFStringRef> name(CopyAppletName(bundlePath));
	CFObj<CFStringRef> header(CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("Add %@ to the desktop?"), (CFStringRef)name));
	CFObj<CFStringRef> message(CFStringCreateWithFormat(kCFAllocatorDefault, nullptr,
		AppletHasFileServices()
			? CFSTR("%@ is not on the app list yet. Added, it can be started from there, and the file manager's Services menu offers its file services.")
			: CFSTR("%@ is not on the app list yet. Added, it can be started from there."),
		(CFStringRef)name));
	OMCAlertResponse response = OMCShowAlert(kOMCAlertLevelNote, header, message, CFSTR("Add"), CFSTR("Not Now"), CFSTR("Never"));
	if(response == kOMCAlertDefaultResponse)
		RunInstaller(script, "--register");
	else if(response == kOMCAlertOtherResponse)
		RunInstaller(script, "--decline");
}

} // namespace

void
OMCOfferDesktopRegistration()
{
	if(OMCTestHostIsActive())
		return;
	const char *noPrompt = g_getenv(kNoPromptVariable);
	if((noPrompt != nullptr) && (noPrompt[0] != '\0'))
		return;
	std::string bundlePath = BundlePath();
	if(bundlePath.empty())
		return;
	std::string script = bundlePath + "/Contents/Linux/install-applet.sh";
	if(!g_file_test(script.c_str(), G_FILE_TEST_IS_EXECUTABLE))
		return; // an applet built before the script existed
	// Only its standard output is read: a message on its standard error (which goes where the
	// applet's own does) cannot spoil the one word
	GSubprocess *process = StartInstaller(script, "--status", G_SUBPROCESS_FLAGS_STDOUT_PIPE);
	if(process == nullptr)
		return;
	InstallerRun *run = new InstallerRun{script, "--status"};
	g_subprocess_communicate_utf8_async(process, nullptr, nullptr, OnStatus, run);
}

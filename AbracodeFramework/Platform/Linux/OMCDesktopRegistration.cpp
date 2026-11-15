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
#include <vector>

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

// What the engine last heard from the script, and who wants to know (the app menu)
struct RegistrationState
{
	std::string script; // the applet's install-applet.sh; empty: no check at all (test launch, no script)
	OMCDesktopState state {kOMCDesktopStateUnknown};
	OMCDesktopStateListener listener {nullptr};
	void *listenerContext {nullptr};
	int sequences {0}; // add or remove sequences running, each until the state after it is known
};

RegistrationState &
State()
{
	static RegistrationState *sState = new RegistrationState(); // never freed: lives as long as the app
	return *sState;
}

void QueryStatus(bool inLaunch, bool inMayAsk);

// One run of the script: its mode, and for a sequence the modes still to run after it
struct InstallerRun
{
	std::string script;
	std::string mode;
	std::vector<std::string> then; // --register, --unregister, --decline: run in turn
	bool launch {false}; // --status: the launch's (else the one that ends a sequence)
	bool mayAsk {false}; // --status: ask when the applet is not on the app list
};

// A sequence is over: its state is known, or cannot be asked
void
EndSequence()
{
	RegistrationState &registration = State();
	if(registration.sequences > 0)
		registration.sequences--;
}

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

void RunSequence(const std::string &inScript, std::vector<std::string> inModes);

// A finished --register, --unregister or --decline, logged when it failed; the next mode of its
// sequence runs, and after the last one the state is asked again for the menu
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
	std::string script = run->script;
	std::vector<std::string> then = std::move(run->then);
	delete run;
	RunSequence(script, std::move(then));
}

// Runs the script with each of inModes in turn, in the background, then asks the state (also when
// a mode could not start, so the menu shows what was done). Its output goes where the applet's own
// goes (the log's place, OMCLog.cpp), not through a pipe: the applet may quit while it runs, and a
// pipe whose reader is gone would cut the script off at its next line of output.
void
RunSequence(const std::string &inScript, std::vector<std::string> inModes)
{
	if(inModes.empty())
	{
		QueryStatus(false, false);
		return;
	}
	std::string mode = inModes.front();
	inModes.erase(inModes.begin());
	GSubprocess *process = StartInstaller(inScript, mode.c_str(), G_SUBPROCESS_FLAGS_NONE);
	if(process == nullptr)
	{
		QueryStatus(false, false);
		return;
	}
	InstallerRun *run = new InstallerRun{inScript, mode, std::move(inModes), false, false};
	g_subprocess_wait_check_async(process, nullptr, OnInstallerDone, run);
}

// Starts a sequence: counted until the state after it is known (OnStatus)
void
BeginSequence(const std::string &inScript, std::vector<std::string> inModes)
{
	State().sequences++;
	RunSequence(inScript, std::move(inModes));
}

// Tells the listener the state the script reported ("this" is on the app list, anything else not)
void
NoteState(const std::string &inState)
{
	RegistrationState &registration = State();
	registration.state = (inState == "this") ? kOMCDesktopStateOnDesktop : kOMCDesktopStateNotOnDesktop;
	if(registration.listener != nullptr)
		registration.listener(registration.state, registration.listenerContext);
}

// The answer of --status: the listener hears it; at launch, a moved copy is registered and one not
// on the app list is asked about when the run may ask. Only at launch: after a sequence, a moved
// copy whose --register failed would be registered again and again.
void
OnStatus(GObject *inSource, GAsyncResult *inResult, gpointer inData)
{
	InstallerRun *run = static_cast<InstallerRun *>(inData);
	std::string script = run->script;
	bool launch = run->launch;
	bool mayAsk = run->mayAsk;
	if(!launch)
		EndSequence();
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
	NoteState(state);
	if(!launch)
		return; // a state asked for the menu only

	// A moved copy takes the entry over without asking, but not the project AppletBuilder's Run
	// starts (the question turned off): a development build must not replace the user's entry
	if((state == "moved") && mayAsk)
	{
		OMCLogMessage("the applet's desktop entry ran a copy that is no longer there: adding this copy");
		BeginSequence(script, {"--register"});
		return;
	}
	if((state != "none") || !mayAsk)
		return; // this, other, declined; or the question is turned off

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
		BeginSequence(script, {"--register"});
	else if(response == kOMCAlertOtherResponse)
		BeginSequence(script, {"--decline"});
}

// Asks the script for this copy's state, in the background: at launch (inLaunch; inMayAsk: the
// answer "none" brings the question), or at the end of a sequence
void
QueryStatus(bool inLaunch, bool inMayAsk)
{
	const std::string &script = State().script;
	// Only its standard output is read: a message on its standard error (which goes where the
	// applet's own does) cannot spoil the one word
	GSubprocess *process = script.empty() ? nullptr : StartInstaller(script, "--status", G_SUBPROCESS_FLAGS_STDOUT_PIPE);
	if(process == nullptr)
	{
		if(!inLaunch)
			EndSequence();
		return;
	}
	InstallerRun *run = new InstallerRun{script, "--status", {}, inLaunch, inMayAsk};
	g_subprocess_communicate_utf8_async(process, nullptr, nullptr, OnStatus, run);
}

} // namespace

void
OMCOfferDesktopRegistration()
{
	if(OMCTestHostIsActive())
		return;
	std::string bundlePath = BundlePath();
	if(bundlePath.empty())
		return;
	std::string script = bundlePath + "/Contents/Linux/install-applet.sh";
	if(!g_file_test(script.c_str(), G_FILE_TEST_IS_EXECUTABLE))
		return; // an applet built before the script existed
	State().script = script;
	// The variable stops only the question: the state is still asked for, for the app menu's item
	const char *noPrompt = g_getenv(kNoPromptVariable);
	bool mayAsk = (noPrompt == nullptr) || (noPrompt[0] == '\0');
	QueryStatus(true, mayAsk);
}

void
OMCSetDesktopStateListener(OMCDesktopStateListener inListener, void *inContext)
{
	State().listener = inListener;
	State().listenerContext = inContext;
}

void
OMCAddToDesktop()
{
	// Not while a change runs: two at once would run the scripts on the same files together
	const RegistrationState &registration = State();
	if(registration.script.empty() || (registration.sequences > 0))
		return;
	BeginSequence(registration.script, {"--register"});
}

void
OMCRemoveFromDesktop()
{
	// Taken off by the user's own choice: not asked again at the next launch
	const RegistrationState &registration = State();
	if(registration.script.empty() || (registration.sequences > 0))
		return;
	BeginSequence(registration.script, {"--unregister", "--decline"});
}

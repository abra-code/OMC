//
//  OMCPlatformStubs.cpp
//  Abracode
//
//  Every platform function the portable engine calls that has no Linux implementation yet (OMC 6.0
//  Phase 6, Private/phase6-linux-build-design.md). Each logs once that it is missing and gives the
//  answer that means "not available": no window, no panel answer, no clipboard text, the alert
//  dismissed without a button. With them libAbracode.so links with -z defs, so a function that
//  Linux lacks is a link error rather than a surprise when an applet runs.
//
//  This file is Phase 7's work list: a function that gets a real Linux implementation moves to its
//  own file in Platform/Linux (named as its Platform/Apple counterpart) and leaves this one.
//

#include "OMCHostInfo.h"
#include "OMCClipboard.h"
#include "OMCTerminalLauncher.h"
#include "OMCTestPlatform.h"
#include "OMCActionUIAddOns.h"
#include "OMCFilePanels.h"
#include "OMCActionUIModels.h"
#include "OMCAlerts.h"
#include "OMCWindowHost.h"
#include "OMCLog.h"
#include <atomic>
#include <unistd.h>

// Logs the first call of each missing function, so a run shows what it needed and did not get
#define OMC_LINUX_NOT_YET(inName) \
	do \
	{ \
		static std::atomic<bool> sLogged { false }; \
		if(!sLogged.exchange(true)) \
			OMCLogMessage("%s is not implemented on Linux yet", inName); \
	} while(0)

#pragma mark - Host info (Platform/OMCHostInfo.h)

CFStringRef OMCCopyHostAppName() { OMC_LINUX_NOT_YET("OMCCopyHostAppName"); return nullptr; }
CFStringRef OMCCopyFrontAppName() { OMC_LINUX_NOT_YET("OMCCopyFrontAppName"); return nullptr; }
CFStringRef OMCCopyFrontAppBundleIdentifier() { OMC_LINUX_NOT_YET("OMCCopyFrontAppBundleIdentifier"); return nullptr; }
pid_t OMCGetFrontAppPID() { OMC_LINUX_NOT_YET("OMCGetFrontAppPID"); return 0; }
CFStringRef OMCCopyAppNameForPID(pid_t pid) { (void)pid; OMC_LINUX_NOT_YET("OMCCopyAppNameForPID"); return nullptr; }

// The engine runs only in applets on Linux (no contextual menu plugin, no Services host)
bool OMCRunningInRegularGUIApp() { return true; }

void OMCRefreshFileInFinder(CFStringRef filePath) { (void)filePath; } // no Finder to refresh

void
OMCGetOperatingSystemVersion(long* outMajorVersion, long* outMinorVersion, long* outPatchVersion)
{
	// What REQUIRED_MAC_OS_MIN_VERSION means on Linux is a Phase 7 decision
	OMC_LINUX_NOT_YET("OMCGetOperatingSystemVersion");
	if(outMajorVersion != nullptr)
		*outMajorVersion = 0;
	if(outMinorVersion != nullptr)
		*outMinorVersion = 0;
	if(outPatchVersion != nullptr)
		*outPatchVersion = 0;
}

OMCModifierKeys OMCGetKeyboardModifiers() { OMC_LINUX_NOT_YET("OMCGetKeyboardModifiers"); return 0; }

StSwitchToFront::StSwitchToFront(bool inRestore) noexcept { (void)inRestore; (void)mPreviousFrontAppPID; }
StSwitchToFront::~StSwitchToFront() noexcept { }

#pragma mark - Clipboard (Platform/OMCClipboard.h)

bool OMCIsTextInClipboard() { OMC_LINUX_NOT_YET("OMCIsTextInClipboard"); return false; }
CFStringRef OMCCopyClipboardText(long inReplaceOption) { (void)inReplaceOption; OMC_LINUX_NOT_YET("OMCCopyClipboardText"); return nullptr; }
bool OMCPasteIntoFrontApp() { OMC_LINUX_NOT_YET("OMCPasteIntoFrontApp"); return false; }

#pragma mark - Terminal (Platform/OMCTerminalLauncher.h)

void
OMCExecuteInTerminal(CFStringRef inCommand, bool openInNewWindow, bool bringToFront)
{
	(void)inCommand;
	(void)openInNewWindow;
	(void)bringToFront;
	OMC_LINUX_NOT_YET("OMCExecuteInTerminal");
}

void
OMCExecuteInITerm(CFStringRef inCommand, CFStringRef inShellPath, bool openInNewWindow, bool bringToFront)
{
	(void)inCommand;
	(void)inShellPath;
	(void)openInNewWindow;
	(void)bringToFront;
	OMC_LINUX_NOT_YET("OMCExecuteInITerm");
}

bool OMCIsShDefaultInTerminal() { return false; }
bool OMCIsShDefaultInITerm() { return false; }

#pragma mark - Test host's window access (Platform/OMCTestPlatform.h)

bool OMCTestPlatformDispatchToKeyWindow(CFStringRef inCommandNameOrId, CFTypeRef inContext) { (void)inCommandNameOrId; (void)inContext; OMC_LINUX_NOT_YET("OMCTestPlatformDispatchToKeyWindow"); return false; }
bool OMCTestPlatformHasWindow(CFStringRef inWindowUUID) { (void)inWindowUUID; OMC_LINUX_NOT_YET("OMCTestPlatformHasWindow"); return false; }
bool OMCTestPlatformDispatchToWindow(CFStringRef inWindowUUID, CFStringRef inCommandNameOrId, CFTypeRef inContext) { (void)inWindowUUID; (void)inCommandNameOrId; (void)inContext; OMC_LINUX_NOT_YET("OMCTestPlatformDispatchToWindow"); return false; }
bool OMCTestPlatformCloseWindow(CFStringRef inWindowUUID) { (void)inWindowUUID; OMC_LINUX_NOT_YET("OMCTestPlatformCloseWindow"); return false; }
void OMCTestPlatformRequestQuit(void) { OMC_LINUX_NOT_YET("OMCTestPlatformRequestQuit"); }

#pragma mark - ActionUI add-ons and models (Platform/OMCActionUIAddOns.h, OMCActionUIModels.h)

void OMCRegisterActionUIAddOns(void) { OMC_LINUX_NOT_YET("OMCRegisterActionUIAddOns"); }
void OMCPlatformForgetActionUIModel(CFStringRef inWindowUUID) { (void)inWindowUUID; OMC_LINUX_NOT_YET("OMCPlatformForgetActionUIModel"); }

#pragma mark - File panels (Platform/OMCFilePanels.h): no answer, as a canceled panel

CFURLRef
OMCPlatformRunSavePanel(CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath,
						CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inAdditonalFlags)
{
	(void)inClientName; (void)inMessage; (void)inDefaultName; (void)inDefaultDirPath;
	(void)inIdentifier; (void)inPrompt; (void)inAllowedContentTypes; (void)inAdditonalFlags;
	OMC_LINUX_NOT_YET("OMCPlatformRunSavePanel");
	return nullptr;
}

CFArrayRef
OMCPlatformRunOpenPanel(CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath,
						CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inAdditonalFlags)
{
	(void)inClientName; (void)inMessage; (void)inDefaultName; (void)inDefaultDirPath;
	(void)inIdentifier; (void)inPrompt; (void)inAllowedContentTypes; (void)inAdditonalFlags;
	OMC_LINUX_NOT_YET("OMCPlatformRunOpenPanel");
	return nullptr;
}

#pragma mark - Alerts (Platform/OMCAlerts.h): the text goes to the log, so it is not lost

OMCAlertResponse
OMCPlatformShowAlert(OMCAlertLevel inLevel, CFStringRef inHeader, CFStringRef inMessage,
					CFStringRef inDefaultButton, CFStringRef inAlternateButton, CFStringRef inOtherButton)
{
	(void)inLevel; (void)inDefaultButton; (void)inAlternateButton; (void)inOtherButton;
	OMC_LINUX_NOT_YET("OMCPlatformShowAlert");
	OMCLogMessage("alert not shown: %s: %s", OMCLogCString(inHeader).c_str(), OMCLogCString(inMessage).c_str());
	return kOMCAlertNoResponse;
}

void
OMCPlatformShowNotice(CFStringRef inHeader, CFStringRef inMessage, CFStringRef inButton, CFURLRef inIconURL)
{
	(void)inButton; (void)inIconURL;
	OMC_LINUX_NOT_YET("OMCPlatformShowNotice");
	OMCLogMessage("notice not shown: %s: %s", OMCLogCString(inHeader).c_str(), OMCLogCString(inMessage).c_str());
}

#pragma mark - Window host (Platform/OMCWindowHost.h): no window, as a document that cannot load

std::unique_ptr<OMCHostedWindow>
OMCCreateHostedWindow(const OMCHostedWindowSpec &inSpec, std::function<void()> inOnClosedByUser)
{
	(void)inSpec;
	(void)inOnClosedByUser;
	OMC_LINUX_NOT_YET("OMCCreateHostedWindow");
	return nullptr;
}

void OMCResetHostedWindowCascading() { }
int OMCOpenHostedWindowCount() { return 0; } // true while OMCCreateHostedWindow makes none

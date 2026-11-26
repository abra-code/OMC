//
//  OMCActionUIAddOns.cpp
//  Abracode
//
//  The macOS add-ons. Each is linked via its own ActionUI Swift package (see project setup) and
//  exposes a plain C entry point (@_cdecl) rather than an Objective-C class, so it is
//  forward-declared here - it is not emitted into a generated -Swift.h.
//

#include "OMCActionUIAddOns.h"

#include <CoreFoundation/CoreFoundation.h>

extern "C" void ActionUIQuickLook_register(void);
extern "C" void ActionUICachedImage_register(void);
extern "C" void ActionUIRichText_register(void);
extern "C" void ActionUIDiff_register(void);
extern "C" void ActionUIChatCore_register(void);
extern "C" void ActionUIChatOpenAI_register(void);
extern "C" void ActionUIChatACP_register(void);
extern "C" void ActionUIHostSurface_register(void);

// The Chat element's ACP transports start an agent as a local process (acp) or reach one through
// a bridge (acp-remote), with the command a Chat window's configuration names. That configuration
// can be set at run time, by a dialog-control message for one, so only an applet that uses agents
// gets the transports: it says so in its Info.plist with CommandChatEnablesACP set to true.
// Without them a Chat window that asks for acp falls back to the local transport and logs it.
static bool AppletEnablesChatACP(void)
{
	CFBundleRef mainBundle = ::CFBundleGetMainBundle();
	if(mainBundle == nullptr)
		return false;
	CFTypeRef value = ::CFBundleGetValueForInfoDictionaryKey(mainBundle, CFSTR("CommandChatEnablesACP"));
	return (value != nullptr) && (::CFGetTypeID(value) == ::CFBooleanGetTypeID()) && ::CFBooleanGetValue((CFBooleanRef)value);
}

extern "C" void OMCRegisterActionUIAddOns(void)
{
	static bool sRegistered = false; // main thread only
	if(sRegistered)
		return;
	sRegistered = true;
	ActionUIQuickLook_register();
	ActionUICachedImage_register();
	ActionUIRichText_register();
	ActionUIDiff_register();
	// The Chat element with its built-in local transports and the OpenAI-compatible one; the ACP
	// transports only on request (see AppletEnablesChatACP)
	ActionUIChatCore_register();
	ActionUIChatOpenAI_register();
	if(AppletEnablesChatACP())
		ActionUIChatACP_register();
	ActionUIHostSurface_register();
}

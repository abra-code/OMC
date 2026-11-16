//
//  OMCActionUIAddOns.cpp (Linux)
//  Abracode
//
//  The Linux add-ons (Platform/OMCActionUIAddOns.h): ActionUI's add-ons that have a GTK element,
//  linked into the engine through their Swift packages (OMC's Package.swift), each registered
//  through its plain C entry point, as on macOS (Platform/Apple/OMCActionUIAddOns.cpp). macOS has
//  two more, QuickLook and Chat, which have no Linux element.
//

#include "OMCActionUIAddOns.h"

extern "C" void ActionUIRichText_register(void);
extern "C" void ActionUICachedImage_register(void);
extern "C" void ActionUIDiff_register(void);
extern "C" void ActionUIHostSurface_register(void);

extern "C" void OMCRegisterActionUIAddOns(void)
{
	static bool sRegistered = false; // main thread only
	if(sRegistered)
		return;
	sRegistered = true;
	ActionUIRichText_register();
	ActionUICachedImage_register();
	ActionUIDiff_register();
	ActionUIHostSurface_register();
}

//
//  OMCActionUIAddOns.cpp
//  Abracode
//
//  The macOS add-ons. Each is linked via its own ActionUI Swift package (see project setup) and
//  exposes a plain C entry point (@_cdecl) rather than an Objective-C class, so it is
//  forward-declared here - it is not emitted into a generated -Swift.h.
//

#include "OMCActionUIAddOns.h"

extern "C" void ActionUIQuickLook_register(void);
extern "C" void ActionUICachedImage_register(void);
extern "C" void ActionUIRichText_register(void);
extern "C" void ActionUIDiff_register(void);
extern "C" void ActionUIChat_register(void);
extern "C" void ActionUIHostSurface_register(void);

extern "C" void OMCRegisterActionUIAddOns(void)
{
	ActionUIQuickLook_register();
	ActionUICachedImage_register();
	ActionUIRichText_register();
	ActionUIDiff_register();
	ActionUIChat_register();
	ActionUIHostSurface_register();
}

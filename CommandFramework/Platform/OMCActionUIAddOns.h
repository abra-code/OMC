//
//  OMCActionUIAddOns.h
//  Abracode
//
//  The optional ActionUI add-ons an OMC host links: each registers extra element types, so that
//  ActionUI dialogs can use them. Which add-ons exist is per platform (macOS:
//  Platform/Apple/OMCActionUIAddOns.cpp; Linux: Platform/Linux/OMCActionUIAddOns.cpp, the ones with
//  a GTK element).
//
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Register every add-on element type, on the main thread, before any dialog is built. Only the first
// call registers: the applet calls it at launch, and a built-in window that needs an add-on (the About
// window's RichText) calls it too, for a host that did not launch as an applet.
void OMCRegisterActionUIAddOns(void);

#ifdef __cplusplus
}
#endif

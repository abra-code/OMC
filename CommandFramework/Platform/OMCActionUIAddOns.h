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

// Register every add-on element type. Once, on the main thread, before any dialog is built.
void OMCRegisterActionUIAddOns(void);

#ifdef __cplusplus
}
#endif

//
//  OMCActionUIModels.h
//  Abracode
//
//  ActionUI keeps each window's model (its loaded description and every element's value and
//  state) until its host removes it, and the ActionUI remote bridge reads windows by id from those
//  models. OMCActionUIModelLifetime.h decides when OMC removes one; this is the removal,
//  implemented per platform: Platform/Apple/OMCActionUIModels.mm (ActionUIObjC).
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

// Main thread. Forgets the window's ActionUI model; afterwards the window is unknown to ActionUI,
// as one never loaded. An unknown window is ignored.
void OMCPlatformForgetActionUIModel(CFStringRef inWindowUUID);

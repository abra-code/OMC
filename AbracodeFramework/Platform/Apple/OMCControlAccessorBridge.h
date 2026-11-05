//
//  OMCControlAccessorBridge.h
//  Abracode
//
//  macOS: an OMCDialogControlAccessor over a window controller that adopts the Objective-C
//  OMCControlAccessor protocol. Objective-C++ only.
//

#pragma once
#include "OMCDialogControlAccessor.h"
#import "OMCControlAccessor.h"
#include <memory>

// The bridge holds the controller weakly, so a dialog that outlives its window does nothing,
// and it catches Objective-C exceptions, which must not cross into the C++ engine.
std::unique_ptr<OMCDialogControlAccessor> OMCMakeControlAccessorBridge(id<OMCControlAccessor> inController);

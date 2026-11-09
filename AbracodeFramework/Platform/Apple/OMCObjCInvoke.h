//
//  OMCObjCInvoke.h
//  Abracode
//
//  INVOKE's Objective-C half, for Objective-C callers: the nib dialogs send messages to their
//  controls too (OMCNibWindowController.mm). Portable callers use Platform/OMCInvoke.h.
//

#pragma once
#import <Foundation/Foundation.h>

// Sends each message of inMessages (arrays of strings: the selector, then its arguments) to
// inTarget through NSInvocation, converting each argument to the type the method takes. A message
// the target does not respond to, or one that raises, is logged and skipped.
void OMCSendObjCMessages(id inTarget, CFArrayRef inMessages) noexcept;

/*
 *  MessagePortSend.h
 *  Contextual Menu Workshop
 *
 *  Created by Tomasz Kukielka on 11/25/06.
 *  Copyright 2006 Abracode. All rights reserved.
 *
 */

#pragma once

#include <Carbon/Carbon.h>

SInt32 SendMessageToRemotePortWithoutResponse(CFStringRef inPort, SInt32 inMsgId, CFDataRef dataToSend);
CFDataRef SendMessageToRemotePortWithResponse(CFStringRef inPort, SInt32 inMsgId, CFDataRef dataToSend);


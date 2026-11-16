//
//  OMCDeferredProgress.h
//  Abracode
//
//  Created by Tomasz Kukielka on 8/2/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//
//  A command's PROGRESS (Command.plist): parses the tasks' output into a total progress (steps,
//  counter, task count, or indeterminate) and shows it in the progress window
//  (OMCProgressWindow.h), at once or after DELAY seconds. Stop in the window stops the tasks'
//  processes. Portable C++ (OMCDeferredProgress.cpp). Main thread only.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <unistd.h>

typedef void *OMCDeferredProgressRef;

OMCDeferredProgressRef OMCDeferredProgressCreate(CFDictionaryRef inProgressParams, CFStringRef inCommandName, CFIndex inTaskCount, CFStringRef inLocTable, CFBundleRef inLocBundle);
void OMCDeferredProgressRelease(OMCDeferredProgressRef inProgressRef);

// Returns true when the user pressed Stop: the tasks' processes have been sent SIGTERM
Boolean OMCDeferredProgressAdvanceProgress(OMCDeferredProgressRef inProgressRef, CFIndex inTaskIndex, pid_t inChildPID, CFStringRef inOutputStr, Boolean isTaskEnded);

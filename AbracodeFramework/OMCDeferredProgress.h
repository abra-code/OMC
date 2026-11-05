//
//  OMCDeferredProgress.h
//  Abracode
//
//  Created by Tomasz Kukielka on 8/2/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#pragma once
#include "OMCProgressParsing.h"

#ifdef __OBJC__

#import <Cocoa/Cocoa.h>

@class OMCProgressWindowController;

@interface OMCDeferredProgress : NSObject
{
	CFObj<CFDictionaryRef> mProgressParams;
	UInt32			mProgressType;
	StepsParams		mStepsParams;
	CounterParams	mCounterParams;
	CFIndex			mTaskCount;
	OMCTaskProgress *mTasks;
	CFObj<CFRunLoopTimerRef> mDeferTimer;
	CFObj<CFStringRef> mTitleString;
	OMCProgressWindowController *mController;

	CFObj<CFStringRef> mLastLineStr;
	CFObj<CFStringRef> mLastPartialLineStr;		
}

- (id)initWithParams:(CFDictionaryRef)inParams forCommand:(CFStringRef)inCommandName taskCount:(CFIndex)inTaskCount locTable:(CFStringRef)inLocTable locBundle:(CFBundleRef)inLocBundle;
- (Boolean)advanceProgressForTask:(CFIndex)inTaskIndex childPid:(pid_t)inChildPID withOutputString:(NSString *)inOutputStr taskEnded:(Boolean)isTaskEnded;
- (void)showProgressWindow;
- (void)calculateOneTaskProgress:(CFIndex)inTaskIndex childPid:(pid_t)inChildPID withLines:(CFArrayRef)inLines taskEnded:(Boolean)isTaskEnded;
- (void)cancelAllChildProcesses;

@end

#endif //__OBJC__


typedef void *OMCDeferredProgressRef;

OMCDeferredProgressRef OMCDeferredProgressCreate(CFDictionaryRef inProgressParams, CFStringRef inCommandName, CFIndex inTaskCount, CFStringRef inLocTable, CFBundleRef inLocBundle);
void OMCDeferredProgressRelease(OMCDeferredProgressRef inProgressRef);
Boolean OMCDeferredProgressAdvanceProgress(OMCDeferredProgressRef inProgressRef, CFIndex inTaskIndex, pid_t inChildPID, CFStringRef inOutputStr, Boolean isTaskEnded);

//
//  OMCDeferredProgress.mm
//  Abracode
//
//  Created by Tomasz Kukielka on 8/2/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#import "OMCDeferredProgress.h"
#import "OMCProgressWindowController.h"
#include "ACFDict.h"
#include "DebugSettings.h"
#include <vector>

void OMCDeferredProgressCallBack(CFRunLoopTimerRef timer, void* info);

inline double CalculateTotalProgress(OMCTaskProgress *allTasks, CFIndex inCount)
{
	double outTotal = 0.0;
	for(CFIndex i = 0; i < inCount; i++)
	{
		outTotal += allTasks[i].progress;
	}
	
	return round(outTotal/(double)inCount);
}

@implementation OMCDeferredProgress

// Command.plist SCHEMA SOURCE OF TRUTH — the PROGRESS dict (TITLE, DELAY, and the
// mutually exclusive DETERMINATE_STEPS / DETERMINATE_COUNTER sub-dicts parsed above).
// Adding/removing/renaming/deprecating/retyping any key here REQUIRES updating the matching
// verifier schema and rebuilding the skill, else the Command.plist verifier drifts:
//   verifier schema: Distribution/AppletBuilder.app/Contents/Library/command_verifier/schemas/PROGRESS.json
//   rebuild skill:   python3 Skill/build_skill.py
-(id)initWithParams:(CFDictionaryRef)inParams forCommand:(CFStringRef)inCommandName taskCount:(CFIndex)inTaskCount locTable:(CFStringRef)inLocTable locBundle:(CFBundleRef)inLocBundle
{
	self = [super init];
    if(self == nil)
		return nil;

	
#if _DEBUG_
    NSLog(@"OMCDeferredProgress = %p", (__bridge void *)self);
#endif

	mProgressType = (inTaskCount > 1) ? kOMCProgressDeterminateTaskCount : kOMCProgressIndeterminate;
	mProgressParams.Adopt(inParams, kCFObjRetain);

	mTaskCount = inTaskCount;
	mTasks = new OMCTaskProgress[mTaskCount];

	ACFDict params(mProgressParams);

    CFDictionaryRef stepsDict = NULL;
    params.GetValue( CFSTR("DETERMINATE_STEPS"), stepsDict );
    if(stepsDict != NULL)
    {//either steps:
        mProgressType = kOMCProgressDeterminateSteps;
        mStepsParams.Init(stepsDict, inLocTable, inLocBundle);
    }
    else
    {//or counter:
        CFDictionaryRef counterDict = NULL;
        params.GetValue( CFSTR("DETERMINATE_COUNTER"), counterDict );
        if(counterDict != NULL)
        {
            mProgressType = kOMCProgressDeterminateCounter;
            mCounterParams.Init(counterDict, inLocTable, inLocBundle);
        }
    }

	CFObj<CFStringRef> titleStr;
	if( params.CopyValue( CFSTR("TITLE"), titleStr ) )
	{
		if( (titleStr != NULL) && (inLocTable != NULL) && (inLocBundle != NULL) )
			titleStr.Adopt( CFCopyLocalizedStringFromTableInBundle( titleStr, inLocTable, inLocBundle, "") );
		mTitleString.Swap(titleStr);
	}

	if(mTitleString == NULL)
	{
		mTitleString.Adopt(inCommandName, kCFObjRetain);
	}

	mController = NULL;

	double delay = 0.0;
	params.GetValue( CFSTR("DELAY"), delay );
	
	if( delay > 0.0 )
	{//use CFRunLoopTimer so we don't rely on existance of NSRunLoop (those are not toll-free bridged equivalents)
        CFRunLoopTimerContext timerContext = {0, (__bridge void *)self, NULL, NULL, NULL};
		mDeferTimer.Adopt( CFRunLoopTimerCreate(
											   kCFAllocatorDefault,
											   CFAbsoluteTimeGetCurrent() + delay,
											   0,		// interval
											   0,		// flags
											   0,		// order
											   OMCDeferredProgressCallBack,
											   &timerContext) );
		
		if(mDeferTimer != NULL)
		{
			CFRunLoopAddTimer(CFRunLoopGetCurrent(), mDeferTimer, kCFRunLoopCommonModes);
		}
	}
	else
	{
		[self showProgressWindow];
	}
	
	return self;
}

- (void)dealloc
{
	if(mDeferTimer != NULL)
	{
		CFRunLoopTimerInvalidate(mDeferTimer);
		mDeferTimer.Release();
	}

	if( mController != NULL )
	{
		[mController close];
		mController = NULL;
	}

	delete [] mTasks;
	mTasks = NULL;
}

// returns true if user cancelled
- (Boolean)advanceProgressForTask:(CFIndex)inTaskIndex childPid:(pid_t)inChildPID withOutputString:(NSString *)inOutputStr taskEnded:(Boolean)isTaskEnded
{
	TRACE_CSTR("advanceProgressForTask: %s\n", inOutputStr.UTF8String);

    CFObj<CFArrayRef> lineArray( SplitStringIntoLines((__bridge CFStringRef)inOutputStr, mLastPartialLineStr) );
	CFIndex lineCount = 0;
	if(lineArray != NULL)
		lineCount = ::CFArrayGetCount(lineArray);

	if(lineCount > 0)
	{
		CFStringRef lastLine = (CFStringRef)::CFArrayGetValueAtIndex(lineArray, lineCount-1);//get last line
		mLastLineStr.Adopt(lastLine, kCFObjRetain);
	}

	[self calculateOneTaskProgress:inTaskIndex childPid:inChildPID withLines:(CFArrayRef)lineArray taskEnded:isTaskEnded];

	if(mController != NULL)
	{//already shown up
		if( [mController isCanceled] )//calcellation is passive this way, maybe we need to send notification and make it active
		{
			[self cancelAllChildProcesses];
			return true;
		}

		double totalProgress = -1.0;
		if( mProgressType != kOMCProgressIndeterminate)
			totalProgress = CalculateTotalProgress(mTasks, mTaskCount);
		
        [mController setProgress:totalProgress text:(__bridge NSString *)(CFStringRef)mLastLineStr];
	}
	
	return false;
}

- (void)calculateOneTaskProgress:(CFIndex)inTaskIndex childPid:(pid_t)inChildPID withLines:(CFArrayRef)inLines taskEnded:(Boolean)isTaskEnded
{
	if( (inTaskIndex < 0) | (inTaskIndex >= mTaskCount) )
		return;//something wrong, index out of bounds

	OMCTaskProgress &currTaskProgress = mTasks[inTaskIndex];
	currTaskProgress.childPID = inChildPID;

	if( isTaskEnded )
	{
		currTaskProgress.progress = 100.0;
		return;
	}
	
	Boolean suppressNonMatchingText = false;
	CFStringRef lastMatchedLine = NULL;
	
	switch(mProgressType)
	{
		case kOMCProgressDeterminateTaskCount:
		//this one gets progressed only on task end
		break;
		
		case kOMCProgressDeterminateCounter:
			lastMatchedLine = mCounterParams.CalculateProgress(inLines, currTaskProgress);
			suppressNonMatchingText = mCounterParams.suppressNonMatchingText;
		break;
		
		case kOMCProgressDeterminateSteps:
			lastMatchedLine = mStepsParams.CalculateProgress(inLines, currTaskProgress);
			suppressNonMatchingText = mStepsParams.suppressNonMatchingText;
		break;
	
		case kOMCProgressIndeterminate:
		default:
		break;
	}
	
	if( currTaskProgress.statusString != NULL )
	{
		mLastLineStr = currTaskProgress.statusString;
	}
	else
	{
		if( suppressNonMatchingText )
			mLastLineStr.Adopt(lastMatchedLine, kCFObjRetain);

		TRACE_CSTR("calculateOneTaskProgress: CalculateProgress returned NULL string, using mLastLineStr=%s\n",
                   ((__bridge NSString *)(CFStringRef)mLastLineStr).UTF8String);
	}
}

- (void) showProgressWindow
{
	if(mDeferTimer != NULL)//if called from timer
	{
		CFRunLoopTimerInvalidate(mDeferTimer);
		mDeferTimer.Release();
	}
	
	if(mController == NULL)
	{
		mController = [[OMCProgressWindowController alloc] initWithWindowNibName:@"progress"];
        [[mController window] setTitle:(__bridge NSString *)(CFStringRef)mTitleString];

		NSString *frameAutosaveName = [NSString stringWithFormat: @"omc_progress_window %@", (__bridge NSString *)(CFStringRef)mTitleString];
		[mController setWindowFrameAutosaveName:frameAutosaveName];
		
		double totalProgress = -1.0;
		if( mProgressType != kOMCProgressIndeterminate)
			totalProgress = CalculateTotalProgress(mTasks, mTaskCount);

		if(mLastLineStr != NULL)
		{
            [mController setProgress:totalProgress text:(__bridge NSString *)(CFStringRef)mLastLineStr];
			mLastLineStr.Release();
		}
		else
		{
			[mController setProgress:totalProgress text:@""];
		}

		[mController showWindow:self];
	}
}

- (void)cancelAllChildProcesses
{
	pid_t myPID = getpid();
	pid_t myGroupPID = getpgid( myPID );

	for(int i = 0; i < mTaskCount; i++)
	{
		if( mTasks[i].childPID > 0)
		{			
			//omc_popen tries to create a new process in separate group
			//this way it can be killed with all its subchildren
			pid_t childGroupPID = getpgid(mTasks[i].childPID);
			if( (childGroupPID > 0) && (childGroupPID != myGroupPID) )
				killpg(childGroupPID, SIGTERM);//separate group for that child process, safe to kill the whole group
			else if( mTasks[i].childPID != myPID )
				kill(mTasks[i].childPID, SIGTERM); //just kill the child process alone, may not kill all subchildren
		}
	}

}

@end //OMCDeferredProgress


void OMCDeferredProgressCallBack(CFRunLoopTimerRef timer, void* info)
{
#pragma unused (timer)
	
	@autoreleasepool
	{
		@try
		{
            OMCDeferredProgress *__weak myProgress = (__bridge OMCDeferredProgress *)info;
			[myProgress showProgressWindow];
		
		}
		@catch (NSException *localException)
		{
			NSLog(@"OMCDeferredProgressCallBack received exception: %@", localException);
		}
	} //@autoreleasepool
}


OMCDeferredProgressRef
OMCDeferredProgressCreate(CFDictionaryRef inProgressParams, CFStringRef inCommandName, CFIndex inTaskCount, CFStringRef inLocTable, CFBundleRef inLocBundle)
{
	OMCDeferredProgress *myProgress = NULL;
    @try
    {
        myProgress = [[OMCDeferredProgress alloc] initWithParams:inProgressParams forCommand:inCommandName taskCount:inTaskCount locTable:inLocTable locBundle:inLocBundle];
    
    }
    @catch (NSException *localException)
    {
    
        NSLog(@"OMCDeferredProgressCreate received exception: %@", localException);
    }

    return (OMCDeferredProgressRef)CFBridgingRetain(myProgress);
}

void
OMCDeferredProgressRelease(OMCDeferredProgressRef inProgressRef)
{
    @try
    {
        OMCDeferredProgress *__strong myProgress = (OMCDeferredProgress *)CFBridgingRelease(inProgressRef);
        myProgress = nil;
    }
    @catch (NSException *localException)
    {
        NSLog(@"OMCDeferredProgressRelease received exception: %@", localException);
    }
}

Boolean
OMCDeferredProgressAdvanceProgress(OMCDeferredProgressRef inProgressRef, CFIndex inTaskIndex, pid_t inChildPID, CFStringRef inOutputStr, Boolean isTaskEnded)
{
	Boolean userCancelled = false;
    @try
    {
        OMCDeferredProgress *__weak myProgress = (__bridge OMCDeferredProgress *)inProgressRef;
        userCancelled = [myProgress advanceProgressForTask:inTaskIndex childPid:inChildPID withOutputString:(__bridge NSString *)inOutputStr taskEnded:isTaskEnded];
    }
    @catch (NSException *localException)
    {
        NSLog(@"OMCDeferredProgressAdvanceProgress received exception: %@", localException);
    }
	return userCancelled;
}

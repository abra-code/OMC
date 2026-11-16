//
//  OMCDeferredProgress.cpp
//  Abracode
//
//  Created by Tomasz Kukielka on 8/2/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//
//  A command's PROGRESS (OMCDeferredProgress.h). Was an Objective-C object (OMCDeferredProgress.mm)
//  with a CFRunLoopTimer for DELAY; the logic is unchanged, the delay is an
//  OMCMainThreadSignal::ScheduleAfter call, canceled when the progress goes away first.
//

#include "OMCDeferredProgress.h"
#include "OMCProgressParsing.h"
#include "OMCProgressWindow.h"
#include "OMCMainThreadSignal.h"
#include "ACFDict.h"
#include "ACFString.h"
#include "CFObj.h"
#include "DebugSettings.h"
#include <memory>
#include <vector>
#include <cmath>
#include <signal.h>

namespace
{

double CalculateTotalProgress(const std::vector<OMCTaskProgress> &allTasks)
{
	if(allTasks.empty())
		return -1.0; // indeterminate, as the old 0/0 was
	double outTotal = 0.0;
	for(const OMCTaskProgress &oneTask : allTasks)
		outTotal += oneTask.progress;
	return round(outTotal/(double)allTasks.size());
}

class OMCDeferredProgress
{
public:
							OMCDeferredProgress(CFDictionaryRef inParams, CFStringRef inCommandName, CFIndex inTaskCount, CFStringRef inLocTable, CFBundleRef inLocBundle);

	// Returns true if the user canceled
	bool					AdvanceProgress(CFIndex inTaskIndex, pid_t inChildPID, CFStringRef inOutputStr, bool isTaskEnded);

private:
	void					CalculateOneTaskProgress(CFIndex inTaskIndex, pid_t inChildPID, CFArrayRef inLines, bool isTaskEnded);
	void					ShowProgressWindow();
	void					CancelAllChildProcesses();
	static void				DelayPassed(void *inContext);

	CFObj<CFDictionaryRef>	mProgressParams;
	UInt32					mProgressType {kOMCProgressIndeterminate};
	StepsParams				mStepsParams;
	CounterParams			mCounterParams;
	std::vector<OMCTaskProgress> mTasks;
	CFObj<CFStringRef>		mTitleString;
	std::unique_ptr<OMCProgressWindow> mWindow;
	std::unique_ptr<OMCScheduledCall> mDelay; // after mWindow: canceled before the window closes, as before

	CFObj<CFStringRef>		mLastLineStr;
	CFObj<CFStringRef>		mLastPartialLineStr;
};

// Command.plist SCHEMA SOURCE OF TRUTH - the PROGRESS dict (TITLE, DELAY, and the
// mutually exclusive DETERMINATE_STEPS / DETERMINATE_COUNTER sub-dicts parsed below).
// Adding/removing/renaming/deprecating/retyping any key here REQUIRES updating the matching
// verifier schema and rebuilding the skill, else the Command.plist verifier drifts:
//   verifier schema: Distribution/AppletBuilder.app/Contents/Library/command_verifier/schemas/PROGRESS.json
//   rebuild skill:   python3 Skill/build_skill.py
OMCDeferredProgress::OMCDeferredProgress(CFDictionaryRef inParams, CFStringRef inCommandName, CFIndex inTaskCount, CFStringRef inLocTable, CFBundleRef inLocBundle)
	: mProgressParams(inParams, kCFObjRetain),
	mTasks( (inTaskCount > 0) ? (size_t)inTaskCount : 0 )
{
	mProgressType = (inTaskCount > 1) ? kOMCProgressDeterminateTaskCount : kOMCProgressIndeterminate;

	ACFDict params(mProgressParams);

	CFDictionaryRef stepsDict = nullptr;
	params.GetValue( CFSTR("DETERMINATE_STEPS"), stepsDict );
	if(stepsDict != nullptr)
	{//either steps:
		mProgressType = kOMCProgressDeterminateSteps;
		mStepsParams.Init(stepsDict, inLocTable, inLocBundle);
	}
	else
	{//or counter:
		CFDictionaryRef counterDict = nullptr;
		params.GetValue( CFSTR("DETERMINATE_COUNTER"), counterDict );
		if(counterDict != nullptr)
		{
			mProgressType = kOMCProgressDeterminateCounter;
			mCounterParams.Init(counterDict, inLocTable, inLocBundle);
		}
	}

	CFObj<CFStringRef> titleStr;
	if( params.CopyValue( CFSTR("TITLE"), titleStr ) )
	{
		if( (titleStr != nullptr) && (inLocTable != nullptr) && (inLocBundle != nullptr) )
			titleStr.Adopt( CFCopyLocalizedStringFromTableInBundle( titleStr, inLocTable, inLocBundle, "") );
		mTitleString.Swap(titleStr);
	}

	if(mTitleString == nullptr)
		mTitleString.Adopt(inCommandName, kCFObjRetain);

	double delay = 0.0;
	params.GetValue( CFSTR("DELAY"), delay );

	if( delay > 0.0 )
		mDelay = OMCMainThreadSignal::ScheduleAfter(delay, DelayPassed, this); // canceled when this goes away first
	else
		ShowProgressWindow();
}

//static
void
OMCDeferredProgress::DelayPassed(void *inContext)
{
	static_cast<OMCDeferredProgress *>(inContext)->ShowProgressWindow();
}

bool
OMCDeferredProgress::AdvanceProgress(CFIndex inTaskIndex, pid_t inChildPID, CFStringRef inOutputStr, bool isTaskEnded)
{
	TRACE_CSTR("AdvanceProgress: %s\n", ACFStringToUTF8(inOutputStr).c_str());

	CFObj<CFArrayRef> lineArray( SplitStringIntoLines(inOutputStr, mLastPartialLineStr) );
	CFIndex lineCount = 0;
	if(lineArray != nullptr)
		lineCount = ::CFArrayGetCount(lineArray);

	if(lineCount > 0)
	{
		CFStringRef lastLine = (CFStringRef)::CFArrayGetValueAtIndex(lineArray, lineCount-1);//get last line
		mLastLineStr.Adopt(lastLine, kCFObjRetain);
	}

	CalculateOneTaskProgress(inTaskIndex, inChildPID, lineArray, isTaskEnded);

	if(mWindow != nullptr)
	{//already shown up
		if( mWindow->IsCanceled() )//cancellation is passive this way, maybe we need to send notification and make it active
		{
			CancelAllChildProcesses();
			return true;
		}

		double totalProgress = -1.0;
		if( mProgressType != kOMCProgressIndeterminate)
			totalProgress = CalculateTotalProgress(mTasks);

		mWindow->SetProgress(totalProgress, mLastLineStr);
	}

	return false;
}

void
OMCDeferredProgress::CalculateOneTaskProgress(CFIndex inTaskIndex, pid_t inChildPID, CFArrayRef inLines, bool isTaskEnded)
{
	if( (inTaskIndex < 0) || ((size_t)inTaskIndex >= mTasks.size()) )
		return;//something wrong, index out of bounds

	OMCTaskProgress &currTaskProgress = mTasks[(size_t)inTaskIndex];
	currTaskProgress.childPID = inChildPID;

	if( isTaskEnded )
	{
		currTaskProgress.progress = 100.0;
		return;
	}

	Boolean suppressNonMatchingText = false;
	CFStringRef lastMatchedLine = nullptr;

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

	if( currTaskProgress.statusString != nullptr )
	{
		mLastLineStr = currTaskProgress.statusString;
	}
	else
	{
		if( suppressNonMatchingText )
			mLastLineStr.Adopt(lastMatchedLine, kCFObjRetain);

		TRACE_CSTR("CalculateOneTaskProgress: CalculateProgress returned NULL string, using mLastLineStr=%s\n",
					ACFStringToUTF8(mLastLineStr).c_str());
	}
}

void
OMCDeferredProgress::ShowProgressWindow()
{
	mDelay.reset(); // done, if called when the delay passed

	if(mWindow != nullptr)
		return;

	mWindow = OMCProgressWindow::Create(mTitleString); // titled, its frame remembered as "omc_progress_window <title>"
	if(mWindow == nullptr)
		return;

	double totalProgress = -1.0;
	if( mProgressType != kOMCProgressIndeterminate)
		totalProgress = CalculateTotalProgress(mTasks);

	if(mLastLineStr != nullptr)
	{
		mWindow->SetProgress(totalProgress, mLastLineStr);
		mLastLineStr.Release();
	}
	else
	{
		mWindow->SetProgress(totalProgress, CFSTR(""));
	}

	mWindow->Show();
}

void
OMCDeferredProgress::CancelAllChildProcesses()
{
	pid_t myPID = getpid();
	pid_t myGroupPID = getpgid( myPID );

	for(const OMCTaskProgress &oneTask : mTasks)
	{
		if( oneTask.childPID > 0)
		{
			//omc_popen tries to create a new process in separate group
			//this way it can be killed with all its subchildren
			pid_t childGroupPID = getpgid(oneTask.childPID);
			if( (childGroupPID > 0) && (childGroupPID != myGroupPID) )
				killpg(childGroupPID, SIGTERM);//separate group for that child process, safe to kill the whole group
			else if( oneTask.childPID != myPID )
				kill(oneTask.childPID, SIGTERM); //just kill the child process alone, may not kill all subchildren
		}
	}
}

} // namespace

OMCDeferredProgressRef
OMCDeferredProgressCreate(CFDictionaryRef inProgressParams, CFStringRef inCommandName, CFIndex inTaskCount, CFStringRef inLocTable, CFBundleRef inLocBundle)
{
	return new OMCDeferredProgress(inProgressParams, inCommandName, inTaskCount, inLocTable, inLocBundle);
}

void
OMCDeferredProgressRelease(OMCDeferredProgressRef inProgressRef)
{
	delete static_cast<OMCDeferredProgress *>(inProgressRef); // cancels a pending delay, closes the window
}

Boolean
OMCDeferredProgressAdvanceProgress(OMCDeferredProgressRef inProgressRef, CFIndex inTaskIndex, pid_t inChildPID, CFStringRef inOutputStr, Boolean isTaskEnded)
{
	if(inProgressRef == nullptr)
		return false;
	return static_cast<OMCDeferredProgress *>(inProgressRef)->AdvanceProgress(inTaskIndex, inChildPID, inOutputStr, isTaskEnded);
}

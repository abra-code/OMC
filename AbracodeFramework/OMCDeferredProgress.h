//
//  OMCDeferredProgress.h
//  Abracode
//
//  Created by Tomasz Kukielka on 8/2/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#include <CoreFoundation/CoreFoundation.h>
#include "OMCConstants.h"
#include "CFObj.h"
#include <regex.h>

//single task progress state
typedef struct OMCTaskProgress
{
	double progress;
	pid_t childPID;
	CFIndex nextStepIndex; //for step progress
	CFStringRef statusString;
} OMCTaskProgress;


enum
{
	kTemplateItemString,
	kTemplateItemGroupIndex
};

struct StatusTemplateItem
{
	//takes ownership of the string
	StatusTemplateItem(CFStringRef inString)
		: type(kTemplateItemString), next(NULL)
	{
		item.text = inString;
	}
	
	StatusTemplateItem(CFIndex inGroupIndex)
		: type(kTemplateItemGroupIndex), next(NULL)
	{
		item.groupIndex = inGroupIndex;
	}
	
	~StatusTemplateItem()
	{
		if( (type == kTemplateItemString) && (item.text != NULL) )
			CFRelease(item.text);
		delete next;
	}

	//returns new tail. replaced null head with self if first link
	StatusTemplateItem * AppendToTail(StatusTemplateItem * &ioHead, StatusTemplateItem *inTail)
	{
		if(ioHead == NULL)
			ioHead = this;
		else
			inTail->next = this;
		return this;
	}

	UInt32 type;
	union
	{
		CFStringRef	text;
		CFIndex		groupIndex;
	} item;

	StatusTemplateItem *next;
};

struct RangeAndString
{
	CFRange		range;
	CFStringRef text;
	
	static void Init(RangeAndString *regGroups, CFIndex regGroupCount)
	{
		for(CFIndex i = 0; i < regGroupCount; i++)
		{
			regGroups[i].text = NULL;
			regGroups[i].range = CFRangeMake(-1, -1);
		}

	}

	static void Reset(RangeAndString *regGroups, CFIndex regGroupCount)
	{
		if(regGroups == NULL)
			return;

		for(CFIndex i = 0; i < regGroupCount; i++)
		{
			if( regGroups[i].text != NULL )
			{
				CFRelease(regGroups[i].text);
				regGroups[i].text = NULL;
			}
			regGroups[i].range = CFRangeMake(-1, -1);
		}
	}
	
	CFStringRef GetString(CFStringRef inWholeString, CFIndex wholeStringLen)
	{
		if( inWholeString == NULL )
			return NULL;

		if(text != NULL)
			return text;

		if( (range.location >= 0) && (range.length > 0) && ((range.location + range.length) <= wholeStringLen) )
		{
			text = ::CFStringCreateWithSubstring( kCFAllocatorDefault, inWholeString, range );
		}
		//else: invalid range, sorry can't get string
		
		return text;
	}	
};

struct CounterParams
{
	CounterParams()
		: mStatusTemplate(NULL), counterIndex(0), rangeEndIndex(0), rangeStartIndex(0), rangeStartValue(0.0), rangeEndValue(100.0),
		  isCountdown(false), suppressNonMatchingText(false),
		regExprValid(false)
	{
		memset( &regularExpression, 0, sizeof(regularExpression) );
	}

	~CounterParams();
	
	void Init(CFDictionaryRef counterDict, CFStringRef inLocTable, CFBundleRef inLocBundle);
	CFStringRef CalculateProgress(CFArrayRef inOutputLines, OMCTaskProgress &outTaskProgress);

	regex_t regularExpression;
	StatusTemplateItem *mStatusTemplate;
	CFIndex counterIndex;
	CFIndex rangeEndIndex;
	CFIndex rangeStartIndex;
	double rangeStartValue;
	double rangeEndValue;
	Boolean isCountdown;
	Boolean suppressNonMatchingText;
	Boolean regExprValid;
};

typedef struct OneStep
{
	CFStringRef matchString;
	regex_t regularExpression;
	Boolean regExprValid;
	CFIndex value;
	CFStringRef status;
} OneStep;

struct StepsParams
{
	StepsParams()
		: stepsCount(0), steps(NULL), matchMethod(kMatchContains), matchCompareOptions(0), suppressNonMatchingText(false)
	{
	
	}
	
	~StepsParams();

	void Init(CFDictionaryRef stepsDict, CFStringRef inLocTable, CFBundleRef inLocBundle);
	CFStringRef CalculateProgress(CFArrayRef inOutputLines, OMCTaskProgress &outTaskProgress);

	CFIndex			stepsCount;
	OneStep			*steps;
	UInt8			matchMethod;
	UInt8			matchCompareOptions;//currently only kCFCompareCaseInsensitive
	Boolean			suppressNonMatchingText;

};

enum
{
	kOMCProgressIndeterminate,
	kOMCProgressDeterminateTaskCount,
	kOMCProgressDeterminateCounter,
	kOMCProgressDeterminateSteps
};

#ifdef __OBJC__

#import <Cocoa/Cocoa.h>

@class OMCProgressWindowController;

@interface OMCDeferredProgress : NSObject
{
	CFDictionaryRef mProgressParams;
	UInt32			mProgressType;
	StepsParams		mStepsParams;
	CounterParams	mCounterParams;
	CFIndex			mTaskCount;
	OMCTaskProgress *mTasks;
	CFRunLoopTimerRef mDeferTimer;
	CFStringRef mTitleString;
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

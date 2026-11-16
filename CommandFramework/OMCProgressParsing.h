//
//  OMCProgressParsing.h
//  Abracode
//
//  The PROGRESS rules of a command: how a task's output lines become a progress value and a status
//  line (determinate counter by regular expression, or steps). Portable C++ on CF; the window that
//  shows the progress is OMCDeferredProgress (macOS). Moved here unchanged from OMCDeferredProgress.h.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include "OMCConstants.h"
#include "CFObj.h"
#include <regex.h>

// single task progress state
struct OMCTaskProgress
{
	double progress = 0.0;
	pid_t childPID = 0;
	CFIndex nextStepIndex = 0; //for step progress
	CFObj<CFStringRef> statusString;
};


enum
{
	kTemplateItemString,
	kTemplateItemGroupIndex
};

struct StatusTemplateItem
{
	//takes ownership of the string
	StatusTemplateItem(CFStringRef inString)
		: type(kTemplateItemString), text(inString), groupIndex(0), next(NULL)
	{
	}

	StatusTemplateItem(CFIndex inGroupIndex)
		: type(kTemplateItemGroupIndex), groupIndex(inGroupIndex), next(NULL)
	{
	}

	~StatusTemplateItem()
	{
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
	CFObj<CFStringRef> text;	// kTemplateItemString
	CFIndex groupIndex;			// kTemplateItemGroupIndex

	StatusTemplateItem *next;
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
	bool isCountdown;
	bool suppressNonMatchingText;
	Boolean regExprValid;
};

struct OneStep
{
	CFStringRef matchString = NULL;
	regex_t regularExpression = {};
	Boolean regExprValid = false;
	CFIndex value = 0;
	CFObj<CFStringRef> status;
};

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
	bool			suppressNonMatchingText;

};

enum
{
	kOMCProgressIndeterminate,
	kOMCProgressDeterminateTaskCount,
	kOMCProgressDeterminateCounter,
	kOMCProgressDeterminateSteps
};

// Splits a task's new output into whole lines; a trailing partial line is kept in
// ioLeftPartialString and joined to the next output. Retained result, or NULL.
CFArrayRef SplitStringIntoLines(CFStringRef inString, CFObj<CFStringRef> &ioLeftPartialString);

//
//  OMCDeferredProgress.m
//  Abracode
//
//  Created by Tomasz Kukielka on 8/2/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#import "OMCDeferredProgress.h"
#import "OMCProgressWindowController.h"
#include "ACFDict.h"
#include "CMUtils.h"
#include <vector>

/*
pseudo plist with proposed enhancements:

<key>PROGRESS</key>
<dict>
	<key>DELAY</key>
	<real>0</real>
	<key>DETERMINATE_COUNTER</key>
	<dict>
		<key>REGULAR_EXPRESSION_MATCH</key>
		<string>#+ (.+)%</string>
		<string>Completed task (.+) of (.+)\.</string>
		<string>Downloaded (.+)k of (.+)k\.</string>
		
		<key>STATUS</key>
		<string>\1% done.</string>
		<string>Task \1 of \2 done.</string>
		<string>\1k of \2k downloaded.</string>

		<key>SUBSTRING_INDEX_FOR_COUNTER</key>
		<integer>1</integer> {substring 1 is the counter}
		<key>SUBSTRING_INDEX_FOR_RANGE_END</key>
		<integer>2</integer> {substring 2 points to range end. default = 100}
		<key>SUBSTRING_INDEX_FOR_RANGE_START</key>
		<integer>0</integer> {substring 0 is invalid = fall back to default range start=0}

		<key>RANGE_START</key>
		<real>0</real> {default value}
		<key>RANGE_END</key>
		<real>100</real> {default value}

		<key>IS_COUNTDOWN</key>
		<false/> {default value}
		<true/>

	</dict>
	<key>DETERMINATE_STEPS</key>
	<dict>
		<key>MATCH_METHOD</key>
		<string>match_exact</string>
		<string>match_contains</string> {default value}
		<string>match_regular_expression</string>
		<key>COMPARE_CASE_INSENSITIVE</key>
		<false/> {default value}
		<true/>

		<key>STEPS</key>
		<array>
			<dict>
				<key>STRING</key>
				<string>Starting</string>
				<key>VALUE</key>
				<integer>0<integer>
			</dict>
			<dict>
				<key>STRING</key>
				<string>Warming Up</string>
				<key>VALUE</key>
				<integer>10<integer>
			</dict>
			<dict>
				<key>STRING</key>
				<string>Full Steam Ahead</string>
				<key>VALUE</key>
				<integer>50<integer>
			</dict>
			<dict>
				<key>STRING</key>
				<string>Cleaning Up</string>
				<key>VALUE</key>
				<integer>90<integer>
			</dict>
			<dict>
				<key>STRING</key>
				<string>The End</string>
				<key>VALUE</key>
				<integer>100<integer>
			</dict>
		</array>
	</dict>
</dict>

*/

CFArrayRef SplitStringIntoLines(CFStringRef inString, CFStringRef &ioLeftPartialString)
{
	if( (inString == NULL) && (ioLeftPartialString == NULL) )
		return NULL;

	CFMutableArrayRef outArray = ::CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);

	CFIndex theSize = 0;
	if(inString != NULL)
		theSize = ::CFStringGetLength(inString);

	if(theSize == 0)
	{//could be the last output string. if we have anything partially left from previous run, we better output it now
		if(ioLeftPartialString != NULL)
		{
			::CFArrayAppendValue(outArray, ioLeftPartialString);
			::CFRelease(ioLeftPartialString);
			ioLeftPartialString = NULL;
		}
		return outArray;
	}

	CFStringInlineBuffer inlineBuff;
	CFStringInitInlineBuffer( inString, &inlineBuff, CFRangeMake(0, theSize) );
	
	CFIndex firstCharIndex = 0;
	UniChar oneChar;

	while( firstCharIndex < theSize)
	{
		oneChar = CFStringGetCharacterFromInlineBuffer( &inlineBuff, firstCharIndex );
		if( (oneChar != (UniChar)'\n') && (oneChar != (UniChar)'\r') )//skip line breaks in front
			break;
		firstCharIndex++;
	}
	
	//if there are any line breaks in front then the last left-over was the complete line so add it now
	if( (firstCharIndex > 0) && (ioLeftPartialString != NULL) )
	{
		::CFArrayAppendValue(outArray, ioLeftPartialString);
		::CFRelease(ioLeftPartialString);
		ioLeftPartialString = NULL;
	}

	if(firstCharIndex == theSize)
		return NULL;
	
	CFIndex i = firstCharIndex;
	CFIndex lineStartIndex = firstCharIndex;

	while(i < theSize)
	{
		oneChar = CFStringGetCharacterFromInlineBuffer( &inlineBuff, i );
		if( (oneChar == (UniChar)'\n') || (oneChar == (UniChar)'\r') )
		{//found line break
			if( (i-lineStartIndex) > 0 )
			{

				CFStringRef oneString = ::CFStringCreateWithSubstring( kCFAllocatorDefault, inString, CFRangeMake(lineStartIndex, i-lineStartIndex) );

				if( ioLeftPartialString != NULL )
				{//we need to combine the new text with left-over from previous run
					CFIndex newLen = CFStringGetLength(ioLeftPartialString);
					if(oneString != NULL)
						newLen += CFStringGetLength(oneString);
					
					CFMutableStringRef combinedStrings = CFStringCreateMutableCopy(kCFAllocatorDefault, newLen, ioLeftPartialString);
					::CFRelease(ioLeftPartialString);
					ioLeftPartialString = NULL;
					if(oneString != NULL)
					{
						::CFStringAppend(combinedStrings, oneString);
						::CFRelease(oneString);
					}
					oneString = combinedStrings;
				}

				if(oneString != NULL)
				{
					::CFArrayAppendValue(outArray, oneString);
					::CFRelease(oneString);
				}
			}
			lineStartIndex = i+1;//first character after this line break
		}
		i++;
	}

	if( (i == theSize) && (i > lineStartIndex) )//last string left - this is partial line content
	{
		CFStringRef oneString = ::CFStringCreateWithSubstring( kCFAllocatorDefault, inString, CFRangeMake(lineStartIndex, i-lineStartIndex) );

		if(ioLeftPartialString != NULL)
		{//partial line adding to partial line? it is probably unlinkely to happen but let's add the pieces together
			CFIndex newLen = CFStringGetLength(ioLeftPartialString);
			if(oneString != NULL)
				newLen += CFStringGetLength(oneString);
			
			CFMutableStringRef combinedStrings = CFStringCreateMutableCopy(kCFAllocatorDefault, newLen, ioLeftPartialString);
			::CFRelease(ioLeftPartialString);
			ioLeftPartialString = NULL;
			if(oneString != NULL)
			{
				::CFStringAppend(combinedStrings, oneString);
				::CFRelease(oneString);
			}
			oneString = combinedStrings;
		}
		
		ioLeftPartialString = oneString;
	}

	return outArray;
}

StatusTemplateItem *
SplitStatusTemplateString(CFStringRef inString)
{
	if(inString == NULL)
		return NULL;

	CFIndex theSize = ::CFStringGetLength(inString);
	if(theSize == 0)
		return NULL;

	StatusTemplateItem *linkHead = NULL;
	StatusTemplateItem *linkTail = NULL;

	CFStringInlineBuffer inlineBuff;
	CFStringInitInlineBuffer( inString, &inlineBuff, CFRangeMake(0, theSize) );

	UniChar oneChar;
	CFIndex i = 0;
	CFIndex rangeStart = 0;
	Boolean escapedChar = false;
	while(i < theSize)
	{
		oneChar = CFStringGetCharacterFromInlineBuffer( &inlineBuff, i );
		//backslash breaks the string sequence and one item needs to be flushed
		if( (oneChar == '\\') && ((i + 1) < theSize) )
		{//skip backslash but flush if we already had a string
			if(i > rangeStart)
			{
				CFStringRef oneString = ::CFStringCreateWithSubstring( kCFAllocatorDefault, inString, CFRangeMake(rangeStart, i-rangeStart) );
				if(oneString != NULL)
				{
					StatusTemplateItem *newItem = new StatusTemplateItem(oneString);//takes ownership of the string
					linkTail = newItem->AppendToTail(linkHead, linkTail);
				}
			}

			i++;
			rangeStart = i;//next string will start after skipped backslash
			oneChar = CFStringGetCharacterFromInlineBuffer( &inlineBuff, i );
			escapedChar = true;
		}
		else
		{
			escapedChar = false;
		}
		
		if( !escapedChar && (oneChar == '$') && ((i + 1) < theSize) )
		{
			//flush if we already had string
			if(i > rangeStart)
			{
				CFStringRef oneString = ::CFStringCreateWithSubstring( kCFAllocatorDefault, inString, CFRangeMake(rangeStart, i-rangeStart) );
				if(oneString != NULL)
				{
					StatusTemplateItem *newItem = new StatusTemplateItem(oneString);//takes ownership of the string
					linkTail = newItem->AppendToTail(linkHead, linkTail);
				}
			}

			rangeStart = i;//pessimistic scenario is that there is no number afer $ sign, and in this case we will start regular string here
		
			i++;

			CFIndex numStart = i;
			CFIndex numEnd = i;
			while(i < theSize)
			{
				oneChar = CFStringGetCharacterFromInlineBuffer( &inlineBuff, i );
				if( (oneChar < '0') || (oneChar > '9') )
				{
					numEnd = i;
					i--;//we read in one too much, make the next loop iteration re-read that char
					break;
				}
				i++;
			}

			if(i == theSize)
			{
				numEnd = i;
				i--;//will be incread at the end of the loop, do not let "i" go above theSize here
			}

			if(numEnd > numStart)
			{
				CFStringRef numString = ::CFStringCreateWithSubstring( kCFAllocatorDefault, inString, CFRangeMake(numStart, numEnd-numStart) );
				if(numString != NULL)
				{
					SInt32 groupIndex = ::CFStringGetIntValue(numString);
					CFRelease(numString);
					
					StatusTemplateItem *newItem = new StatusTemplateItem(groupIndex);
					linkTail = newItem->AppendToTail(linkHead, linkTail);
				}
				rangeStart = i+1;//next text range will start after number
			}
		}
		i++;
	}
	
	if( (i == theSize) && (i > rangeStart) )//last string left
	{
		CFStringRef oneString = ::CFStringCreateWithSubstring( kCFAllocatorDefault, inString, CFRangeMake(rangeStart, i-rangeStart) );
		if(oneString != NULL)
		{
			StatusTemplateItem *newItem = new StatusTemplateItem(oneString);//takes ownership of the string
			linkTail = newItem->AppendToTail(linkHead, linkTail);
		}
	}

	return linkHead;
}

CounterParams::~CounterParams()
{
	if(regExprValid)
	{
		::regfree(&regularExpression);
		regExprValid = false;
	}

	delete mStatusTemplate;//this chain is self-destructing, just delete the head
}

void
CounterParams::Init(CFDictionaryRef counterDict, CFStringRef inLocTable, CFBundleRef inLocBundle)
{
	ACFDict counterParams(counterDict);

	Boolean caseInsensitive = false;
	counterParams.GetValue(CFSTR("COMPARE_CASE_INSENSITIVE"), caseInsensitive);

	CFStringRef theStr = NULL;
	if( counterParams.GetValue(CFSTR("REGULAR_EXPRESSION_MATCH"), theStr) )
	{
        std::string matchString = CMUtils::CreateUTF8StringFromCFString(theStr);
		int regFlags = REG_EXTENDED;
		if( caseInsensitive )
			regFlags |= REG_ICASE;
		regExprValid = ::regcomp(&(regularExpression), matchString.c_str(), regFlags) == 0;
	}
	
	
	if( counterParams.CopyValue(CFSTR("STATUS"), theStr) )
	{
		if( (theStr != NULL) && (inLocTable != NULL) && (inLocBundle != NULL) )
		{
			CFStringRef locStr = CFCopyLocalizedStringFromTableInBundle( theStr, inLocTable, inLocBundle, "");
			CFRelease(theStr);
			theStr = locStr;
		}
		
		if(theStr != NULL)
		{
			mStatusTemplate = SplitStatusTemplateString(theStr);
			CFRelease(theStr);
		}
	}

	counterParams.GetValue(CFSTR("SUBSTRING_INDEX_FOR_COUNTER"), counterIndex);
	if( (counterIndex < 0) || (counterIndex > 99) )
		counterIndex = 0;
	counterParams.GetValue(CFSTR("SUBSTRING_INDEX_FOR_RANGE_END"), rangeEndIndex);
	if( (rangeEndIndex < 0) || (rangeEndIndex > 99) )
		rangeEndIndex = 0;
	counterParams.GetValue(CFSTR("SUBSTRING_INDEX_FOR_RANGE_START"), rangeStartIndex);
	if( (rangeStartIndex < 0) || (rangeStartIndex > 99) )
		rangeStartIndex = 0;

	counterParams.GetValue(CFSTR("IS_COUNTDOWN"), isCountdown);
	if(isCountdown)
	{//different defaults for countdown
		rangeStartValue = 0.0;
		rangeEndValue = 0.0;
	}
	counterParams.GetValue(CFSTR("RANGE_START"), rangeStartValue);
	counterParams.GetValue(CFSTR("RANGE_END"), rangeEndValue);
	counterParams.GetValue(CFSTR("SUPPRESS_NON_MATCHING_TEXT"), suppressNonMatchingText);
}

//returns last matched line if any
CFStringRef
CounterParams::CalculateProgress(CFArrayRef inOutputLines, OMCTaskProgress &outTaskProgress)
{
	outTaskProgress.statusString = NULL;//will be set with the last valid statusString

	if( !regExprValid )
		return NULL;

	CFIndex lineCount = 0;
	if(inOutputLines != NULL)
		lineCount = CFArrayGetCount(inOutputLines);

	CFIndex maxSubExpressionIndex = std::max( std::max(counterIndex, rangeEndIndex), rangeStartIndex );
	size_t maxMatchCount = maxSubExpressionIndex+1;
    std::vector<regmatch_t> matches(maxMatchCount);

	CFStringRef lastMatchedLine = NULL;

	for(CFIndex i = 0; i < lineCount; i++)
	{
		CFStringRef oneLine = (CFStringRef)CFArrayGetValueAtIndex(inOutputLines, i);

		int result = -1;
        std::string searchedString = CMUtils::CreateUTF8StringFromCFString(oneLine);
		if(searchedString.length() > 0)
			result = ::regexec( &regularExpression, searchedString.c_str(), maxMatchCount, matches.data(), 0);

		if(result == 0)
		{
			lastMatchedLine = oneLine;
			
			double currValue = 0.0;
			CFIndex startOffset = -1;
            CFIndex endOffset = -1;

			if(counterIndex > 0)
			{
				startOffset = matches[counterIndex].rm_so;
				endOffset = matches[counterIndex].rm_eo;
			}

			if( (startOffset >= 0) && (endOffset > startOffset) )
			{
				const char *numChars = searchedString.c_str() + startOffset;
				CFIndex theLen = endOffset - startOffset;
				CFObj<CFStringRef> numStr( ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)numChars, theLen, kCFStringEncodingUTF8, true), kCFObjDontRetain );
				if(numStr != NULL)
					currValue = ::CFStringGetDoubleValue(numStr);
			}

			startOffset = -1;
			endOffset = -1;

			if(rangeEndIndex > 0)
			{
				startOffset = matches[rangeEndIndex].rm_so;
				endOffset = matches[rangeEndIndex].rm_eo;
			}
			if( (startOffset >= 0) && (endOffset > startOffset) )
			{
				const char *numChars = searchedString.c_str() + startOffset;
				CFIndex theLen = endOffset - startOffset;
				CFObj<CFStringRef> numStr( ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)numChars, theLen, kCFStringEncodingUTF8, true), kCFObjDontRetain );
				if(numStr != NULL)
					rangeEndValue = ::CFStringGetDoubleValue(numStr);
			}
			
			startOffset = -1;
			endOffset = -1;

			if(rangeStartIndex > 0)
			{
				startOffset = matches[rangeStartIndex].rm_so;
				endOffset = matches[rangeStartIndex].rm_eo;
			}

			if( (startOffset >= 0) && (endOffset > startOffset) )
			{
				const char *numChars = searchedString.c_str() + startOffset;
				CFIndex theLen = endOffset - startOffset;
				CFObj<CFStringRef> numStr( ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)numChars, theLen, kCFStringEncodingUTF8, true), kCFObjDontRetain );
				if(numStr != NULL)
					rangeStartValue = ::CFStringGetDoubleValue(numStr);
			}

			double newProgress = 0.0;
			
			if(isCountdown)
			{
				if(currValue > rangeStartValue)//initialization of rangeStartValue. after that it should only get lower
					rangeStartValue = currValue;
				
				//range start value is higher than end value, 
				if(currValue < rangeEndValue)
					currValue = rangeEndValue;

				//if countdown range is from 60 to 10
				//current value = 50, we have progress of 10/50
				
				if( (rangeStartValue - rangeEndValue) != 0.0 )
					newProgress = 100.0*(rangeStartValue - currValue)/(rangeStartValue - rangeEndValue);
			}
			else
			{
				if(currValue > rangeEndValue)
					currValue = rangeEndValue;

				if(currValue < rangeStartValue)
					currValue = rangeStartValue;

				if( (rangeEndValue - rangeStartValue) != 0.0 )
					newProgress = 100.0*(currValue-rangeStartValue)/(rangeEndValue - rangeStartValue);
			}

			//we still want to process the output string even for the same progress amount
			//status string might be different for the same progress amount!
			if( (newProgress >= outTaskProgress.progress) || (outTaskProgress.progress == 0) )
			{
				outTaskProgress.progress = newProgress;
			}
		}
		else
		{
#if 0//_DEBUG_
			NSLog(@"CounterParams::CalculaeProgress() Regex not matched for string = %@", oneLine);
#endif
		}
	}

	return lastMatchedLine;
}


StepsParams::~StepsParams()
{
	if(steps != NULL)
	{
		for(CFIndex stepIndex = 0; stepIndex < stepsCount; stepIndex++)
		{
			if(steps[stepIndex].regExprValid)
			{
				::regfree( &steps[stepIndex].regularExpression );
				steps[stepIndex].regExprValid = false;
			}

            if(steps[stepIndex].status != NULL)
			{
				CFRelease(steps[stepIndex].status);
				steps[stepIndex].status = NULL;
			}
		}
		delete steps;
	}
}

void
StepsParams::Init(CFDictionaryRef stepsDict, CFStringRef inLocTable, CFBundleRef inLocBundle)
{
	ACFDict stepsParams(stepsDict);

	CFStringRef theStr;
	if( stepsParams.GetValue(CFSTR("MATCH_METHOD"), theStr) )
	{
		if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("match_exact"), 0 ) )
		{
			matchMethod = kMatchExact;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("match_contains"), 0 ) )
		{
			matchMethod = kMatchContains;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("match_regular_expression"), 0 ) )
		{
			matchMethod = kMatchRegularExpression;
		}
	}

	Boolean boolValue = false;
	if( stepsParams.GetValue(CFSTR("COMPARE_CASE_INSENSITIVE"), boolValue) && boolValue )
		matchCompareOptions |= kCFCompareCaseInsensitive;						

	stepsParams.GetValue(CFSTR("SUPPRESS_NON_MATCHING_TEXT"), suppressNonMatchingText);

	CFArrayRef stepsArray = NULL;
	if( stepsParams.GetValue(CFSTR("STEPS"), stepsArray) )
	{
		//read them all here
		stepsCount = CFArrayGetCount(stepsArray);
		steps = new OneStep[stepsCount];

		for(CFIndex stepIndex = 0; stepIndex < stepsCount; stepIndex++)
		{
			steps[stepIndex].matchString = NULL;
			steps[stepIndex].value = 0;
			steps[stepIndex].status = NULL;
			steps[stepIndex].regExprValid = false;
			CFDictionaryRef oneStepDict = ACFType<CFDictionaryRef>::DynamicCast( CFArrayGetValueAtIndex(stepsArray, stepIndex) );
			if(oneStepDict != NULL)
			{
				ACFDict oneStepParams(oneStepDict);
				CFStringRef theStr = NULL;
				oneStepParams.GetValue( CFSTR("STRING"), theStr );
				
				if(matchMethod != kMatchRegularExpression)
				{
					steps[stepIndex].matchString = theStr;
				}
				else
				{				
                    std::string matchString = CMUtils::CreateUTF8StringFromCFString(theStr);
					int regFlags = REG_EXTENDED | REG_NOSUB;
					if( (matchCompareOptions & kCFCompareCaseInsensitive) != 0 )
						regFlags |= REG_ICASE;
					steps[stepIndex].regExprValid = ::regcomp(&(steps[stepIndex].regularExpression), matchString.c_str(), regFlags) == 0;
				}
				
				oneStepParams.GetValue( CFSTR("VALUE"), steps[stepIndex].value );
				
				oneStepParams.CopyValue( CFSTR("STATUS"), steps[stepIndex].status );//need to release status string
				if( (steps[stepIndex].status != NULL) && (inLocTable != NULL) && (inLocBundle != NULL) )
				{
					CFStringRef locStr = CFCopyLocalizedStringFromTableInBundle( steps[stepIndex].status, inLocTable, inLocBundle, "");
					CFRelease(steps[stepIndex].status);
					steps[stepIndex].status = locStr;
				}
			}
		}
	}
}

//returns last matched line if any
CFStringRef
StepsParams::CalculateProgress(CFArrayRef inOutputLines, OMCTaskProgress &outTaskProgress)
{
	CFIndex lineCount = 0;
	if(inOutputLines != NULL)
		lineCount = CFArrayGetCount(inOutputLines);
	
	outTaskProgress.statusString = NULL;//will be set with the last valid statusString
	
	CFStringRef lastMatchedLine = NULL;

	for(CFIndex i = 0; i < lineCount; i++)
	{
		CFStringRef oneLine = (CFStringRef)CFArrayGetValueAtIndex(inOutputLines, i);
		Boolean foundAMatch = false;
		for( CFIndex currStepIndex = outTaskProgress.nextStepIndex; currStepIndex < stepsCount; currStepIndex++ )
		{
			const OneStep &currStep = steps[currStepIndex];
			switch(matchMethod)
			{
				case kMatchExact:
				{
					if(currStep.matchString != NULL)
					{
						CFComparisonResult result = ::CFStringCompare(oneLine, currStep.matchString, matchCompareOptions);
						if(result == kCFCompareEqualTo)
						{//found a match
							outTaskProgress.nextStepIndex = currStepIndex+1;
							outTaskProgress.progress = (double)currStep.value;
							outTaskProgress.statusString = currStep.status;
							foundAMatch = true;
						}
					}
				}
				break;
				
				case kMatchContains:
				{
					if(currStep.matchString != NULL)
					{
						CFRange foundRange = ::CFStringFind(oneLine, currStep.matchString, matchCompareOptions);
						if( (foundRange.location != kCFNotFound) && (foundRange.length > 0) )
						{
							outTaskProgress.nextStepIndex = currStepIndex+1;
							outTaskProgress.progress = (double)currStep.value;
							outTaskProgress.statusString = currStep.status;
							foundAMatch = true;
						}
					}
				}
				break;
				
				case kMatchRegularExpression:
				{
					if( currStep.regExprValid )
					{
						int result = -1;
                        std::string searchedString = CMUtils::CreateUTF8StringFromCFString(oneLine);
						if(searchedString.length() > 0)
							result = ::regexec( &currStep.regularExpression, searchedString.c_str(), 0, NULL, 0);
						if(result == 0)
						{
							outTaskProgress.nextStepIndex = currStepIndex+1;
							outTaskProgress.progress = (double)currStep.value;
							outTaskProgress.statusString = currStep.status;
							foundAMatch = true;
						}
					}
				}
				break;
			}
			if(foundAMatch)
				break;
		}
		
		if(foundAMatch)
			lastMatchedLine = oneLine;
	}

//caller wants to take ownership of the oputput string so let's retain it 
	if(outTaskProgress.statusString != NULL)
		::CFRetain(outTaskProgress.statusString);
	return lastMatchedLine;
}


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

-(id)initWithParams:(CFDictionaryRef)inParams forCommand:(NSString *)inCommandName taskCount:(CFIndex)inTaskCount locTable:(CFStringRef)inLocTable locBundle:(CFBundleRef)inLocBundle
{
	self = [super init];
    if(self == nil)
		return nil;

	
#if _DEBUG_
	NSLog(@"OMCDeferredProgress = %p", (void *)self);
#endif

	mProgressType = (inTaskCount > 1) ? kOMCProgressDeterminateTaskCount : kOMCProgressIndeterminate;
	mProgressParams = inParams;
	if(mProgressParams != NULL)
		CFRetain(mProgressParams);

	mTaskCount = inTaskCount;
	mTasks = new OMCTaskProgress[mTaskCount];
	memset( mTasks, 0, mTaskCount*sizeof(OMCTaskProgress) );

	ACFDict params(mProgressParams);
	mTitleString = NULL;
	if( params.CopyValue( CFSTR("TITLE"), mTitleString ) )
	{
		if( (mTitleString != NULL) && (inLocTable != NULL) && (inLocBundle != NULL) )
		{
			CFStringRef locString = CFCopyLocalizedStringFromTableInBundle( mTitleString, inLocTable, inLocBundle, "");
			CFRelease(mTitleString);
			mTitleString = locString;
		}
	}
	
	if(mTitleString == NULL)
	{
		mTitleString = (CFStringRef)inCommandName;
		if(mTitleString != NULL)
			CFRetain(mTitleString);
	}

	mController = NULL;

	double delay = 0.0;
	params.GetValue( CFSTR("DELAY"), delay );
	
	mDeferTimer = NULL;
	if( delay > 0.0 )
	{//use CFRunLoopTimer so we don't rely on existance of NSRunLoop (those are not toll-free bridged equivalents)
		CFRunLoopTimerContext timerContext = {0, self, NULL, NULL, NULL};
		mDeferTimer = CFRunLoopTimerCreate(
											   kCFAllocatorDefault,
											   CFAbsoluteTimeGetCurrent() + delay,
											   0,		// interval
											   0,		// flags
											   0,		// order
											   OMCDeferredProgressCallBack,
											   &timerContext);
		
		if(mDeferTimer != NULL)
		{
			CFRunLoopAddTimer(CFRunLoopGetCurrent(), mDeferTimer, kCFRunLoopCommonModes);
		}
	}
	else
	{
		[self showProgressWindow];
	}

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
	
	return self;
}

- (void)dealloc
{
	if(mProgressParams != NULL)
	{
		CFRelease(mProgressParams);
		mProgressParams = NULL;
	}

	if(mTitleString != NULL)
	{
		CFRelease(mTitleString);
		mTitleString = NULL;
	}

	if(mDeferTimer != NULL)
	{
		CFRunLoopTimerInvalidate(mDeferTimer);
		CFRelease(mDeferTimer);
		mDeferTimer = NULL;
	}

	if( mController != NULL )
	{
		[mController close];
		[mController release];
		mController = NULL;
	}

	delete [] mTasks;
	mTasks = NULL;
	
	[super dealloc];
}

//returns true if user cancelled
- (Boolean)advanceProgressForTask:(CFIndex)inTaskIndex childPid:(pid_t)inChildPID withOutputString:(NSString *)inOutputStr taskEnded:(Boolean)isTaskEnded
{
#if 0//_DEBUG_
	NSLog(@"advanceProgressForTask: %@", inOutputStr);
#endif

	CFObj<CFArrayRef> lineArray( SplitStringIntoLines((CFStringRef)inOutputStr, mLastPartialLineStr.GetReference()) );
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
		
		[mController setProgress:totalProgress text:(NSString *)(CFStringRef)mLastLineStr];
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
		mLastLineStr.Adopt(currTaskProgress.statusString, kCFObjDontRetain);//take ownership of the returned string
		currTaskProgress.statusString = NULL;
	}
	else
	{
		if( suppressNonMatchingText )
			mLastLineStr.Adopt(lastMatchedLine, kCFObjRetain);

#if 0//_DEBUG_
		NSLog(@"calculateOneTaskProgress: CalculateProgress returned NULL string, using mLastLineStr=%@", (CFStringRef)mLastLineStr);
#endif		
	}
}

- (void) showProgressWindow
{
	if(mDeferTimer != NULL)//if called from timer
	{
		CFRunLoopTimerInvalidate(mDeferTimer);
		CFRelease(mDeferTimer);
		mDeferTimer = NULL;
	}
	
	if(mController == NULL)
	{
		mController = [[OMCProgressWindowController alloc] initWithWindowNibName:@"progress"];
		[[mController window] setTitle:(NSString *)mTitleString];

		NSString *frameAutosaveName = [NSString stringWithFormat: @"omc_progress_window %@", mTitleString];
		[mController setWindowFrameAutosaveName:frameAutosaveName];
		
		double totalProgress = -1.0;
		if( mProgressType != kOMCProgressIndeterminate)
			totalProgress = CalculateTotalProgress(mTasks, mTaskCount);

		if(mLastLineStr != NULL)
		{
			[mController setProgress:totalProgress text:(NSString *)(CFStringRef)mLastLineStr];
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
			OMCDeferredProgress *myProgress = (OMCDeferredProgress *)info;
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
    @autoreleasepool
	{
		@try
		{
			myProgress = [[OMCDeferredProgress alloc] initWithParams:inProgressParams forCommand:(NSString *)inCommandName taskCount:inTaskCount locTable:inLocTable locBundle:inLocBundle];
		
		}
		@catch (NSException *localException)
		{
		
			NSLog(@"OMCDeferredProgressCreate received exception: %@", localException);
		}
	} //@autoreleasepool

	return (OMCDeferredProgressRef)myProgress;
}

void
OMCDeferredProgressRelease(OMCDeferredProgressRef inProgressRef)
{
	@autoreleasepool
	{
		@try
		{
			OMCDeferredProgress *myProgress = (OMCDeferredProgress *)inProgressRef;
			[myProgress release];
		}
		@catch (NSException *localException)
		{
			NSLog(@"OMCDeferredProgressRelease received exception: %@", localException);
		}
	} //@autoreleasepool
}

Boolean
OMCDeferredProgressAdvanceProgress(OMCDeferredProgressRef inProgressRef, CFIndex inTaskIndex, pid_t inChildPID, CFStringRef inOutputStr, Boolean isTaskEnded)
{
	Boolean userCancelled = false;
	@autoreleasepool
	{
		@try
		{
			OMCDeferredProgress *myProgress = (OMCDeferredProgress *)inProgressRef;
			userCancelled = [myProgress advanceProgressForTask:inTaskIndex childPid:inChildPID withOutputString:(NSString *)inOutputStr taskEnded:isTaskEnded];
		}
		@catch (NSException *localException)
		{
			NSLog(@"OMCDeferredProgressAdvanceProgress received exception: %@", localException);
		}
	} //@autoreleasepool
	return userCancelled;
}

//
//  OMCProgressParsing.cpp
//  Abracode
//
//  See OMCProgressParsing.h. Moved here unchanged from OMCDeferredProgress.mm; the only edits are
//  ACFStringToUTF8 in place of CMUtils::CreateUTF8StringFromCFString and an NSString bridge.
//

#include "OMCProgressParsing.h"
#include "ACFDict.h"
#include "ACFString.h"
#include "DebugSettings.h"
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

// The left-over partial line followed by inMore (which may be NULL). Retained result.
static CFStringRef
CreateJoinedString(CFStringRef inLeftOver, CFStringRef inMore)
{
	CFIndex newLen = ::CFStringGetLength(inLeftOver);
	if(inMore != NULL)
		newLen += ::CFStringGetLength(inMore);

	CFMutableStringRef combinedStrings = ::CFStringCreateMutableCopy(kCFAllocatorDefault, newLen, inLeftOver);
	if((combinedStrings != NULL) && (inMore != NULL))
		::CFStringAppend(combinedStrings, inMore);
	return combinedStrings;
}

CFArrayRef SplitStringIntoLines(CFStringRef inString, CFObj<CFStringRef> &ioLeftPartialString)
{
	if( (inString == NULL) && (ioLeftPartialString == NULL) )
		return NULL;

	CFObj<CFMutableArrayRef> outArray( ::CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks) );

	CFIndex theSize = 0;
	if(inString != NULL)
		theSize = ::CFStringGetLength(inString);

	if(theSize == 0)
	{//could be the last output string. if we have anything partially left from previous run, we better output it now
		if(ioLeftPartialString != NULL)
		{
			::CFArrayAppendValue(outArray, ioLeftPartialString);
			ioLeftPartialString.Release();
		}
		return outArray.Detach();
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
		ioLeftPartialString.Release();
	}

	// Only line breaks: the left-over line, if any, is now complete. (This returned NULL, which
	// leaked outArray and lost that line; fixed when the code moved here.)
	if(firstCharIndex == theSize)
		return outArray.Detach();

	CFIndex i = firstCharIndex;
	CFIndex lineStartIndex = firstCharIndex;

	while(i < theSize)
	{
		oneChar = CFStringGetCharacterFromInlineBuffer( &inlineBuff, i );
		if( (oneChar == (UniChar)'\n') || (oneChar == (UniChar)'\r') )
		{//found line break
			if( (i-lineStartIndex) > 0 )
			{
				CFObj<CFStringRef> oneString( ::CFStringCreateWithSubstring( kCFAllocatorDefault, inString, CFRangeMake(lineStartIndex, i-lineStartIndex) ) );

				if( ioLeftPartialString != NULL )
				{//we need to combine the new text with left-over from previous run
					oneString.Adopt( CreateJoinedString(ioLeftPartialString, oneString) );
					ioLeftPartialString.Release();
				}

				if(oneString != NULL)
					::CFArrayAppendValue(outArray, oneString);
			}
			lineStartIndex = i+1;//first character after this line break
		}
		i++;
	}

	if( (i == theSize) && (i > lineStartIndex) )//last string left - this is partial line content
	{
		CFObj<CFStringRef> oneString( ::CFStringCreateWithSubstring( kCFAllocatorDefault, inString, CFRangeMake(lineStartIndex, i-lineStartIndex) ) );

		if(ioLeftPartialString != NULL)
		{//partial line adding to partial line? it is probably unlinkely to happen but let's add the pieces together
			oneString.Adopt( CreateJoinedString(ioLeftPartialString, oneString) );
			ioLeftPartialString.Release();
		}

		ioLeftPartialString.Swap(oneString);
	}

	return outArray.Detach();
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
				CFObj<CFStringRef> numString( ::CFStringCreateWithSubstring( kCFAllocatorDefault, inString, CFRangeMake(numStart, numEnd-numStart) ) );
				if(numString != NULL)
				{
					SInt32 groupIndex = ::CFStringGetIntValue(numString);
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

// Command.plist SCHEMA SOURCE OF TRUTH — PROGRESS.DETERMINATE_COUNTER (COMPARE_CASE_INSENSITIVE,
// REGULAR_EXPRESSION_MATCH, STATUS, SUBSTRING_INDEX_FOR_COUNTER/RANGE_END/RANGE_START,
// IS_COUNTDOWN, RANGE_START, RANGE_END, SUPPRESS_NON_MATCHING_TEXT).
// Adding/removing/renaming/deprecating/retyping any key here REQUIRES updating the matching
// verifier schema and rebuilding the skill, else the Command.plist verifier drifts:
//   verifier schema: Distribution/AppletBuilder.app/Contents/Library/command_verifier/schemas/DETERMINATE_COUNTER.json
//   rebuild skill:   python3 Skill/build_skill.py
void
CounterParams::Init(CFDictionaryRef counterDict, CFStringRef inLocTable, CFBundleRef inLocBundle)
{
	ACFDict counterParams(counterDict);

	bool caseInsensitive = false;
	counterParams.GetValue(CFSTR("COMPARE_CASE_INSENSITIVE"), caseInsensitive);

	CFStringRef regExStr = NULL;
	if( counterParams.GetValue(CFSTR("REGULAR_EXPRESSION_MATCH"), regExStr) )
	{
        std::string matchString = ACFStringToUTF8(regExStr);
		int regFlags = REG_EXTENDED;
		if( caseInsensitive )
			regFlags |= REG_ICASE;
		regExprValid = ::regcomp(&(regularExpression), matchString.c_str(), regFlags) == 0;
	}

	CFObj<CFStringRef> statusStr;
	if( counterParams.CopyValue(CFSTR("STATUS"), statusStr.GetReference()) )
	{
		if( (statusStr != NULL) && (inLocTable != NULL) && (inLocBundle != NULL) )
			statusStr.Adopt( CFCopyLocalizedStringFromTableInBundle( statusStr, inLocTable, inLocBundle, "") );

		if(statusStr != NULL)
			mStatusTemplate = SplitStatusTemplateString(statusStr);
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
	outTaskProgress.statusString.Release();//will be set with the last valid statusString

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
        std::string searchedString = ACFStringToUTF8(oneLine);
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

				// Build status string from template with captured regex groups
				if(mStatusTemplate != NULL)
				{
					CFObj<CFMutableStringRef> statusString(::CFStringCreateMutable(kCFAllocatorDefault, 0));
					StatusTemplateItem *oneTemplateItem = mStatusTemplate;
					while (oneTemplateItem != NULL)
					{
						if( oneTemplateItem->type == kTemplateItemString )
						{
							if(oneTemplateItem->text != NULL)
								::CFStringAppend(statusString, oneTemplateItem->text);
						}
						else
						{
							CFIndex groupIndex = oneTemplateItem->groupIndex;
							if( (groupIndex >= 0) && ((size_t)groupIndex < maxMatchCount) )
							{
								regoff_t grpStart = matches[groupIndex].rm_so;
								regoff_t grpEnd = matches[groupIndex].rm_eo;
								if( (grpStart >= 0) && (grpEnd > grpStart) )
								{
									const char *grpChars = searchedString.c_str() + grpStart;
									CFIndex grpLen = grpEnd - grpStart;
									CFObj<CFStringRef> groupStr(::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)grpChars, grpLen, kCFStringEncodingUTF8, true));
									if(groupStr != NULL)
										::CFStringAppend(statusString, groupStr);
								}
							}
						}

						oneTemplateItem = oneTemplateItem->next;
					}

					if( ::CFStringGetLength(statusString) > 0 )
					{
						outTaskProgress.statusString.Adopt((CFStringRef)statusString.Detach());
					}
				}
			}
		}
		else
		{
			TRACE_CSTR("CounterParams::CalculateProgress() Regex not matched for string = %s\n", ACFStringToUTF8(oneLine).c_str());
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
		}
		delete [] steps;
	}
}

// Command.plist SCHEMA SOURCE OF TRUTH — PROGRESS.DETERMINATE_STEPS (MATCH_METHOD enum,
// COMPARE_CASE_INSENSITIVE, SUPPRESS_NON_MATCHING_TEXT, STEPS array).
// Adding/removing/renaming/deprecating/retyping any key (or enum value) here REQUIRES updating
// the matching verifier schema and rebuilding the skill, else the Command.plist verifier drifts:
//   verifier schema: Distribution/AppletBuilder.app/Contents/Library/command_verifier/schemas/DETERMINATE_STEPS.json
//   rebuild skill:   python3 Skill/build_skill.py
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

	bool boolValue = false;
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
                    std::string matchString = ACFStringToUTF8(theStr);
					int regFlags = REG_EXTENDED | REG_NOSUB;
					if( (matchCompareOptions & kCFCompareCaseInsensitive) != 0 )
						regFlags |= REG_ICASE;
					steps[stepIndex].regExprValid = ::regcomp(&(steps[stepIndex].regularExpression), matchString.c_str(), regFlags) == 0;
				}
				
				oneStepParams.GetValue( CFSTR("VALUE"), steps[stepIndex].value );
				
				CFObj<CFStringRef> statusStr;
				if( oneStepParams.CopyValue( CFSTR("STATUS"), statusStr.GetReference() ) )
				{
					if( (statusStr != NULL) && (inLocTable != NULL) && (inLocBundle != NULL) )
						statusStr.Adopt( CFCopyLocalizedStringFromTableInBundle( statusStr, inLocTable, inLocBundle, "") );
					steps[stepIndex].status.Swap(statusStr);
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
	
	outTaskProgress.statusString.Release();//will be set with the last valid statusString

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
							outTaskProgress.statusString.Adopt(currStep.status, kCFObjRetain);
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
							outTaskProgress.statusString.Adopt(currStep.status, kCFObjRetain);
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
                        std::string searchedString = ACFStringToUTF8(oneLine);
						if(searchedString.length() > 0)
							result = ::regexec( &currStep.regularExpression, searchedString.c_str(), 0, NULL, 0);
						if(result == 0)
						{
							outTaskProgress.nextStepIndex = currStepIndex+1;
							outTaskProgress.progress = (double)currStep.value;
							outTaskProgress.statusString.Adopt(currStep.status, kCFObjRetain);
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

	return lastMatchedLine;
}

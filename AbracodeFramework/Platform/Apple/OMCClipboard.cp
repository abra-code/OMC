//**************************************************************************************
// Filename:	OMCClipboard.cp
//				(was CMUtils/CMUtilsClipboard.cp, part of Contextual Menu Workshop by Abracode Inc.)
//
// Copyright (c) 2002-2026 Abracode, Inc.  All rights reserved.
//
// Description:	the macOS clipboard for the engine (Platform/OMCClipboard.h), on the Pasteboard
//				Manager, and the exported CMUtils::PutCFStringToClipboard*.
//
//**************************************************************************************

#include <ApplicationServices/ApplicationServices.h>
#include "OMCClipboard.h"
#include "CMUtils.h" // CMUtils::PutCFStringToClipboard*, exported, and the character helpers
#include "OMCConstants.h"
#include "DebugSettings.h"
#include "CFObj.h"
#include "ACFType.h"
#include "OMCTestHost.h"
#include <vector>

// The clipboard, or in an OMC test launch the run's own general pasteboard (OMCTestHost.h), so a
// test never reads or replaces the user's clipboard. Returns a reference the caller releases.
//
// The run's pasteboard is opened once and kept for the life of the process. A reference kept open
// sees what another process (a handler's pasteboard tool, the test) writes at its next
// PasteboardSynchronize, but a new reference to a named pasteboard, opened after this process
// released its earlier one, reads as empty (checked on macOS 27). The system clipboard has no such
// trouble and is opened per call, as before.
static OSStatus
CreateClipboardRef(PasteboardRef *outClipboard)
{
	*outClipboard = NULL;
	CFStringRef testName = OMCTestHostGetClipboardName();
	if(testName == NULL)
		return PasteboardCreate(kPasteboardClipboard, outClipboard);

	// Opened for the first name seen and kept: correct because the test host decides the name once
	// per process (DecidePasteboards in OMCTestHost.cpp) and never changes it.
	static PasteboardRef sTestClipboard = [testName]()
	{
		PasteboardRef board = NULL;
		if(PasteboardCreate(testName, &board) != noErr)
			return (PasteboardRef)NULL;
		return board;
	}();
	if(sTestClipboard == NULL)
		return -1;
	*outClipboard = (PasteboardRef)CFRetain(sTestClipboard);
	return noErr;
}

#define SwapHiLoBytes(x)	( (unsigned short)((unsigned char)(x)<<8) | ((unsigned short)(x) >> 8) )



bool
OMCIsTextInClipboard()
{
	bool outTextPresent = false;

	CFObj<PasteboardRef> clipboardRef;
	OSStatus err = CreateClipboardRef( &clipboardRef );
	if( (err != noErr) || (clipboardRef == NULL) )
		return false;

	/*PasteboardSyncFlags  syncFlags =*/ PasteboardSynchronize( clipboardRef );
	
	ItemCount itemCount = 0;
	err = PasteboardGetItemCount(clipboardRef, &itemCount);
	if( err != noErr )
		return false;

	//one-based indexes
	for(ItemCount i = 1; i <= itemCount; i++ )
	{
		PasteboardItemID itemID = 0;
		err = PasteboardGetItemIdentifier(clipboardRef, i, &itemID);
		if(err == noErr)
		{
			CFObj<CFArrayRef> flavorUTIs;
			err = PasteboardCopyItemFlavors(clipboardRef, itemID, &flavorUTIs);
			if(flavorUTIs != NULL)
			{
				CFIndex flavorCount = CFArrayGetCount(flavorUTIs);
				for(CFIndex flIndex = 0; flIndex < flavorCount; flIndex++)
				{
					CFTypeRef oneItem = CFArrayGetValueAtIndex(flavorUTIs, flIndex);
					CFStringRef oneUTI = ACFType<CFStringRef>::DynamicCast(oneItem);
					if( (oneUTI != NULL) && UTTypeConformsTo(oneUTI, CFSTR("public.plain-text")) )
					{
						outTextPresent = true;
						break;
					}
				}
			}
		}
		if(outTextPresent)
			break;
	}
	return outTextPresent;
}



CFStringRef
OMCCopyClipboardText(long inReplaceOption)
{
	TRACE_CSTR( "OMCCopyClipboardText\n" );
	
	CFStringRef outString = NULL;

	CFObj<PasteboardRef> clipboardRef;
	OSStatus err = CreateClipboardRef( &clipboardRef );
	if( (err != noErr) || (clipboardRef == NULL) )
		return NULL;

	/*PasteboardSyncFlags  syncFlags =*/ PasteboardSynchronize( clipboardRef );
	
	ItemCount itemCount = 0;
	err = PasteboardGetItemCount(clipboardRef, &itemCount);
	if( err != noErr )
		return NULL;

	//one-based indexes
	for(ItemCount i = 1; i <= itemCount; i++ )
	{
		PasteboardItemID itemID = 0;
		err = PasteboardGetItemIdentifier(clipboardRef, i, &itemID);
		if(err == noErr)
		{
			CFObj<CFArrayRef> flavorUTIs;
			err = PasteboardCopyItemFlavors(clipboardRef, itemID, &flavorUTIs);
			if(flavorUTIs != NULL)
			{
				CFIndex flavorCount = CFArrayGetCount(flavorUTIs);
				// In the order the item lists its flavors, richest first. A flavor whose data is not
				// available (promised by an application that has since quit) is skipped.
				for(CFIndex flIndex = 0; flIndex < flavorCount; flIndex++)
				{
					CFTypeRef oneItem = CFArrayGetValueAtIndex(flavorUTIs, flIndex);
					CFStringRef oneUTI = ACFType<CFStringRef>::DynamicCast(oneItem);
					if(oneUTI != NULL)
					{
						bool isUTF16 = false;
						CFStringEncoding byteEncoding = ::CFStringGetSystemEncoding();
						CFObj<CFDataRef> textData;
						if( UTTypeEqual(oneUTI, CFSTR("public.utf8-plain-text")) )
						{
							err = PasteboardCopyItemFlavorData( clipboardRef, itemID, oneUTI, &textData );
							byteEncoding = kCFStringEncodingUTF8;
						}
						else if( UTTypeEqual(oneUTI, CFSTR("public.utf16-plain-text")) || UTTypeEqual(oneUTI, CFSTR("com.apple.utf16-plain-text")) )
						{
							err = PasteboardCopyItemFlavorData( clipboardRef, itemID, oneUTI, &textData );
							isUTF16 = true;
						}
						else if( UTTypeEqual(oneUTI, CFSTR("com.apple.traditional-mac-plain-text")) )
						{
							err = PasteboardCopyItemFlavorData( clipboardRef, itemID, oneUTI, &textData );
							isUTF16 = false;
						}
						
						if(textData != NULL)
						{
							CFObj<CFMutableDataRef> textMutableData( CFDataCreateMutableCopy(kCFAllocatorDefault, 0, textData) );
							textData.Release();
							if(textMutableData != NULL)
							{
								UInt8 *textDataPtr = CFDataGetMutableBytePtr( textMutableData );
								CFIndex textDataLength = CFDataGetLength( textMutableData );
								if(textDataPtr != NULL)
								{
									if(isUTF16)
									{
										UniChar *theText = (UniChar *)textDataPtr;
										UniCharCount theCount = textDataLength/sizeof(UniChar);
										
										if((theCount > 0) && (theText[0] == 0xFEFF))
										{
											theText++;
											theCount--;
										}
										else if((theCount > 0) && (theText[0] == 0xFFFE))
										{//how the heck the text in clipboard might be in swapped form?
											theText++;
											theCount--;
											for(SInt32 i = 0; i< (SInt32)theCount; i++ )
											{
												theText[i] = SwapHiLoBytes(theText[i]);
											}
										}
										
										if(inReplaceOption == kTextReplaceLFsWithCRs)
											CMUtils::ReplaceUnicodeCharacters(theText, theCount, 0x000A, 0x000D);
										else if(inReplaceOption == kTextReplaceCRsWithLFs)
											CMUtils::ReplaceUnicodeCharacters(theText, theCount, 0x000D, 0x000A);
										
										outString = ::CFStringCreateWithCharacters(kCFAllocatorDefault, theText, theCount );
									}
									else
									{
										if(inReplaceOption == kTextReplaceLFsWithCRs)
											CMUtils::ReplaceCharacters((char *)textDataPtr, textDataLength, 0x0A, 0x0D);
										else if(inReplaceOption == kTextReplaceCRsWithLFs)
											CMUtils::ReplaceCharacters((char*)textDataPtr, textDataLength, 0x0D, 0x0A);

										outString = ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8*)textDataPtr, textDataLength, byteEncoding, true);
									}
								}
							}
						}
					}
					if( outString != NULL )
						break;
				}
			}
		}
		if( outString != NULL )
			break;
	}
	return outString;
}



OSStatus
CMUtils::PutCFStringToClipboard(CFStringRef inString)
{
	if(inString == NULL)
		return noErr;

	CFIndex uniCount = ::CFStringGetLength(inString);
	if(uniCount == 0)
		return noErr;

	CFObj<PasteboardRef> clipboardRef;
	OSStatus err = CreateClipboardRef( &clipboardRef );
	if(err != noErr)
		return err;
		
	if(clipboardRef == NULL)
		return -1;

	// A kept reference (the run's board in a test launch) must catch up with other processes' writes
	// before it may clear the board, or the clear fails as modified (badPasteboardSyncErr).
	/*PasteboardSyncFlags  syncFlags =*/ PasteboardSynchronize( clipboardRef );
	err = PasteboardClear(clipboardRef);

	if(err == noErr)
	{
		err = PutCFStringToClipboardAsUnicodeText(clipboardRef, (PasteboardItemID)1, inString);
		err = PutCFStringToClipboardAsMacEncodedText(clipboardRef, (PasteboardItemID)1, inString);
	}

	return err;
}

OSStatus
CMUtils::PutCFStringToClipboardAsUnicodeText(PasteboardRef inPasteboardRef, PasteboardItemID inItem, CFStringRef inString)
{
	if( (inPasteboardRef == NULL) || (inString == NULL) )
		return paramErr;
	
	OSStatus err = noErr;
	CFIndex uniCount = ::CFStringGetLength(inString);
	if(uniCount == 0)
		return noErr;

	const UniChar *uniString = ::CFStringGetCharactersPtr(inString);

	if( uniString != NULL )
	{
		CFObj<CFDataRef> theData( CFDataCreate(kCFAllocatorDefault, (const UInt8*)uniString, uniCount*sizeof(UniChar)) );
		err = PasteboardPutItemFlavor(inPasteboardRef, inItem, CFSTR("com.apple.utf16-plain-text"), theData, kPasteboardFlavorNoFlags);
	}
	else
	{
		//CFStringGetCharactersPtr failed and we must copy the string
		std::vector<UniChar> newString(uniCount);

		CFRange theRange;
		theRange.location = 0;
		theRange.length = uniCount;
		::CFStringGetCharacters( inString, theRange, newString.data() );
		
		CFObj<CFDataRef> theData( CFDataCreate(kCFAllocatorDefault, (const UInt8*)newString.data(), uniCount*sizeof(UniChar)) );
		err = PasteboardPutItemFlavor(inPasteboardRef, inItem, CFSTR("com.apple.utf16-plain-text"), theData, kPasteboardFlavorNoFlags);
	}

	return err;
}

OSStatus
CMUtils::PutCFStringToClipboardAsMacEncodedText(PasteboardRef inPasteboardRef, PasteboardItemID inItem, CFStringRef inString)
{
	if( (inPasteboardRef == NULL) || (inString == NULL) )
		return paramErr;

	OSStatus err = noErr;
	CFIndex uniCount = ::CFStringGetLength(inString);
	if(uniCount == 0)
		return noErr;

	CFStringEncoding sysEnc = ::CFStringGetSystemEncoding();
	CFIndex newSize = ::CFStringGetMaximumSizeForEncoding(uniCount, sysEnc);
	if(newSize > 0)
	{
        std::vector<char> buff(newSize + 1);
		Boolean isOK = ::CFStringGetCString(inString, buff.data(), newSize + 1, sysEnc);
		if(isOK)
		{
			long stringLen = strlen(buff.data());
			
			CFObj<CFDataRef> theData( CFDataCreate(kCFAllocatorDefault, (const UInt8*)buff.data(), stringLen) );
			err = PasteboardPutItemFlavor(inPasteboardRef, inItem, CFSTR("com.apple.traditional-mac-plain-text"), theData, kPasteboardFlavorNoFlags);
		}
		else
			err = memFullErr;
	}
	return err;
}


// Pastes the clipboard into the app in front: the system clipboard is synchronized, then Command-V
// is posted as four key events
void
OMCPasteIntoFrontApp()
{
	//synchronize pasteboard before simulating cmd+v
	{
		CFObj<PasteboardRef> thePasteboard;
		OSStatus err = PasteboardCreate( kPasteboardClipboard, &thePasteboard );
		if( (err == noErr) && (thePasteboard != nullptr) )
		{
			[[maybe_unused]] PasteboardSyncFlags syncFlags = PasteboardSynchronize( thePasteboard );
	#if _DEBUG_
			printf("OMC: PasteboardSyncFlags = 0x%.8X\n", (unsigned int)syncFlags);
	#endif
		}
	}

	CFObj<CGEventRef> cmdDown = CGEventCreateKeyboardEvent(nullptr, (CGKeyCode)55, true);
	CGEventPost(kCGHIDEventTap, cmdDown);

	CFObj<CGEventRef> vDown = CGEventCreateKeyboardEvent(nullptr, (CGKeyCode)9, true); // 'v' down
	CGEventPost(kCGHIDEventTap, vDown);

	CFObj<CGEventRef> vUp = CGEventCreateKeyboardEvent(nullptr, (CGKeyCode)9, false); // 'v' up
	CGEventPost(kCGHIDEventTap, vUp);

	CFObj<CGEventRef> cmdUp = CGEventCreateKeyboardEvent(nullptr, (CGKeyCode)55, false);
	CGEventPost(kCGHIDEventTap, cmdUp);
}

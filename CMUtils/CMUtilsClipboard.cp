//**************************************************************************************
// Filename:	CMUtilsClipboard.cp
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
//
// Copyright � 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	static utilities for Contextual Menu Plugins
//
//
//**************************************************************************************

#include "CMUtils.h"
#include "DebugSettings.h"
#include "CFObj.h"
#include "ACFType.h"
#include <vector>

#define SwapHiLoBytes(x)	( (unsigned short)((unsigned char)(x)<<8) | ((unsigned short)(x) >> 8) )



Boolean
CMUtils::IsTextInClipboard()
{
	Boolean outTextPresent = false;

	CFObj<PasteboardRef> clipboardRef;
	OSStatus err = PasteboardCreate( kPasteboardClipboard, &clipboardRef );
	if( (err != noErr) || (clipboardRef == NULL) )
		return false;

	PasteboardSyncFlags  syncFlags = PasteboardSynchronize( clipboardRef );
	
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
CMUtils::CreateCFStringFromClipboardText(long inReplaceOption)
{
	TRACE_CSTR( "CreateCFStringFromClipboardText\n" );
	
	CFStringRef outString = NULL;

	CFObj<PasteboardRef> clipboardRef;
	OSStatus err = PasteboardCreate( kPasteboardClipboard, &clipboardRef );
	if( (err != noErr) || (clipboardRef == NULL) )
		return NULL;

	PasteboardSyncFlags  syncFlags = PasteboardSynchronize( clipboardRef );
	
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
				for(CFIndex flIndex = 0; i < flavorCount; flIndex++)
				{
					CFTypeRef oneItem = CFArrayGetValueAtIndex(flavorUTIs, flIndex);
					CFStringRef oneUTI = ACFType<CFStringRef>::DynamicCast(oneItem);
					if(oneUTI != NULL)
					{
						bool isUTF16 = false;
						CFObj<CFDataRef> textData;
						if( UTTypeEqual(oneUTI, CFSTR("com.apple.utf16-plain-text")) )
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
										
										if(theText[0] == 0xFEFF)
										{
											theText++;
											theCount--;
										}
										else if(theText[0] == 0xFFFE)
										{//how the heck the text in clipboard might be in swapped form?
											theText++;
											theCount--;
											for(SInt32 i = 0; i< (SInt32)theCount; i++ )
											{
												theText[i] = SwapHiLoBytes(theText[i]);
											}
										}
										
										if(inReplaceOption == kTextReplaceLFsWithCRs)
											ReplaceUnicodeCharacters(theText, theCount, 0x000A, 0x000D);
										else if(inReplaceOption == kTextReplaceCRsWithLFs)
											ReplaceUnicodeCharacters(theText, theCount, 0x000D, 0x000A);
										
										outString = ::CFStringCreateWithCharacters(kCFAllocatorDefault, theText, theCount );
									}
									else
									{
										if(inReplaceOption == kTextReplaceLFsWithCRs)
											ReplaceCharacters((char *)textDataPtr, textDataLength, 0x0A, 0x0D);
										else if(inReplaceOption == kTextReplaceCRsWithLFs)
											ReplaceCharacters((char*)textDataPtr, textDataLength, 0x0D, 0x0A);

										outString = ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8*)textDataPtr, textDataLength, ::CFStringGetSystemEncoding(), true);
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
	OSStatus err = PasteboardCreate( kPasteboardClipboard, &clipboardRef );
	if(err != noErr)
		return err;
		
	if(clipboardRef == NULL)
		return -1;

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

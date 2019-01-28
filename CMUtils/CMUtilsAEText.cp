//**************************************************************************************
// Filename:	CMUtilsAEText.cp
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
#include "StAEDesc.h"
#include "AStdArrayNew.h"
#include "AStdMalloc.h"
#include "CFObj.h"

Boolean
CMUtils::AEDescHasTextData(const AEDesc &inDesc)
{
#if _DEBUG_
	{
		DEBUG_CFSTR( CFSTR("AEDescHasTextData. Data type is:") );
		CFObj<CFStringRef> dbgType( ::UTCreateStringForOSType(inDesc.descriptorType) );
		DEBUG_CFSTR( (CFStringRef)dbgType );
	}
#endif

	if( (inDesc.descriptorType == typeChar) || (inDesc.descriptorType == typeUnicodeText) )
	{//try without coercing first
		return (::AEGetDescDataSize( &inDesc ) > 0);
	}
	else if( (inDesc.descriptorType != typeNull) && (inDesc.dataHandle != NULL) )
	{
		StAEDesc textDesc;
		
		if( ::AECoerceDesc(&inDesc, typeUnicodeText, textDesc) == noErr)
		{
			if( textDesc.GetDescriptorType() == typeUnicodeText ) 
				if( textDesc.GetDataStorage() != NULL )
					return (::AEGetDescDataSize(textDesc) > 0);
		}
		else if( ::AECoerceDesc(&inDesc, typeChar, textDesc) == noErr )
		{
			if( textDesc.GetDescriptorType() == typeChar ) 
				if( textDesc.GetDataStorage() != NULL )
					return (::AEGetDescDataSize(textDesc) > 0);
		}
	}
	
	return false;
}


//returns null if descriptior does not contain text
CFStringRef
CMUtils::CreateCFStringFromAEDesc(const AEDesc &inDesc, long inReplaceOption)
{
	TRACE_CSTR("CMUtils::CreateCFStringFromAEDesc\n" );

#if _DEBUG_

	char debugStr[32];
	DEBUG_CSTR( "AEDescHasTextData: data type is: " );
	UInt8 *descPtr = (UInt8 *)&inDesc.descriptorType;
	debugStr[0] = descPtr[0];
	debugStr[1] = descPtr[1];
	debugStr[2] = descPtr[2];
	debugStr[3] = descPtr[3];
	debugStr[4] = '\0';
	
	
	DEBUG_CSTR( debugStr );
	DEBUG_CSTR("\n");
	
	if(inDesc.dataHandle != NULL)
	{
		DEBUG_CSTR( "AEDescHasTextData: dataHandle is not NULL\n" );
	}
	else
	{
		DEBUG_CSTR( "AEDescHasTextData: dataHandle is NULL\n" );
	}
#endif

	CFStringRef outString = NULL;

	if( (inDesc.descriptorType == typeUnicodeText) && (inDesc.dataHandle != NULL) )
	{
		Size byteCount = ::AEGetDescDataSize( &inDesc );
		UniChar *newBuffer = (UniChar *)::NewPtrClear(byteCount);
		if(newBuffer != NULL)
		{
			if( ::AEGetDescData( &inDesc, newBuffer, byteCount ) == noErr)
			{
				if( ((byteCount/sizeof(UniChar)) > 0) && (newBuffer[0] == 0xFEFF) )
				{
					newBuffer++;
					byteCount -= sizeof(UniChar);
				}
				
				if(inReplaceOption == kTextReplaceLFsWithCRs)
					ReplaceUnicodeCharacters(newBuffer, byteCount/sizeof(UniChar), 0x000A, 0x000D);
				else if(inReplaceOption == kTextReplaceCRsWithLFs)
					ReplaceUnicodeCharacters(newBuffer, byteCount/sizeof(UniChar), 0x000D, 0x000A);
			
				outString = ::CFStringCreateWithCharacters(kCFAllocatorDefault, newBuffer, byteCount/sizeof(UniChar) );
			}	
			::DisposePtr( (Ptr)newBuffer );
		}
	}
	else if( (inDesc.descriptorType == typeChar) && (inDesc.dataHandle != NULL) )
	{
		Size byteCount = ::AEGetDescDataSize( &inDesc );
		char *newBuffer = ::NewPtrClear(byteCount);
		if(newBuffer != NULL)
		{
			if( ::AEGetDescData( &inDesc, newBuffer, byteCount ) == noErr)
			{
				if(inReplaceOption == kTextReplaceLFsWithCRs)
					ReplaceCharacters(newBuffer, byteCount, 0x0A, 0x0D);
				else if(inReplaceOption == kTextReplaceCRsWithLFs)
					ReplaceCharacters(newBuffer, byteCount, 0x0D, 0x0A);

				outString = ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8*)newBuffer, byteCount, CFStringGetSystemEncoding(), true);
			}	
			::DisposePtr( (Ptr)newBuffer );
		}
	}
	else if( (inDesc.descriptorType != typeNull) && (inDesc.dataHandle != NULL) ) 
	{
		StAEDesc textDesc;
	
		if( ::AECoerceDesc(&inDesc, typeUnicodeText, textDesc) == noErr)
		{
			if(textDesc.GetDescriptorType() == typeUnicodeText) 
				if(textDesc.GetDataStorage() != NULL)
				{
					Size byteCount = ::AEGetDescDataSize( textDesc );
					UniChar *newBuffer = (UniChar *)::NewPtrClear(byteCount);
					if(newBuffer != NULL)
					{
						if( ::AEGetDescData( textDesc, newBuffer, byteCount ) == noErr)
						{
							if( ((byteCount/sizeof(UniChar)) > 0) && (newBuffer[0] == 0xFEFF) )
							{
								newBuffer++;
								byteCount -= sizeof(UniChar);
							}

							if(inReplaceOption == kTextReplaceLFsWithCRs)
								ReplaceUnicodeCharacters(newBuffer, byteCount/sizeof(UniChar), 0x000A, 0x000D);
							else if(inReplaceOption == kTextReplaceCRsWithLFs)
								ReplaceUnicodeCharacters(newBuffer, byteCount/sizeof(UniChar), 0x000D, 0x000A);

							outString = ::CFStringCreateWithCharacters(kCFAllocatorDefault, newBuffer, byteCount/sizeof(UniChar) );
						}	
						::DisposePtr( (Ptr)newBuffer );
					}
				}
		}
		else if( ::AECoerceDesc(&inDesc, typeChar, textDesc) == noErr)
		{
			if(textDesc.GetDescriptorType() == typeChar) 
				if(textDesc.GetDataStorage() != NULL)
				{
					Size byteCount = ::AEGetDescDataSize( textDesc );
					char *newBuffer = ::NewPtrClear(byteCount);
					if(newBuffer != NULL)
					{
						if( ::AEGetDescData( textDesc, newBuffer, byteCount ) == noErr)
						{
							if(inReplaceOption == kTextReplaceLFsWithCRs)
								ReplaceCharacters(newBuffer, byteCount, 0x0A, 0x0D);
							else if(inReplaceOption == kTextReplaceCRsWithLFs)
								ReplaceCharacters(newBuffer, byteCount, 0x0D, 0x0A);

							outString = ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8*)newBuffer, byteCount, CFStringGetSystemEncoding(), true);
						}	
						::DisposePtr( (Ptr)newBuffer );
					}
				}
		}
	}

	if(outString == NULL)
	{
		DEBUG_CSTR( "CMUtils::CreateCFStringFromAEDesc: NULL string returned\n" );
	}

	return outString;
}

OSStatus
CMUtils::CreateUniTextDescFromCFString(CFStringRef inStringRef, AEDesc &outDesc)
{
	if(inStringRef == NULL) return paramErr;

	CFIndex uniCount = ::CFStringGetLength(inStringRef);
	const UniChar *uniString = ::CFStringGetCharactersPtr(inStringRef);

	if( uniString != NULL )
	{
		return ::AECreateDesc(typeUnicodeText, uniString, uniCount*sizeof(UniChar), &outDesc);
	}
	
	AStdArrayNew<UniChar> newString(uniCount);

	CFRange theRange;
	theRange.location = 0;
	theRange.length = uniCount;
	::CFStringGetCharacters( inStringRef, theRange, newString.Get());
	return ::AECreateDesc(typeUnicodeText, newString.Get(), uniCount*sizeof(UniChar), &outDesc);

}

void
CMUtils::ReplaceCharacters(char *ioText, Size inSize, char inFromChar, char inToChar)
{
	for(Size i = 0; i < inSize; i++)
	{
		if(ioText[i] == inFromChar)
			ioText[i] = inToChar;
	}
}

void
CMUtils::ReplaceUnicodeCharacters(UniChar *ioText, UniCharCount inCount, UniChar inFromChar, UniChar inToChar)
{
	for(UniCharCount i = 0; i < inCount; i++)
	{
		if(ioText[i] == inFromChar)
			ioText[i] = inToChar;
	}
}

//zero-terminated string is given on output
//result allocated with malloc, caller responsible for freeing it
char *
CMUtils::CreateUTF8CStringFromCFString(CFStringRef inString, ByteCount *outCount)
{
	if(outCount != NULL)
		*outCount = 0;

	TRACE_CSTR("Entering CreateUTF8CStringFromCFString\n");

	if( inString == NULL )
	{
		TRACE_CSTR("Input CFString is NULL, return\n");
		return NULL;
	}

	//OSStatus err = noErr;
	CFIndex uniCount = ::CFStringGetLength(inString);
	if(uniCount > 0)
	{
		CFIndex newSize = ::CFStringGetMaximumSizeForEncoding(uniCount, kCFStringEncodingUTF8);
		if(newSize > 0)
		{
			AMalloc buff(newSize + 1);
			Boolean isOK = ::CFStringGetCString(inString, buff.Get(), newSize + 1, kCFStringEncodingUTF8);
			if(isOK)
			{
				if(outCount != NULL)
					*outCount = strlen(buff.Get());
				return buff.Detach();
			}
		}
	}
	
	TRACE_CSTR("CreateUTF8CStringFromCFString. Empty string\n");
	return (char *)calloc(1, sizeof(char));//one byte with '\0'
}

//character, not byte, count is given on output
//uni char data is not terminated with null
//data is malloced, so caller is responsible for freeing it
 
UniChar *
CMUtils::CreateUTF16DataFromCFString(CFStringRef inString, UniCharCount *outCharCount)
{
	if( inString == NULL )
	{
		TRACE_CSTR("Input CFString is NULL, return\n");
		return NULL;
	}

	CFIndex uniCount = ::CFStringGetLength(inString);
	SInt32 allocCount = uniCount;
	if(uniCount == 0)//we still want to allocate data for empty string but better not malloc 0 size
		allocCount = 1;

	AStdMalloc<UniChar> newString(allocCount);

	CFRange theRange;
	theRange.location = 0;
	theRange.length = uniCount;
	::CFStringGetCharacters( inString, theRange, newString.Get());
	if(outCharCount != NULL)
		*outCharCount = uniCount;

	return newString.Detach();
}


//**************************************************************************************
// Filename:	CMUtils.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
//
// Copyright © 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	static utilities for Contextual Menu Plugins
//
//
//**************************************************************************************
#ifndef __CMUtils__
#define __CMUtils__

#pragma once

#include "DebugSettings.h"
#include <Carbon/Carbon.h>
#include <string>

#pragma export off

typedef OSStatus (*CFURLHandlerProc)( CFURLRef inURLRef, void *ioData );

enum
{
	kListClear					= 0x00000000,

	kProcDirectiveMask			= 0x00FF0000,
	kProcBreakOnFirst			= 0x00010000,
	
	kListOutFlagsMask			= 0xFF000000,
	kListOutMultipleObjects		= 0x01000000,
	kListOutErrorsOccurred		= 0x02000000
};

enum
{
	kTextReplaceNothing,
	kTextReplaceLFsWithCRs,
	kTextReplaceCRsWithLFs
};

class CMUtils
{
public:
										
	static OSStatus 	AddCommandToAEDescList(	ConstStr255Param inCommandString,
												SInt32 inCommandID,
												AEDescList* ioCommandList,
												MenuItemAttributes attributes = 0,
												UInt32 modifiers = kMenuNoModifiers);

	static OSStatus		AddCommandToAEDescList(	const UniChar *inCommandString,
												UniCharCount inCount,
												SInt32 inCommandID,
												AEDescList* ioCommandList,
												MenuItemAttributes attributes = 0,
												UInt32 modifiers = kMenuNoModifiers);

	static OSStatus		AddCommandToAEDescList(	CFStringRef inCommandString,
												SInt32 inCommandID,
												Boolean putCFString, //available starting with OS 10.2
												AEDescList* ioCommandList,
												MenuItemAttributes attributes = 0,
												UInt32 modifiers = kMenuNoModifiers);

	static OSStatus		AddCommandToAEDescList_Compatible(
												CFStringRef inCommandString,
												SInt32 inCommandID,
												AEDescList* ioCommandList,
												MenuItemAttributes attributes = 0,
												UInt32 modifiers = kMenuNoModifiers);

	static OSStatus		AddSubmenu( AEDescList* ioCommands, CFStringRef inName, AEDescList &inSubList );
	static OSStatus		AddSubmenu( AEDescList* ioCommands, const UniChar *inName, UniCharCount inCount, AEDescList &inSubList );

	static SInt32		FindSubmenu(AEDescList* ioCommands, CFStringRef inName);
//	Boolean				IsSubmenuWithName(const AERecord *inMenuItemRec, CFStringRef inSubmenuName);

	static Boolean		ProcessObjectList( const AEDescList *fileList, UInt32 &ioFlags, CFURLHandlerProc inProcPtr, void *inProcData = NULL );

	static Boolean		ProcessObjectList( CFArrayRef fileList, UInt32 &ioFlags, CFURLHandlerProc inProcPtr, void *inProcData = NULL );

	static CFMutableArrayRef	CollectObjectNames( const AEDescList *fileList);
	static OSStatus				AESortFileList(const AEDescList *inFileList, AEDescList *outSortedList, CFOptionFlags compareOptions);

    static CFURLRef     CopyURL(const AEDesc &inDesc);

	static CFBundleRef	CFBundleCreate(CFURLRef inBundleURL);

	static OSErr		SendAppleEventToRunningApplication( FourCharCode appSig, AEEventClass theAEEventClass,
															AEEventID theAEEventID, const AEDesc &directObjectDesc, Boolean waitForReply = false);

	static OSErr		SendAEWithObjToRunningApp( FourCharCode appSig, AEEventClass theAEEventClass, AEEventID theAEEventID,
													AEKeyword keyOne, const AEDesc &objOne, Boolean waitForReply = false  );

	static OSErr		SendAEWithTwoObjToRunningApp( FourCharCode appSig, AEEventClass theAEEventClass, AEEventID theAEEventID,
														AEKeyword keyOne, const AEDesc &objOne,
														AEKeyword keyTwo, const AEDesc &objTwo, Boolean waitForReply = false);

	static OSErr		SendAEWithThreeObjToRunningApp( FourCharCode appSig, AEEventClass theAEEventClass, AEEventID theAEEventID,
														AEKeyword keyOne, const AEDesc &objOne,
														AEKeyword keyTwo, const AEDesc &objTwo,
														AEKeyword keyThree, const AEDesc &objThree, Boolean waitForReply = false);

	static OSErr		SendAppleEventToRunningApplication( const char * inAppBundleIDCStr, AEEventClass theAEEventClass,
															AEEventID theAEEventID, const AEDesc &directObjectDesc, Boolean waitForReply = false);

	static OSErr		SendAEWithObjToRunningApp( const char * inAppBundleIDCStr, AEEventClass theAEEventClass, AEEventID theAEEventID,
													AEKeyword keyOne, const AEDesc &objOne, Boolean waitForReply = false  );

	static OSErr		SendAEWithTwoObjToRunningApp( const char * inAppBundleIDCStr, AEEventClass theAEEventClass, AEEventID theAEEventID,
														AEKeyword keyOne, const AEDesc &objOne,
														AEKeyword keyTwo, const AEDesc &objTwo, Boolean waitForReply = false);

	static OSErr		SendAEWithThreeObjToRunningApp( const char * inAppBundleIDCStr, AEEventClass theAEEventClass, AEEventID theAEEventID,
														AEKeyword keyOne, const AEDesc &objOne,
														AEKeyword keyTwo, const AEDesc &objTwo,
														AEKeyword keyThree, const AEDesc &objThree, Boolean waitForReply = false);

    static bool         IsClickInOpenFinderWindow(const AEDesc *inContext, Boolean doCheckIfFolder) noexcept;

	static Boolean		AEDescHasTextData(const AEDesc &inDesc);
	static CFStringRef	CreateCFStringFromAEDesc(const AEDesc &inDesc, long inReplaceOption);
	static OSStatus		CreateUniTextDescFromCFString(CFStringRef inStringRef, AEDesc &outDesc);

	static Boolean		IsTextInClipboard();
	static CFStringRef	CreateCFStringFromClipboardText(long inReplaceOption);
	static OSStatus		PutCFStringToClipboard(CFStringRef inString);
	static OSStatus		PutCFStringToClipboardAsUnicodeText(PasteboardRef inPasteboardRef, PasteboardItemID inItem, CFStringRef inString);
	static OSStatus		PutCFStringToClipboardAsMacEncodedText(PasteboardRef inPasteboardRef, PasteboardItemID inItem, CFStringRef inString);
	
	static void			ReplaceCharacters(char *ioText, Size inSize, char inFromChar, char inToChar);
	static void			ReplaceUnicodeCharacters(UniChar *ioText, UniCharCount inCount, UniChar inFromChar, UniChar inToChar);
    static std::string	CreateUTF8StringFromCFString(CFStringRef inString);
	static UniChar *	CreateUTF16DataFromCFString(CFStringRef inString, UniCharCount *outCharCount);
};



#pragma export reset


#endif //__CMUtils__

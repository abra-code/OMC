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

#pragma export off

typedef OSStatus (*FSRefHandlerProc)( const FSRef *inRef, void *ioData );
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

	static Boolean		ProcessObjectList( const AEDescList *fileList, UInt32 &ioFlags, FSRefHandlerProc inProcPtr, void *inProcData = NULL );

	static Boolean		ProcessObjectList( CFArrayRef fileList, UInt32 &ioFlags, CFURLHandlerProc inProcPtr, void *inProcData = NULL );

	static CFMutableArrayRef	CollectObjectNames( const AEDescList *fileList);
	static OSStatus				AESortFileList(const AEDescList *inFileList, AEDescList *outSortedList, CFOptionFlags compareOptions);

	static OSErr		GetFSRef(const AEDesc &inDesc, FSRef &outRef);

	static OSErr		CreateFSRefDesc( const CFURLRef inURL, AEDesc &outAEDesc );

	static OSStatus		GetPStringName(const FSRef *inRef, Str255 outName);
	static CFStringRef	CreateCFStringNameFromFSRef(const FSRef *inRef);
	static OSErr		CreateAliasDesc( const AliasHandle inAliasH, AEDesc *outAliasAEDesc );
    static OSErr		CreateAliasDesc( const FSRef *inFSRef, AEDesc *outAliasAEDesc );
	static OSErr		CreateAliasDesc( const CFURLRef inURL, AEDesc *outAliasAEDesc );

	static OSErr		IsFolder(const FSRef *inRef, Boolean &outIsFolder);

	static CFBundleRef	CFBundleCreate(CFURLRef inBundleURL);

	static OSErr		SendAppleEventToFinder( AEEventClass theAEEventClass, AEEventID theAEEventID,
												const AEDesc &directObjectDesc,
												Boolean waitForReply);
												
	static OSErr		SendAEWithTwoObjToFinder( AEEventClass theAEEventClass, AEEventID theAEEventID,
													AEKeyword keyOne, const AEDesc &objOne,
													AEKeyword keyTwo, const AEDesc &objTwo,
													Boolean waitForReply);

	static OSErr		SendAEWithThreeObjToFinder( AEEventClass theAEEventClass, AEEventID theAEEventID,
													AEKeyword keyOne, const AEDesc &objOne,
													AEKeyword keyTwo, const AEDesc &objTwo,
													AEKeyword keyThree, const AEDesc &objThree,
													Boolean waitForReply);

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

//	static OSErr		SendServicesQueryToSelf();
	static CFStringRef	CopyHostName();


	static void			PutFinderObjectToTrash(const AEDesc &directObjectDesc, Boolean waitForReply);
	static void			PutFinderObjectToTrash(const FSRef *inRef, Boolean waitForReply);

	static void			UpdateFinderObject(const AEDesc &directObjectDesc, Boolean waitForReply);
	static void			UpdateFinderObject(const FSRef *inRef, Boolean waitForReply);

	static void			MoveFinderObjectToFolder(const AEDesc &directObjectDesc, const FSRef *inFolderRef, Boolean waitForReply);

	static void			MoveFinderObjectToFolder(const FSRef *inFileRef, const FSRef *inFolderRef, Boolean waitForReply);

	static OSStatus		GetInsertionLocationAsAliasDesc(AEDesc &outAliasDesc, AEDesc &outFinderObj);
	static Boolean		IsClickInOpenFinderWindow(const AEDesc *inContext, Boolean doCheckIfFolder);
	static OSErr		GetFinderWindowViewType(AEDesc &finderObjDesc, FourCharCode &outViewType);

	static OSErr		DeleteObject(const FSRef *inRef);

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
	static char *		CreateUTF8CStringFromCFString(CFStringRef inString, ByteCount *outCount);
	static UniChar *	CreateUTF16DataFromCFString(CFStringRef inString, UniCharCount *outCharCount);



	static void			BufToHex( const unsigned char* src, char *dest, ByteCount srcLen, ByteCount &destLen, UInt8 clumpSize = 0);
};



#pragma export reset


#endif //__CMUtils__

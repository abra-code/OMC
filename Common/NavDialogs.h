//**************************************************************************************
// Filename:	NavDialogs.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright © 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	
//
//**************************************************************************************

#pragma once

#import <Carbon/Carbon.h>

extern "C"
{

Boolean		CreatePathFromSaveAsDialog(CFURLRef &outRef, CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags = 0);
Boolean		CreatePathFromChooseFileDialog(CFURLRef &outRef, CFStringRef inClientName, CFStringRef inMessage, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags = 0);
Boolean		CreatePathFromChooseFolderDialog(CFURLRef &outRef, CFStringRef inClientName, CFStringRef inMessage, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags = 0);
Boolean		CreatePathFromChooseObjectDialog(CFURLRef &outRef, CFStringRef inClientName, CFStringRef inMessage, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags = 0);

Boolean		ChooseFolderDialog(FSRef &outFolderRef, CFStringRef inClientName, CFStringRef inMessage, CFStringRef inActionButtLabel, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags = 0);
Boolean		ChooseFileDialog(FSRef &outRef, CFStringRef inClientName, CFStringRef inMessage, CFStringRef inActionButtLabel, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags = 0);


CFURLRef	FURLCreateFromNavReply(const NavReplyRecord * navReply);
OSStatus	GetFSRefFromNavReply(const NavReplyRecord * navReply, FSRef &outFSRef);

Boolean		GetAEListFromChooseFileDialog(AEDescList &outList, CFStringRef inClientName, CFStringRef inMessage, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags = 0);
Boolean		GetAEListFromChooseFolderDialog(AEDescList &outList, CFStringRef inClientName, CFStringRef inMessage, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags = 0);
Boolean		GetAEListFromChooseObjectDialog(AEDescList &outList, CFStringRef inClientName, CFStringRef inMessage, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags = 0);

}; //extern "C"
/*
 *  OMCDialog.h
 *  Abracode
 *
 *  Created by Tomasz Kukielka on 3/2/08.
 *  Copyright 2008 Abracode. All rights reserved.
 *
 */

#pragma once

#include "AObserver.h"
#include "MessagePortListener.h"

class SelectionIterator;
class OnMyCommandCM;

enum
{
	kControlCustomValueKey = 'val!',
	kCustomEscapeMethodKey = 'esc!',
	kCustomPrefixKey = 'pre!',
	kCustomSuffixKey = 'suf!',
	kCustomSeparatorKey = 'sep!',
	kSelectionIteratingCommands = 'ite!',
	kReverseIterationCommands = 'rev!',
	
	kCustomFontName = 'fon!',
	kCustomFontSize = 'siz!'
};

enum
{
	kControlModifier_AllRows		= 0x00000001,
//TODO:
//	kControlModifier_InterfaceValue	= 0x00000002, //mapped value is default
//	kControlModifier_Index			= 0x00000004,
//	kControlModifier_Bool			= 0x00000008, //a checkbox returns integer 0 or 1, this may change the result to false/true
};

class OMCDialog : public ARefCounted
{

public:
	friend class OnMyCommandCM;

							OMCDialog();
	virtual					~OMCDialog();

	AObserverBase *			GetObserver()
							{
								return (AObserver<OMCDialog> *)mTaskObserver;
							}

	SelectionIterator *		GetSelectionIterator()
							{
								return mSelectionIterator;
							}

	void					SetSelectionIterator(SelectionIterator *inIterator)
							{
								mSelectionIterator = inIterator;
							}

	void					StartListening();

	CFStringRef				GetDialogUniqueID();

	virtual CFTypeRef		CopyControlValue(CFStringRef inControlID, CFStringRef inControlPart, SelectionIterator *inSelIterator, CFDictionaryRef *outCustomProperties) noexcept = 0;
	virtual void			CopyAllControlValues(CFSetRef requestedNibControls, SelectionIterator *inSelIterator) noexcept = 0;

	virtual CFDataRef		ReceivePortMessage( SInt32 msgid, CFDataRef inData ) = 0;//remote message
	virtual void			ReceiveNotification(void *ioData) = 0;//local message

	static ARefCountedObj<OMCDialog> FindDialogByGUID(CFStringRef inGUID);

	static CFStringRef		CreateControlValueString(CFTypeRef controlValue, CFDictionaryRef customProperties, UInt16 escSpecialCharsMode, bool isEnvStyle) noexcept;
	CFStringRef				CreateNibControlValue(SInt32 inSpecialWordID, CFStringRef inNibControlString, UInt16 escSpecialCharsMode, bool isEnvStyle) noexcept;

	void					AddEnvironmentVariablesForAllControls(CFMutableDictionaryRef ioEnvironList) noexcept;

protected:
	OMCDialog *				next;
	ARefCountedObj< AObserver<OMCDialog> > mTaskObserver;
	MessagePortListener<OMCDialog> mListener;
	CFObj<CFStringRef>		mDialogUniqueID;
	CFObj<CFMutableDictionaryRef> mNibControlValues;//key: controlID string, value: dictionary for columnID (as long) & value (CFType)
	CFObj<CFMutableDictionaryRef> mNibControlCustomProperties;
	SelectionIterator *		mSelectionIterator;//temporary reference for subcommand execution
	static OMCDialog *		sChainHead;
};

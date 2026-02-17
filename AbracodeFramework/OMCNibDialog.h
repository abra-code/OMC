//
//  OMCNibDialog.h
//  Abracode
//
//  Created by Tomasz Kukielka on 3/1/08.
//  Copyright 2008 Abracode. All rights reserved.
//

class OnMyCommandCM;
#include "OMCDialog.h"

using OMCNibWindowControllerRef = void *;
class CommandRuntimeData;

class OMCNibDialog: public OMCDialog
{
public:
						OMCNibDialog(OMCNibWindowControllerRef inController)
						{
							mController = inController;
						}

	virtual				~OMCNibDialog() { }

	virtual CFTypeRef	CopyControlValue(CFStringRef inControlID, CFStringRef inControlPart, SelectionIterator *inSelIterator, CFDictionaryRef *outCustomProperties) noexcept override;
	virtual void		CopyAllControlValues(CFSetRef requestedNibControls, SelectionIterator *inSelIterator) noexcept override;

	virtual CFDataRef	ReceivePortMessage( SInt32 msgid, CFDataRef inData ) noexcept override; // remote message
	virtual void		ReceiveNotification(void *ioData) noexcept override; // local message

	virtual CFStringRef	CreateControlValue(SInt32 inSpecialWordID, CFStringRef inControlString, UInt16 escSpecialCharsMode, bool isEnvStyle) noexcept override;
	virtual void		AddEnvironmentVariablesForAllControls(CFMutableDictionaryRef ioEnvironList) noexcept override;

	void				SetController(OMCNibWindowControllerRef inController) noexcept
						{
							mController = inController;
						}

private:
	void				StoreControlValue(CFStringRef controlID, CFTypeRef inValue, CFStringRef controlPart) noexcept;

private:
	OMCNibWindowControllerRef mController; //not owned
};


ARefCountedObj<OMCDialog> RunNibDialog(OnMyCommandCM *inPlugin, CommandRuntimeData *commandRuntimeData);

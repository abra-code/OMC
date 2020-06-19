//
//  OMCCocoaDialog.h
//  Abracode
//
//  Created by Tomasz Kukielka on 3/1/08.
//  Copyright 2008 Abracode. All rights reserved.
//

class OnMyCommandCM;
#include "OMCDialog.h"

using OMCDialogControllerRef = void *;

class OMCCocoaDialog: public OMCDialog
{
public:
						OMCCocoaDialog(OMCDialogControllerRef inController)
						{
							mController = inController;
						}

	virtual				~OMCCocoaDialog() { }

	virtual CFTypeRef	CopyControlValue(CFStringRef inControlID, CFStringRef inControlPart, SelectionIterator *inSelIterator, CFDictionaryRef *outCustomProperties) noexcept;
	virtual void		CopyAllControlValues(CFSetRef requestedNibControls, SelectionIterator *inSelIterator) noexcept;

	virtual CFDataRef	ReceivePortMessage( SInt32 msgid, CFDataRef inData );//remote message
	virtual void		ReceiveNotification(void *ioData);//local message

	void				SetController(OMCDialogControllerRef inController) noexcept
						{
							mController = inController;
						}

private:
	void				StoreControlValue(CFStringRef controlID, CFTypeRef inValue, CFStringRef controlPart) noexcept;

private:
	OMCDialogControllerRef mController; //not owned
};


ARefCountedObj<OMCCocoaDialog> RunCocoaDialog(OnMyCommandCM *inPlugin);

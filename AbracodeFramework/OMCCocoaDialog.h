//
//  OMCCocoaDialog.h
//  Abracode
//
//  Created by Tomasz Kukielka on 3/1/08.
//  Copyright 2008 Abracode. All rights reserved.
//

class OnMyCommandCM;
#include "OMCDialog.h"

@class OMCDialogController;

class OMCCocoaDialog: public OMCDialog
{
public:
						OMCCocoaDialog(OMCDialogController *inController)
						{
							mController = inController;
						}

	virtual				~OMCCocoaDialog() { }

	virtual CFTypeRef	CopyControlValue(CFStringRef inControlID, CFStringRef inControlPart, SelectionIterator *inSelIterator, CFDictionaryRef *outCustomProperties) noexcept;
	virtual void		CopyAllControlValues(CFSetRef requestedNibControls, SelectionIterator *inSelIterator) noexcept;

	virtual CFDataRef	ReceivePortMessage( SInt32 msgid, CFDataRef inData );//remote message
	virtual void		ReceiveNotification(void *ioData);//local message

	void				SetController(OMCDialogController *inController) noexcept
						{
							mController = inController;
						}

private:
	void				StoreControlValue(CFStringRef controlID, CFTypeRef inValue, CFStringRef controlPart) noexcept;

private:
	OMCDialogController *mController; //not owned
};



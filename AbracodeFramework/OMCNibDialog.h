//
//  OMCNibDialog.h
//  Abracode
//
//  Created by Tomasz Kukielka on 3/1/08.
//  Copyright 2008 Abracode. All rights reserved.
//

class OnMyCommandCM;
#include "OMCDialog.h"

class CommandRuntimeData;

class OMCNibDialog: public OMCDialog
{
public:
						OMCNibDialog()
						{
						}

	virtual				~OMCNibDialog() { }

	virtual void		CopyAllControlValues(CFSetRef requestedNibControls, SelectionIterator *inSelIterator) noexcept override;

	virtual CFStringRef	CreateControlValue(SInt32 inSpecialWordID, CFStringRef inControlString, UInt16 escSpecialCharsMode, bool isEnvStyle) noexcept override;
	virtual void		AddEnvironmentVariablesForAllControls(CFMutableDictionaryRef ioEnvironList) noexcept override;

private:
	void				StoreControlValue(CFStringRef controlID, CFTypeRef inValue, CFStringRef controlPart) noexcept;
};


ARefCountedObj<OMCDialog> RunNibDialog(OnMyCommandCM *inPlugin, CommandRuntimeData *commandRuntimeData);

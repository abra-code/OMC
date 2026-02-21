//
//  OMCActionUIDialog.h
//  Abracode
//
//  Created by Tomasz Kukielka on 2/17/26.
//  Copyright 2026 Abracode. All rights reserved.
//

class OnMyCommandCM;
#include "OMCDialog.h"

class CommandRuntimeData;

class OMCActionUIDialog: public OMCDialog
{
public:
						OMCActionUIDialog()
						{
						}

	virtual				~OMCActionUIDialog() { }

	virtual void		CopyAllControlValues(CFSetRef requestedNibControls, SelectionIterator *inSelIterator) noexcept override;
	virtual CFStringRef	CreateControlValue(SInt32 inSpecialWordID, CFStringRef inControlString, UInt16 escSpecialCharsMode, bool isEnvStyle) noexcept override;
	virtual void		AddEnvironmentVariablesForAllControls(CFMutableDictionaryRef ioEnvironList) noexcept override;
};


ARefCountedObj<OMCDialog> RunActionUIDialog(OnMyCommandCM *inPlugin, CommandRuntimeData *commandRuntimeData);

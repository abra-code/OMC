//
//  OnMyCommandAE.h
//  Abracode
//
//  The contextual menu plugin's object (OnMyCommandCM.plugin, loaded by Shortcuts.app): the Menu
//  Manager's ExamineContext, HandleSelection and PostMenuCleanup over Apple event descriptors, on an
//  engine (OnMyCommand) of its own. The plugin creates it in CreateNewCMPlugin(), once per menu.
//  macOS only. Phase 5 step 6 (Private/phase5-interfaces-design.md).
//

#pragma once
#include "ACMPlugin.h"

class OnMyCommand;

class OnMyCommandCMPlugin : public ACMPlugin
{
public:
						OnMyCommandCMPlugin();
	virtual				~OnMyCommandCMPlugin();

	OSStatus			ExamineContext( const AEDesc *inAEContext, AEDescList *outCommandPairs ) override;
	OSStatus			HandleSelection( AEDesc *inAEContext, SInt32 inCommandID ) override;
	void				PostMenuCleanup() override;
	CFBundleRef			GetBundleRef() const override; // Abracode.framework, the engine's

private:
	ARefCountedObj<OnMyCommand>	mEngine;
};

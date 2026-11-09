//
//  OnMyCommandAE.cp
//  Abracode
//
//  The Apple event face of OnMyCommandCM: the contextual menu plugin API (ACMPlugin's ExamineContext
//  and HandleSelection, loaded by Shortcuts.app) and OMC.h's Apple event functions reach the engine
//  here. The Apple event descriptor of the selection is turned into an OMCHostSelection (CF) before
//  the engine's context check sees it; the engine itself takes no Apple event types for the context.
//  macOS only. Phase 5 step 6 (Private/phase5-interfaces-design.md).
//

#include "OnMyCommand.h"
#include "OMCHostSelection.h"
#include "OMCMenuModel.h"
#include "SubmenuTree.h"
#include "OMCConstants.h"
#include "CMUtils.h"
#include "StAEDesc.h"
#include "CFObj.h"
#include "DebugSettings.h"

// The selection a host handed over, in CF:
// - the items that are files, as CFURLs, the way CMUtils::ProcessObjectList took them (each item made
//   a file URL, those that cannot be are skipped), when the descriptor is a list;
// - the text, raw, when the descriptor holds text;
// - the Finder open-folder check, which needs the descriptor and Finder: valid while the request runs.
static void
MakeHostSelection(const AEDesc *inAEContext, OMCHostSelection &outSelection)
{
	outSelection.isNull = (inAEContext == nullptr) || (inAEContext->descriptorType == typeNull) || (inAEContext->dataHandle == nullptr);
	if(outSelection.isNull)
		return;

	long itemCount = 0;
	if(::AECountItems(inAEContext, &itemCount) == noErr)
	{
		CFObj<CFMutableArrayRef> files( CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks) );
		for(long i = 1; (i <= itemCount) && (files != nullptr); i++)
		{
			StAEDesc oneItem;
			AEKeyword theKeyword;
			if(::AEGetNthDesc(inAEContext, i, typeWildCard, &theKeyword, oneItem) == noErr)
			{
				CFObj<CFURLRef> oneURL( CMUtils::CopyURL(oneItem) );
				if(oneURL != nullptr)
					CFArrayAppendValue(files, oneURL);
			}
		}
		outSelection.files.Adopt( files.Detach() );
	}

	if(CMUtils::AEDescHasTextData(*inAEContext))
		outSelection.text.Adopt( CMUtils::CreateCFStringFromAEDesc(*inAEContext, kTextReplaceNothing) );

	outSelection.isClickInOpenFinderWindow = [inAEContext]()
	{
		return CMUtils::IsClickInOpenFinderWindow(inAEContext, false);
	};
}

// The menu as the Menu Manager's contextual menu API takes it: command records in an Apple event list,
// submenus nested, built from the engine's menu model in its order
static void
AddMenuToAEList(const OMCMenuModel &inMenu, AEDescList *ioRootMenu)
{
	if(ioRootMenu == nullptr)
		return;
	SubmenuTree itemTree(ioRootMenu);
	for(const OMCMenuItemEntry &entry : inMenu.items)
		itemTree.AddMenuItem(entry.submenuPath, entry.name, entry.commandRef, 0, kMenuNoModifiers);
	itemTree.BuildSubmenuTree();
}

//classic API for CM
OSStatus
OnMyCommandCM::ExamineContext( const AEDesc *inAEContext, AEDescList *outCommandPairs )
{
	OSStatus __unused err = Init();
	OMCHostSelection selection;
	MakeHostSelection(inAEContext, selection);
	OMCMenuModel menu;
	OSStatus checkErr = CommonContextCheck( selection.files, &selection, nullptr, (outCommandPairs != nullptr) ? &menu : nullptr, -1 /*inCmdIndex*/ );
	AddMenuToAEList(menu, outCommandPairs);
	return checkErr;
}

//new API for OMC.h
OSStatus
OnMyCommandCM::ExamineContext( const AEDesc *inAEContext, SInt32 inCommandRef, AEDescList *outCommandPairs )
{
	SInt32 cmdIndex = -1;
	if(inCommandRef >= kCMCommandStart)
		cmdIndex = mCurrCommandIndex = inCommandRef - kCMCommandStart;
	else
		mCurrCommandIndex = 0;

	OMCHostSelection selection;
	MakeHostSelection(inAEContext, selection);
	OMCMenuModel menu;
	OSStatus checkErr = CommonContextCheck( selection.files, &selection, nullptr, (outCommandPairs != nullptr) ? &menu : nullptr, cmdIndex );
	AddMenuToAEList(menu, outCommandPairs);
	return checkErr;
}

// Carry out the command that the user selected; the context is the one ExamineContext examined
// (inAEContext is the same selection, from the Menu Manager's contextual menu API)
OSStatus
OnMyCommandCM::HandleSelection( AEDesc *inAEContext, SInt32 inCommandRef )
{
	return ExecuteCommandRef(inCommandRef);
}

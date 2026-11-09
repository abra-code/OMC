//
//  OnMyCommandAE.cp
//  Abracode
//
//  The Apple event face of the engine: the contextual menu plugin's object (OnMyCommandCMPlugin,
//  loaded by Shortcuts.app) and OMC.h's Apple event functions (OMCRunCommandAE, OMCExamineContextAE,
//  OMCExecuteCommandAE) reach OnMyCommandCM here. The Apple event descriptor of the selection is
//  turned into an OMCHostSelection (CF) and the engine's menu model into the Menu Manager's
//  AEDescList; the engine itself takes no Apple event types.
//  macOS only. Phase 5 step 6 (Private/phase5-interfaces-design.md).
//

#include "OnMyCommandAE.h"
#include "OnMyCommand.h"
#include "OMC.h"
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

// The context check for an Apple event selection: one command (kCMCommandStart + index) or all of
// them (below kCMCommandStart); the menu is built whenever a list is given, also when the check then
// refuses the command
static OSStatus
ExamineAEContext(OnMyCommandCM &inEngine, const AEDesc *inAEContext, SInt32 inCommandRef, AEDescList *outCommandPairs)
{
	OMCHostSelection selection;
	MakeHostSelection(inAEContext, selection);
	OMCMenuModel menu;
	OSStatus checkErr = inEngine.ExamineHostSelection( selection, inCommandRef, (outCommandPairs != nullptr) ? &menu : nullptr );
	AddMenuToAEList(menu, outCommandPairs);
	return checkErr;
}

#pragma mark -
#pragma mark **** The contextual menu plugin's object ****

OnMyCommandCMPlugin::OnMyCommandCMPlugin()
	: ACMPlugin(nullptr) // the bundle is the engine's
	, mEngine(new OnMyCommandCM(nullptr), kARefCountDontRetain)
{
}

OnMyCommandCMPlugin::~OnMyCommandCMPlugin()
{
}

OSStatus
OnMyCommandCMPlugin::ExamineContext( const AEDesc *inAEContext, AEDescList *outCommandPairs )
{
	OSStatus __unused err = mEngine->Init();
	return ExamineAEContext(*mEngine, inAEContext, kOmcUnspecifiedCommand, outCommandPairs);
}

// Carry out the command that the user selected; the context is the one ExamineContext examined
// (inAEContext is the same selection, from the Menu Manager's contextual menu API)
OSStatus
OnMyCommandCMPlugin::HandleSelection( AEDesc *inAEContext, SInt32 inCommandID )
{
	return mEngine->ExecuteCommandRef(inCommandID);
}

void
OnMyCommandCMPlugin::PostMenuCleanup()
{
	mEngine->PostMenuCleanup();
}

CFBundleRef
OnMyCommandCMPlugin::GetBundleRef() const
{
	return mEngine->GetBundleRef();
}

#pragma mark -
#pragma mark **** OMC.h: the Apple event functions ****

//the same as OMCRunCommand() but takes AEDesc which may be text, file or a list of files

extern "C" OSStatus OMCRunCommandAE(CFTypeRef inPlistRef, CFStringRef inCommandNameOrID, AEDesc *inAEContext)
{
	OSStatus err = noErr;

	try
	{
		ARefCountedObj<OnMyCommandCM> omcPlugin(new OnMyCommandCM(inPlistRef), kARefCountDontRetain);
		omcPlugin->Init();
		SInt32 commandIndex = omcPlugin->FindCommandIndex(inCommandNameOrID);
		if(commandIndex < 0)
        {
            return fnfErr;
        }

		StAEDesc replacementContext;
		if((inAEContext != nullptr) && (inAEContext->dataHandle != nullptr))
		{
			if((inAEContext->descriptorType != typeAEList) &&
				(inAEContext->descriptorType != typeUnicodeText) &&
				(inAEContext->descriptorType != typeChar) &&
				(inAEContext->descriptorType != typeCString) &&
				(inAEContext->descriptorType != typePString) &&
				(inAEContext->descriptorType != typeUTF16ExternalRepresentation) &&
				(inAEContext->descriptorType != typeUTF8Text))
			{//try to coerce to see if it might be a single file ref
			//make a list even if single file. preferrable because Finder in 10.3 or higher does that
				StAEDesc coercedRef;
				err = ::AECoerceDesc(inAEContext, typeFileURL, coercedRef);
				if(err == noErr)
				{
					err = ::AECreateList(nullptr, 0, false, replacementContext);
					if(err == noErr)
					{
						err = ::AEPutDesc(replacementContext, // the list
											0, // put at the end of our list
											coercedRef);
						inAEContext = replacementContext;
					}
				}
			}
		}

		// all commands, as the contextual menu examines them: the activation is not checked here
		err = ExamineAEContext(*omcPlugin, inAEContext, kOmcUnspecifiedCommand, nullptr);
		if(err == noErr)
		{
			err = omcPlugin->ExecuteCommandRef(kCMCommandStart+commandIndex);
			omcPlugin->PostMenuCleanup();//currently doing nothing, just for completeness
		}
	}
	catch(...)
	{
		err = -1;
	}

	return err;
}

extern "C" OSStatus OMCExamineContextAE(OMCExecutorRef inOMCExecutor, OMCCommandRef inCmdRef, const AEDesc *inAEContext, AEDescList *outCommandPairs)
{
	try
	{
		if(inOMCExecutor != nullptr)
        {
            return ExamineAEContext(*inOMCExecutor, inAEContext, inCmdRef, outCommandPairs);
        }
	}
	catch(...)
	{

	}
	return paramErr;
}

extern "C" OSStatus OMCExecuteCommandAE(OMCExecutorRef inOMCExecutor, AEDesc *inAEContext, OMCCommandRef inCommandRef)
{
	OSStatus err = paramErr;

	try
	{
		if(inOMCExecutor != NULL)
		{
			if(OMCIsValidCommandRef(inCommandRef))
            {
                err = inOMCExecutor->ExecuteCommandRef(inCommandRef);
            }
			inOMCExecutor->PostMenuCleanup();//currently does nothing
		}
	}
	catch(...)
	{
		err = -1;
	}

	return err;
}

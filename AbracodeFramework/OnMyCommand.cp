//**************************************************************************************
// Filename:	OnMyCommandCM.cp
//
// Description:	Main OnMyCommand enigne methods
//
//**************************************************************************************


#include "OnMyCommand.h"
#include "CommandRuntimeData.h"
#include "OMCNavigationDialogs.h"
#include "CMUtils.h"
#include "CFObj.h"
#include "StAEDesc.h"
#include <string>
#include <vector>

#include "DebugSettings.h"
//#include "NavDialogs.h"
#include "OMCFilePanels.h"
#include "OmcExecutor.h"
//#include <sys/stat.h>
#include <unistd.h>
#include <regex.h>

// OMCCocoaHelper was only useful for CM plugins executed in-proc
// these days are long gone
//#include "OMCCocoaHelperExterns.h"
#include "MoreAppleEvents.h"
//#include "AAEDesc.h"
#include "NibDialogControl.h"
//#include "OMCCarbonDialog.h"
#include "SubmenuTree.h"
#include "StSwitchToFront.h"
#include "DefaultExternBundle.h"
#include "OmcTaskManager.h"
#include "ACFDict.h"
#include "ACFArr.h"
#include "OMCCocoaDialog.h"
#include "OMCInputDialog.h"
#include "SelectionIterator.h"
#include "ACFPropertyList.h"
#include "ACFURL.h"
#include "OMCHelpers.h"
#include "OMCStrings.h"
#include "OMCTerminalExecutor.h"
#include "OMCiTermExecutor.h"
#include "OMCEnvironmentExportScript.h"

enum
{
	kClearTextDialogIndx		= 128,
	kPasswordTextDialogIndx		= 129,
	kPopupMenuDialogIndx		= 130,
	kComboBoxDialogIndx			= 131
};

#pragma mark -
#pragma mark **** IMPLEMENTATION ****

CFStringRef kBundleIDString = CFSTR("com.abracode.AbracodeFramework");

SInt32 OnMyCommandCM::sMacOSVersion = 101300;

OnMyCommandCM::OnMyCommandCM(CFPropertyListRef inPlistRef)
	: ACMPlugin( kBundleIDString ) //mBundleRef is pointing to Abracode.framework bundle
{
	TRACE_CSTR( "OnMyCommandCM::OnMyCommandCM\n" );

	if(inPlistRef != NULL)
	{
		CFTypeID plistType = ::CFGetTypeID( inPlistRef );
		if(plistType == ACFType<CFURLRef>::GetTypeID())
		{
			mPlistURL.Adopt((CFURLRef)inPlistRef, kCFObjRetain);
			CFObj<CFStringRef> theExt( ::CFURLCopyPathExtension(mPlistURL) );
			if(theExt != NULL)
			{
				if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("omc"), theExt, kCFCompareCaseInsensitive) )
				{//it is an extern .omc bundle
					mExternBundleOverrideURL.Adopt( mPlistURL, kCFObjRetain );//it is a bundle URL actually
					CFObj<CFBundleRef> externBundle( CMUtils::CFBundleCreate(mPlistURL), kCFObjDontRetain );
					if(externBundle != NULL)
						mPlistURL.Adopt( ::CFBundleCopyResourceURL( externBundle, CFSTR("Command.plist"), NULL, NULL ), kCFObjDontRetain );
				}
			}
		}
		else if(plistType == ACFType<CFDictionaryRef>::GetTypeID())
		{
			LoadCommandsFromPlistRef(inPlistRef);
		}
	}
}


OnMyCommandCM::~OnMyCommandCM()
{
	TRACE_CSTR( "OnMyCommandCM::~OnMyCommandCM this=%p\n", (void*)this );
	try
	{
		DeleteCommandList();
	}
	catch(...)
	{
		LOG_CSTR( "OnMyCommandCM::~OnMyCommandCM: unknown exception has been caught\n" );
	}
}

OSStatus
OnMyCommandCM::Init()
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		long sysVerMajor = 10;
		long sysVerMinor = 13;
		long sysVerBugFix = 0;

		GetOperatingSystemVersion(&sysVerMajor, &sysVerMinor, &sysVerBugFix);
		
		//eg. 101405 max 999999
		sMacOSVersion = 10000 * (SInt32)sysVerMajor + 100 * (SInt32)sysVerMinor + (SInt32)sysVerBugFix;
	});

//#if _DEBUG_
//	printf("OMC: Current system version = 0x%.8X, integer = %d\n", (unsigned int)mSysVersion, (int)mSysVersion);
//#endif

	CFObj<CFURLRef> myHostBundleURL = CFBundleCopyBundleURL(CFBundleGetMainBundle());
	mMyHostBundlePath.Adopt(CreatePathFromCFURL(myHostBundleURL, kEscapeNone), kCFObjDontRetain);
	mMyHostAppName.Adopt(CopyHostAppName(), kCFObjDontRetain);

	InitOmcBundlePaths();

#if  0 //_DEBUG_
	CFShow((CFStringRef)mMyHostBundlePath);
#endif

	return noErr;
}

void
OnMyCommandCM::InitOmcBundlePaths()
{
	CFObj<CFURLRef> abracodeFrameworkBundleURL = CFBundleCopyBundleURL(mBundleRef);
	if(abracodeFrameworkBundleURL != nullptr)
	{
		CFObj<CFURLRef> supportPathURL(CFURLCreateCopyAppendingPathComponent(
									kCFAllocatorDefault,
									abracodeFrameworkBundleURL,
									CFSTR("Versions/Current/Support"),
									true));
		mOmcSupportPath.Adopt(CreatePathFromCFURL(supportPathURL, kEscapeNone), kCFObjDontRetain);
	}

	CFObj<CFURLRef> resPathURL = CFBundleCopyResourcesDirectoryURL(mBundleRef);
	mOmcResourcesPath.Adopt(CreatePathFromCFURL(resPathURL, kEscapeNone), kCFObjDontRetain);

}

//classic API for CM
OSStatus
OnMyCommandCM::ExamineContext( const AEDesc *inAEContext, AEDescList *outCommandPairs )
{
	OSStatus __unused err = Init();
	return CommonContextCheck( inAEContext, NULL, outCommandPairs, -1 /*inCmdIndex*/ );
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

	return CommonContextCheck( inAEContext, NULL, outCommandPairs, cmdIndex );
}

//new API for OMC.h
OSStatus
OnMyCommandCM::ExamineContext( CFTypeRef inContext, SInt32 inCommandRef )
{
	SInt32 cmdIndex = -1;
	if(inCommandRef >= kCMCommandStart)
		cmdIndex = mCurrCommandIndex = inCommandRef - kCMCommandStart;
	else
		mCurrCommandIndex = 0;

	return CommonContextCheck( NULL, inContext, NULL, cmdIndex );
}

// it is OK to have NULL AE or CF, or both contexts here

OSStatus
OnMyCommandCM::CommonContextCheck( const AEDesc *inAEContext, CFTypeRef inContext, AEDescList *outCommandPairs, SInt32 inCmdIndex )
{
	TRACE_CSTR( "OnMyCommandCM::CommonContextCheck\n" );
	OSStatus err = noErr;

    // Create new command runtime data, temporarily stored in mInitialRuntimeData
    // mInitialRuntimeData should be emptied in ExecuteCommand() and
    // CommandRuntimeData should live on idependently of OnMyCommandCM object
    // Make sure we don't have any previous runtime data when we start a new command context check and execution
    // mInitialRuntimeData should be valid for ExecuteCommand() only if CommonContextCheck() returns noErr
    
    assert(mInitialRuntimeData == nullptr);
    mInitialRuntimeData.Adopt(new CommandRuntimeData());
    OMCContextData &contextData = mInitialRuntimeData->GetContextData();
    
#if _DEBUG_
	if(inAEContext != NULL)
	{
		DEBUG_CFSTR( CFSTR("OnMyCommandCM::ExamineContext. Data type is:") );
		CFObj<CFStringRef> dbgType( ::UTCreateStringForOSType(inAEContext->descriptorType) );
		DEBUG_CFSTR( (CFStringRef)dbgType );
	}
#endif

	ResetOutputWindowCascading();
	
	//from now on we assume that PostMenuCleanup will be called so we own the data

    contextData.isTextInClipboard = CMUtils::IsTextInClipboard();

	//remember if the context was null on CMPluginExamineContext
	//we cannot trust it when handling the selection later
	if(inAEContext != NULL)
        contextData.isNullContext = ((inAEContext->descriptorType == typeNull) || (inAEContext->dataHandle == NULL));
	else
        contextData.isNullContext = (inContext == NULL);

    CFObj<CFMutableArrayRef> contextFiles;
    
	if(inContext != NULL)
	{
		CFTypeID contextType = ::CFGetTypeID( inContext );
		if( contextType == ACFType<CFStringRef>::GetTypeID() )//text
		{
            contextData.contextText.Adopt( (CFStringRef)inContext, kCFObjRetain);
			contextData.isTextContext = true;
		}
		else if( contextType == ACFType<CFArrayRef>::GetTypeID() ) //list of files
		{
			contextFiles.Adopt(
					::CFArrayCreateMutable(kCFAllocatorDefault, contextData.objectList.size(), &kCFTypeArrayCallBacks),
					kCFObjDontRetain );

			CFArrayRef fileArray = (CFArrayRef)inContext;
			CFIndex fileCount = ::CFArrayGetCount(fileArray);
			if( (fileCount > 0) && (contextFiles != NULL) )
			{
				for(CFIndex i = 0; i < fileCount; i++)
				{
					CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(fileArray, i);
					if(oneItemRef != NULL)
					{
						CFObj<CFURLRef> oneUrl;
						contextType = ::CFGetTypeID( oneItemRef );

						if( contextType == ACFType<CFStringRef>::GetTypeID() )//text
						{
							//somebody was lazy and gave us a path - we accept only POSIX paths
							oneUrl.Adopt( ::CFURLCreateWithFileSystemPath (
													kCFAllocatorDefault,
													(CFStringRef)oneItemRef,
													kCFURLPOSIXPathStyle,
													false), kCFObjDontRetain);
						}
						else if( contextType == ACFType<CFURLRef>::GetTypeID() )
						{
							oneUrl.Adopt( (CFURLRef)oneItemRef, kCFObjRetain );
						}
						
						if(oneUrl != NULL)
							::CFArrayAppendValue( contextFiles, (CFURLRef)oneUrl );
					}
				}
			}
		}
		else if( contextType == ACFType<CFURLRef>::GetTypeID() )
		{//make a list even if single file. preferrable because Finder in 10.3 or higher does that
			contextFiles.Adopt(
								::CFArrayCreateMutable(kCFAllocatorDefault, 1, &kCFTypeArrayCallBacks),
								kCFObjDontRetain );
			::CFArrayAppendValue( contextFiles, (CFURLRef)inContext );
		}
		else
		{
			LOG_CSTR( "OMC->CommonContextCheck: unknown context type\n" );
		}
	}

	Boolean runningInEditorApp = false;
	Boolean frontProcessIsFinder = false;
    Boolean runningInShortcutsObserver = false;

	CFStringRef hostAppBundleID = CFBundleGetIdentifier(CFBundleGetMainBundle());
	if(hostAppBundleID != NULL)
	{
        if(kCFCompareEqualTo == ::CFStringCompare(hostAppBundleID, CFSTR("com.abracode.OMCService"), 0))
        {
            mHostApp = kOMCHostApp_OMCService;
        }
		else if(kCFCompareEqualTo == ::CFStringCompare(hostAppBundleID, CFSTR("com.abracode.ShortcutObserver"), 0))
		{
            mHostApp = kOMCHostApp_ShortcutsObserver;
            runningInShortcutsObserver = true;
		}
        else if(kCFCompareEqualTo == ::CFStringCompare(hostAppBundleID, CFSTR("com.abracode.Shortcuts"), 0))
        {
            mHostApp = kOMCHostApp_Shortcuts;
            runningInEditorApp = true;
        }
        else if(kCFCompareEqualTo == ::CFStringCompare(hostAppBundleID, CFSTR("de.MacDisk.Knut.OMCEdit"), 0))
        {
            mHostApp = kOMCHostApp_OMCEdit;
            runningInEditorApp = true;
        }
	}
	
    if((mHostApp == kOMCHostApp_OMCService) || (mHostApp == kOMCHostApp_ShortcutsObserver))
    {
        //remember front process pid at the moment of context check
        //in case it gets changed later, we need to keep it
        mFrontProcessPID = GetFrontAppPID();
        
        CFObj<CFStringRef> frontProcessBundleID = CopyFrontAppBundleIdentifier();
        if(frontProcessBundleID != nullptr)
        {
            if( kCFCompareEqualTo == ::CFStringCompare( frontProcessBundleID, CFSTR("com.apple.finder"), 0 ) )
                frontProcessIsFinder = true;
        }
    }
    	
	if(mCommandList == NULL)
	{//not loaded yet?
		if( mPlistURL != NULL )
			LoadCommandsFromPlistFile(mPlistURL);
		else
			ReadPreferences();
	}

	Boolean anythingSelected = false;

	UInt32 theFlags = kListClear;
    size_t validObjectCount = 0;
	if( !contextData.isNullContext && !contextData.isTextContext ) //we have some context that is not text
	{
		TRACE_CSTR( "OnMyCommandCM->CMPluginExamineContext: not null context descriptor\n" );
		//pre-allocate space for all object properties
		long listItemsCount = 0;
		err = paramErr;
		if(inAEContext != NULL)
		{
			err = ::AECountItems(inAEContext, &listItemsCount);
		}
		else if(contextFiles != NULL)
		{
			listItemsCount = ::CFArrayGetCount(contextFiles);
			err = noErr;
		}
		
		if(err  == noErr )
		{
			TRACE_CSTR( "OnMyCommandCM->CMPluginExamineContext: count of items in context: %d\n", (int)listItemsCount );

			if(listItemsCount > 0)
			{
				contextData.objectList.resize(listItemsCount);
			}
		}
        
		if( contextFiles != NULL )
            validObjectCount = CMUtils::ProcessObjectList( contextFiles, theFlags, CFURLCheckFileOrFolder, &contextData.objectList);
		else if(inAEContext != NULL)
            validObjectCount = CMUtils::ProcessObjectList( inAEContext, theFlags, CFURLCheckFileOrFolder, &contextData.objectList );

        anythingSelected = (validObjectCount > 0);
	}

    //update total count
    contextData.objectList.resize(validObjectCount);

	Boolean isFolder = false;
	if(contextData.objectList.size() == 1)
	{
		isFolder = CheckAllObjects(contextData.objectList, CheckIfFolder, NULL);
		if(isFolder)
		{
			Boolean isPackage = CheckAllObjects(contextData.objectList, CheckIfPackage, NULL);
			if(isPackage)
				isFolder = false;
		}
	}

	if(	anythingSelected && ((theFlags & kListOutMultipleObjects) == 0) && isFolder &&
		(runningInShortcutsObserver && frontProcessIsFinder) )
	{//single folder selected in Finder - check what it is
        contextData.isOpenFolder = CMUtils::IsClickInOpenFinderWindow(inAEContext, false);
		anythingSelected = ! contextData.isOpenFolder;
	}
	else if( !anythingSelected && !contextData.isTextContext )
	{//not a list of objects, maybe a selected text?
		if( (inAEContext != nullptr) && !contextData.isNullContext )
            contextData.isTextContext = CMUtils::AEDescHasTextData(*inAEContext);
	}

	err = noErr;

	CFObj<CFStringRef> frontProcessName = CopyFrontAppName();

	//menu population requested
	if(outCommandPairs != NULL)
	{
		(void)PopulateItemsMenu(inAEContext,
                                *mInitialRuntimeData,
                                outCommandPairs,
								runningInEditorApp || runningInShortcutsObserver,
								frontProcessName);
	}
	
	if(inCmdIndex >= 0)
	{
		bool isEnabled = IsCommandEnabled(inCmdIndex,
                                          inAEContext,
                                          contextData,
                                          runningInEditorApp || runningInShortcutsObserver,
                                          frontProcessName);
		if( !isEnabled )
			err = errAEWrongDataType;
	}
	
    if(err != noErr)
    {
        mInitialRuntimeData = nullptr;
    }

	return err;
}

// ---------------------------------------------------------------------------
// HandleSelection
// ---------------------------------------------------------------------------
// Carry out the command that the user selected. The commandID indicates 
// which command was selected

// pass nullptr for inAEContext when executing with CF Context

OSStatus
OnMyCommandCM::HandleSelection( AEDesc *inAEContext, SInt32 inCommandRef )
{
    if(inCommandRef < kCMCommandStart)
    {
        LOG_CSTR( "HandleSelection: unknown menu item ID. Aliens?\n" );
        mInitialRuntimeData = nullptr; // discard the runtime data created in context check
        return paramErr;
    }

    SInt32 cmdIndex = inCommandRef - kCMCommandStart;

    return ExecuteCommand(inAEContext, cmdIndex, nullptr /*parentCommandRuntimeData*/ );
}

// pass nullptr for inAEContext when executing with CF Context
// NO RETURNS IN THE MIDDLE!

OSStatus
OnMyCommandCM::ExecuteCommand(AEDesc *inAEContext, SInt32 inCommandIndex, const CommandRuntimeData *parentCommandRuntimeData)
{
	TRACE_CSTR( "OnMyCommandCM::ExecuteCommand\n" );

    ARefCountedObj<CommandRuntimeData> commandRuntimeData = mInitialRuntimeData;
    assert(commandRuntimeData != nullptr);
    mInitialRuntimeData = nullptr;
    
	if((mCommandList == nullptr) || (mCommandCount == 0))
    {
        return noErr;
    }
    
    // retain self here to ensure the safety of all operations in scope
    ARefCountedObj<OnMyCommandCM> localRetain(this, kARefCountRetain);

	try
	{
		if( inCommandIndex < 0 || inCommandIndex >= mCommandCount )
			throw OSStatus(paramErr);

        mCurrCommandIndex = inCommandIndex;
		CommandDescription &currCommand = mCommandList[mCurrCommandIndex];
        
        // if we have a parent command runtime data
        // we need to resolve the parent context with our own data created in context check
         if(parentCommandRuntimeData != nullptr)
        {
            // a data with null context from our prior context check can be replaced with data from parent
            if(commandRuntimeData->GetContextData().isNullContext)
            {
                // preserve our own command UUID, not the one from parent command
                // but other than that transfer all other data from parent
                CFObj<CFStringRef> commandUUID(commandRuntimeData->GetCommandUUID(), kCFObjRetain);
                commandRuntimeData.Adopt(new CommandRuntimeData(*parentCommandRuntimeData));
                commandRuntimeData->SetCommandUUID(commandUUID);
            }
            else
            {
                // TODO: decide what are we going to do with both non-null conext and a parent runtime data
                assert(false);
            }
        }
        
        OMCContextData &contextData = commandRuntimeData->GetContextData();

		CGEventFlags keyboardModifiers = GetKeyboardModifiers();
		//only if lone control key is pressed we consider it a debug request
		currCommand.debugging = ((keyboardModifiers &
								(kCGEventFlagMaskAlphaShift | kCGEventFlagMaskShift | kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand)) == 0)
								&& ((keyboardModifiers & kCGEventFlagMaskControl) != 0);
		
		//take original command by reference, not copy
		PrescanCommandDescription( currCommand );
		
		CFBundleRef localizationBundle = NULL;
		if(currCommand.localizationTableName != NULL)//client wants to be localized
		{
			localizationBundle = GetCurrentCommandExternBundle();
			if(localizationBundle == NULL)
				localizationBundle = CFBundleGetMainBundle();
		}

		//obtain text from selection before any dialogs are shown
		bool objListEmpty = (contextData.objectList.size() == 0);
		
		if( ((currCommand.prescannedCommandInfo & kOmcCommandContainsTextObject) != 0) && (contextData.contextText == NULL) )
		{
			CreateTextContext(currCommand, contextData, inAEContext);
		}

		CFObj<CFStringRef> dynamicCommandName( CreateDynamicCommandName(currCommand,
                                                                        *commandRuntimeData,
                                                                        currCommand.localizationTableName,
                                                                        localizationBundle) );

		if(CURRENT_OMC_VERSION < currCommand.requiredOMCVersion )
		{
			StSwitchToFront switcher;
			CFObj<CFStringRef> warningText( ::CFCopyLocalizedStringFromTableInBundle( CFSTR("TOO_LOW_OMC"),
															CFSTR("Private"), mBundleRef, "") );

			if( false == DisplayVersionWarning(mBundleRef, dynamicCommandName, warningText, currCommand.requiredOMCVersion, CURRENT_OMC_VERSION) )
			{
				throw OSStatus(userCanceledErr);
			}
		}
		
		if( sMacOSVersion < currCommand.requiredMacOSMinVersion)
		{
			StSwitchToFront switcher;
			CFObj<CFStringRef> warningText( ::CFCopyLocalizedStringFromTableInBundle( CFSTR("TOO_LOW_MAC_OS"),
															CFSTR("Private"), mBundleRef, "") );

			if( false == DisplayVersionWarning(mBundleRef, dynamicCommandName, warningText, currCommand.requiredMacOSMinVersion, sMacOSVersion) )
			{
				throw OSStatus(userCanceledErr);
			}
		}
		
		if(sMacOSVersion > currCommand.requiredMacOSMaxVersion)
		{
			StSwitchToFront switcher;
			CFObj<CFStringRef> warningText( ::CFCopyLocalizedStringFromTableInBundle( CFSTR("TOO_HIGH_MAC_OS"),
															CFSTR("Private"), mBundleRef, "") );

			if( false == DisplayVersionWarning(mBundleRef, dynamicCommandName, warningText, currCommand.requiredMacOSMaxVersion, sMacOSVersion) )
			{
				throw OSStatus(userCanceledErr);
			}
		}
		
		if( currCommand.warningStr != NULL )
		{
			TRACE_CSTR("OnMyCommandCM About to display warning\n" );
			StSwitchToFront switcher;
			if( DisplayWarning(currCommand, *commandRuntimeData) == false )
			{
				throw OSStatus(userCanceledErr);
			}
		}
		
		if(((currCommand.prescannedCommandInfo & kOmcCommandContainsInputText) != 0) && (commandRuntimeData->inputText == nullptr))
		{
			TRACE_CSTR( "OnMyCommandCM About to ask for input text\n" );
			StSwitchToFront switcher;

			//if( ShowInputDialog( currCommand, mInputText.GetReference() ) == false )
			if( RunCocoaInputDialog( this, *commandRuntimeData) == false )
			{
				throw OSStatus(userCanceledErr);
			}
		}

		if((currCommand.prescannedCommandInfo & kOmcCommandContainsSaveAsDialog) != 0)
		{
            PresentSaveAsDialog(this,
                                *commandRuntimeData,
                                dynamicCommandName,
                                localizationBundle);
		}
		
		if((currCommand.prescannedCommandInfo & kOmcCommandContainsChooseFileDialog) != 0)
		{
            PresentChooseFileDialog(this,
                                    *commandRuntimeData,
                                    dynamicCommandName,
                                    localizationBundle);
		}

		if((currCommand.prescannedCommandInfo & kOmcCommandContainsChooseFolderDialog) != 0)
		{
            PresentChooseFolderDialog(this,
                                    *commandRuntimeData,
                                    dynamicCommandName,
                                    localizationBundle);
		}

		if((currCommand.prescannedCommandInfo & kOmcCommandContainsChooseObjectDialog) != 0)
		{
            PresentChooseObjectDialog(this,
                                      *commandRuntimeData,
                                      dynamicCommandName,
                                      localizationBundle);
		}
        
		if( objListEmpty || contextData.isTextContext )//text context
		{
			TRACE_CSTR("OnMyCommandCM->ExecuteCommand: about to process command with text selection\n" );
			ExecuteCommandWithText(currCommand, contextData.contextText, commandRuntimeData);
		}
		else //file context
		{
			TRACE_CSTR("OnMyCommandCM About to proces file list\n" );
			ExecuteCommandWithObjects(commandRuntimeData);
		}
		
		//we used to do some post-processing here but now most commands are async so we need to call Finalize when task ends

		TRACE_CSTR("OnMyCommandCM->ExecuteCommand: finished successfully\n" );
	}
	catch(OSStatus &thrownError)
	{
		if(thrownError == userCanceledErr)
		{
			mError = userCanceledErr;
			TRACE_CSTR("OnMyCommandCM->ExecuteCommand: user cancelled\n" );
		}
	}
	catch(...)
	{
		LOG_CSTR( "OnMyCommandCM->ExecuteCommand: unknown error ocurred\n" );
		mError = -1;
	}

    return noErr;
}


void
OnMyCommandCM::PostMenuCleanup()
{
	TRACE_CSTR( "OnMyCommandCM::PostMenuCleanup\n" );
    // sometimes context check is not followed by ExecuteCommand() - discard runtime data
    mInitialRuntimeData = nullptr;
}


void
OnMyCommandCM::DeleteCommandList()
{
	if( mCommandList != NULL )
	{
		for(UInt32 i = 0; i < mCommandCount; i++)
		{
			if(mCommandList[i].name != NULL)
				::CFRelease(mCommandList[i].name);

			if(mCommandList[i].namePlural != NULL)
				::CFRelease(mCommandList[i].namePlural);

			if(mCommandList[i].command != NULL)
				::CFRelease(mCommandList[i].command);
				
			if(mCommandList[i].inputPipe != NULL)
				::CFRelease(mCommandList[i].inputPipe);

			if(mCommandList[i].activationExtensions != NULL)
				::CFRelease(mCommandList[i].activationExtensions);
	
			if( mCommandList[i].activationTypes != NULL )
				delete [] mCommandList[i].activationTypes;

			if(mCommandList[i].mulObjPrefix != NULL)
				::CFRelease(mCommandList[i].mulObjPrefix);

			if(mCommandList[i].mulObjSuffix != NULL)
				::CFRelease(mCommandList[i].mulObjSuffix);

			if(mCommandList[i].mulObjSeparator != NULL)
				::CFRelease(mCommandList[i].mulObjSeparator);
			
			if(mCommandList[i].warningStr != NULL)
				::CFRelease(mCommandList[i].warningStr);
			
			if(mCommandList[i].warningExecuteStr != NULL)
				::CFRelease(mCommandList[i].warningExecuteStr);

			if(mCommandList[i].warningCancelStr != NULL)
				::CFRelease(mCommandList[i].warningCancelStr);

			if(mCommandList[i].submenuName != NULL)
				::CFRelease(mCommandList[i].submenuName);

			if(mCommandList[i].inputDialogOK != NULL)
				::CFRelease(mCommandList[i].inputDialogOK);

			if(mCommandList[i].inputDialogCancel != NULL)
				::CFRelease(mCommandList[i].inputDialogCancel);

			if(mCommandList[i].inputDialogMessage != NULL)
				::CFRelease(mCommandList[i].inputDialogMessage);

			if(mCommandList[i].inputDialogDefault != NULL)
				::CFRelease(mCommandList[i].inputDialogDefault);

			if(mCommandList[i].inputDialogMenuItems != NULL)
				::CFRelease(mCommandList[i].inputDialogMenuItems);
			
			if(mCommandList[i].refresh != NULL)
				::CFRelease(mCommandList[i].refresh);

			if(mCommandList[i].saveAsParams != NULL)
				::CFRelease(mCommandList[i].saveAsParams);
			
			if(mCommandList[i].chooseFileParams != NULL)
				::CFRelease(mCommandList[i].chooseFileParams);	
			
			if(mCommandList[i].chooseFolderParams != NULL)
				::CFRelease(mCommandList[i].chooseFolderParams);

			if(mCommandList[i].chooseObjectParams != NULL)
				::CFRelease(mCommandList[i].chooseObjectParams);

			if(mCommandList[i].outputWindowOptions != NULL)
				::CFRelease(mCommandList[i].outputWindowOptions);
				
			if(mCommandList[i].nibDialog != NULL)
				::CFRelease(mCommandList[i].nibDialog);

			if(mCommandList[i].appNames != NULL)
				::CFRelease(mCommandList[i].appNames);

			if(mCommandList[i].commandID != NULL)
				::CFRelease(mCommandList[i].commandID);
			
			if(mCommandList[i].nextCommandID != NULL)
				::CFRelease(mCommandList[i].nextCommandID);

			if(mCommandList[i].externalBundlePath != NULL)
				::CFRelease(mCommandList[i].externalBundlePath);
			
			if(mCommandList[i].externBundle != NULL)
				::CFRelease(mCommandList[i].externBundle);
			
			if(mCommandList[i].popenShell != NULL)
				::CFRelease(mCommandList[i].popenShell);
			
			if(mCommandList[i].customEnvironVariables != NULL)
				::CFRelease(mCommandList[i].customEnvironVariables);

			if(mCommandList[i].specialRequestedNibControls != nullptr)
				::CFRelease(mCommandList[i].specialRequestedNibControls);

			if(mCommandList[i].iTermShellPath != NULL)
				::CFRelease(mCommandList[i].iTermShellPath);

			if(mCommandList[i].endNotification != NULL)
				::CFRelease(mCommandList[i].endNotification);

			if(mCommandList[i].progress != NULL)
				::CFRelease(mCommandList[i].progress);
		
			if(mCommandList[i].contextMatchString != NULL)
				::CFRelease(mCommandList[i].contextMatchString);
		
			if(mCommandList[i].multipleSelectionIteratorParams != NULL)
				::CFRelease(mCommandList[i].multipleSelectionIteratorParams);
				
			if(mCommandList[i].localizationTableName != NULL)
				::CFRelease(mCommandList[i].localizationTableName);
		}

		delete [] mCommandList;
		mCommandList = NULL;
	}
	mCommandCount = 0;
}

//external API, needs to load commands if needed
SInt32
OnMyCommandCM::FindCommandIndex( CFStringRef inNameOrId )
{
	if(mCommandList == NULL)
	{//not loaded yet?
		if( mPlistURL != NULL )
			LoadCommandsFromPlistFile(mPlistURL);
		else
			ReadPreferences();
	}

	if( (mCommandList == NULL) || (mCommandCount == 0) )
		return -1;

	CFStringRef commandName = inNameOrId;
	CFStringRef commandId = inNameOrId;
	if(inNameOrId == NULL)
	{
		commandId = kOMCTopCommandID;//find first top command
	}

	SInt32 idCandidate = -1;
	SInt32 nameCandidate = -1;
	
	for(SInt32 i = 0; i < (SInt32)mCommandCount; i++)
	{
		if( (mCommandList[i].commandID != NULL) && ::CFEqual(mCommandList[i].commandID, commandId) )
		{
			idCandidate = i;
			break;
		}
		else if( (commandName != NULL) && (mCommandList[i].name != NULL) )
		{
			CFObj<CFStringRef> combinedName( ::CFStringCreateByCombiningStrings(kCFAllocatorDefault, mCommandList[i].name, CFSTR("")) );
			if( (combinedName != NULL) && ::CFEqual( (CFStringRef)combinedName, commandName) )
			{
				//found command by name, now get the top one (becuase this one might be a subcommand)
				nameCandidate = i;

				for(SInt32 j = i; j < (SInt32)mCommandCount; j++)
				{
					if( (mCommandList[j].name != NULL) &&
						(mCommandList[j].commandID != NULL) && ::CFEqual(mCommandList[j].commandID, kOMCTopCommandID) )
					{
						CFObj<CFStringRef> subCombinedName( ::CFStringCreateByCombiningStrings(kCFAllocatorDefault, mCommandList[j].name, CFSTR("")) );
						if( (subCombinedName != NULL) && ::CFEqual( (CFStringRef)subCombinedName, commandName) )
						{
							idCandidate = j;
							break;
						}
					}
				}
				break;
			}
		}
	}

	if(idCandidate >= 0)
		return idCandidate;

	return nameCandidate;
}

#pragma mark -

static CFStringRef
CreateTerminalCommandWithEnvironmentSetup(CFStringRef inCommand,
                                          CommandDescription &currCommand,
                                          CommandRuntimeData &commandRuntimeData,
                                          CFDictionaryRef environList,
                                          bool isSh)
{
	CFStringRef commandUUID = commandRuntimeData.GetCommandUUID();
	WriteEnvironmentSetupScriptToTmp(environList, commandUUID, isSh);
	CFObj<CFStringRef> envSetupCommand = CreateEnvironmentSetupCommandForShell(commandUUID, isSh);
	CFObj<CFMutableStringRef> commandWithEnvSetup = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, envSetupCommand);
	CFStringAppend(commandWithEnvSetup, inCommand);
	return commandWithEnvSetup.Detach();
}


OSStatus
OnMyCommandCM::ExecuteCommandWithObjects(CommandRuntimeData *initialCommandRuntimeData)
{
    assert(initialCommandRuntimeData != nil);
    OMCContextData &initialContextData = initialCommandRuntimeData->GetContextData();
    
	if( (mCommandList == nullptr) || (mCommandCount == 0) || (initialContextData.objectList.size() == 0) )
		return noErr;

	if( mCurrCommandIndex >= mCommandCount)
		return paramErr;

	CommandDescription &currCommand = mCommandList[mCurrCommandIndex];
	CFBundleRef externBundle = GetCurrentCommandExternBundle();
	CFBundleRef localizationBundle = nullptr;
	if(currCommand.localizationTableName != nullptr)//client wants to be localized
	{
		localizationBundle = externBundle;
		if(localizationBundle == nullptr)
			localizationBundle = CFBundleGetMainBundle();
	}

	TRACE_CSTR("OnMyCommandCM. ExecuteCommandWithObjects\n" );
	
	CFObj<CFStringRef> dynamicCommandName( CreateDynamicCommandName(currCommand,
                                                                    *initialCommandRuntimeData,
                                                                    currCommand.localizationTableName,
                                                                    localizationBundle) );

	CFIndex objectCount = initialContextData.objectList.size();
	if( currCommand.multipleObjectProcessing == kMulObjProcessTogether )
    {
        objectCount = 1;
    }
    
	CFIndex maxTaskCount = currCommand.maxTaskCount;
	if( maxTaskCount <= 0 )//max task count not specified explicitly, use reasonable default value
	{
		if(objectCount > 1)
		{
			host_basic_info *hostInfo = GetHostBasicInfo();
			if(hostInfo != nullptr)
				maxTaskCount = (2 * hostInfo->avail_cpus /*logical_cpu*/);
		}
		else
        {
            maxTaskCount = 1;//don't care becuase we will have only one task
        }
	}

	OmcHostTaskManager *taskManager = new OmcHostTaskManager( this, currCommand, dynamicCommandName, mBundleRef, maxTaskCount );

    ARefCountedObj<OMCDialog> initalActiveDialog;
    // is this a subcommand triggered from already active dialog?
    initalActiveDialog = OMCDialog::FindDialogByUUID(initialCommandRuntimeData->GetAssociatedDialogUUID());
    if(initalActiveDialog != nullptr)
    {
        SelectionIterator* selIterator = initalActiveDialog->GetSelectionIterator();
        initalActiveDialog->CopyAllControlValues(currCommand.specialRequestedNibControls, selIterator);
    }

	if( currCommand.refresh != nullptr )
	{//refreshing needed - compose array of paths before performing any action
		for(CFIndex i = 0; i < initialContextData.objectList.size(); i++)
		{
			TRACE_CSTR("OnMyCommandCM. create refresh path\n" );
            initialContextData.currObjectIndex = i;
			CFObj<CFMutableStringRef> onePath( CreateCombinedStringWithObjects(currCommand.refresh,
                                                                               *initialCommandRuntimeData,
                                                                               nullptr,
                                                                               nullptr) );
            initialContextData.objectList[i].refreshPath.Adopt(CreatePathByExpandingTilde(onePath));
		}
	}

	UInt8 executionMode = currCommand.executionMode;
	if(currCommand.debugging)
	{ //when in debuggging mode, change silent executions to executions with output windows
		if(executionMode == kExecSilentPOpen)
			executionMode = kExecPOpenWithOutputWindow;
		else if(executionMode == kExecPopenScriptFile)
			executionMode = kExecPopenScriptFileWithOutputWindow;
		else if(executionMode == kExecAppleScript)
			executionMode = kExecAppleScriptWithOutputWindow;
	}

	for(CFIndex i = 0; i < objectCount; i++)
	{
        ARefCountedObj<CommandRuntimeData> commandRuntimeData;
		if(currCommand.multipleObjectProcessing == kMulObjProcessTogether)
        {
            initialContextData.currObjectIndex = -1; // invalid index means process them all together
            assert(objectCount == 1);
            commandRuntimeData.Adopt(initialCommandRuntimeData, kARefCountRetain);
        }
		else
        {
            // Create a new CommandRuntimeData with a single file context data
            initialContextData.currObjectIndex = i;
            commandRuntimeData.Adopt(new CommandRuntimeData(*initialCommandRuntimeData, i));
        }
        
        if(commandRuntimeData == nullptr)
        {
            throw OSStatus(memFullErr);
        }
                
        ARefCountedObj<OMCDialog> activeDialog;
        // is this command creating a new dialog?
        if( currCommand.nibDialog != nullptr )
        {
			// bring executing application to front. important when running within ShortcutsObserver
			// don't restore because for non-modal dialogs this would bring executing app behind along with the dialog
			StSwitchToFront switcher(false);
			
			 // we create one dialog for all objects or we create for each object when processing separately
			activeDialog = RunCocoaDialog(this, commandRuntimeData);
			if(activeDialog != nullptr)
			{
				SelectionIterator* selIterator = activeDialog->GetSelectionIterator();
				activeDialog->CopyAllControlValues(currCommand.specialRequestedNibControls, selIterator);
			}
			else
			{
				throw OSStatus(userCanceledErr);
			}
        }

		UInt8 escapingMode = currCommand.escapeSpecialCharsMode;
		if((executionMode == kExecPopenScriptFile) ||
			(executionMode == kExecPopenScriptFileWithOutputWindow))
        {
            escapingMode = kEscapeNone; //the command is actually a path and will not be interpeted by any shell
        }
        
		CFObj<CFMutableStringRef> theCommand( CreateCommandStringWithObjects(currCommand.command, *commandRuntimeData, escapingMode) );
		CFObj<CFMutableStringRef> inputPipe( CreateCommandStringWithObjects(currCommand.inputPipe, *commandRuntimeData, kEscapeNone) );
		CFObj<CFDictionaryRef> environList( CreateEnvironmentVariablesDict(NULL, *commandRuntimeData) );

		ARefCountedObj<OmcExecutor> theExec;
        
		CFObj<CFStringRef> objName(CreateObjName(commandRuntimeData->GetAssociatedObject(), NULL));
			
		switch(executionMode)
		{
			case kExecTerminal:
			{
				bool isSh = IsShDefaultInTerminal();
				CFObj<CFStringRef> commandWithEnvSetup = CreateTerminalCommandWithEnvironmentSetup(theCommand,
                                                                                                   currCommand,
                                                                                                   *commandRuntimeData,
                                                                                                   environList,
                                                                                                   isSh);
				ExecuteInTerminal( commandWithEnvSetup, currCommand.openNewTerminalSession, currCommand.bringTerminalToFront);
			}
			break;
			
			case kExecITerm:
			{
				bool isSh = IsShDefaultInITem();
				CFObj<CFStringRef> commandWithEnvSetup = CreateTerminalCommandWithEnvironmentSetup(theCommand,
                                                                                                   currCommand,
                                                                                                   *commandRuntimeData,
                                                                                                   environList,
                                                                                                   isSh);
				ExecuteInITerm( commandWithEnvSetup, currCommand.iTermShellPath, currCommand.openNewTerminalSession, currCommand.bringTerminalToFront);
			}
			break;

			default:
			case kExecSilentPOpen:
				theExec.Adopt( new POpenExecutor(currCommand, environList) );
			break;
			
			case kExecSilentSystem:
				theExec.Adopt( new SystemExecutor() );
			break;
			
			case kExecPOpenWithOutputWindow:
				theExec.Adopt( new POpenWithOutputExecutor(currCommand, dynamicCommandName, externBundle, environList) );
			break;
			
			case kExecAppleScript:
				theExec.Adopt( new AppleScriptExecutor(currCommand, nullptr /*inDynamicName*/, externBundle, false /*useOutputWindow*/) );
			break;
			
			case kExecAppleScriptWithOutputWindow:
				theExec.Adopt( new AppleScriptExecutor(currCommand, dynamicCommandName, externBundle, true /*useOutputWindow*/) );
			break;

			case kExecPopenScriptFile:
				theExec.Adopt( new POpenScriptFileExecutor(currCommand, externBundle, environList) );
			break;
			
			case kExecPopenScriptFileWithOutputWindow:
				theExec.Adopt( new POpenScriptFileWithOutputExecutor(currCommand, dynamicCommandName, externBundle, environList) );
			break;
		}
		
		if(theExec != nullptr)
        {
            taskManager->AddTask( theExec, commandRuntimeData, theCommand, inputPipe, objName );//retains theExec and runtime data
        }
        
        if(activeDialog != nullptr)
        {
            taskManager->AddObserver( activeDialog->GetObserver() );
        }
    }

	if(mObserver != nullptr)
    {
        taskManager->AddObserver( mObserver );
    }
    
	taskManager->Start();

	return noErr;
}


OSStatus
OnMyCommandCM::ExecuteCommandWithText(CommandDescription &currCommand, CFStringRef inStrRef, CommandRuntimeData *commandRuntimeData)
{
    assert(commandRuntimeData != nullptr);

	UInt8 escapingMode = currCommand.escapeSpecialCharsMode;
	UInt8 executionMode = currCommand.executionMode;

	if(currCommand.debugging)
	{ //when in debuggging mode, change silent executions to executions with output windows
		if(executionMode == kExecSilentPOpen)
			executionMode = kExecPOpenWithOutputWindow;
		else if(executionMode == kExecPopenScriptFile)
			executionMode = kExecPopenScriptFileWithOutputWindow;
		else if(executionMode == kExecAppleScript)
			executionMode = kExecAppleScriptWithOutputWindow;
	}

	if((executionMode == kExecPopenScriptFile) ||
		(executionMode == kExecPopenScriptFileWithOutputWindow))
		escapingMode = kEscapeNone; //the command is actually a path and will not be interpeted by any shell

	CFBundleRef externBundle = GetCurrentCommandExternBundle();
	CFBundleRef localizationBundle = nullptr;
	if(currCommand.localizationTableName != nullptr)//client wants to be localized
	{
		localizationBundle = externBundle;
		if(localizationBundle == nullptr)
			localizationBundle = CFBundleGetMainBundle();
	}
    
    ARefCountedObj<OMCDialog> activeDialog;
    // is this command creating a new dialog?
    if(currCommand.nibDialog != nullptr)
    {
        //bring executing application to front. important when running within ShortcutsObserver
        //don't restore because for non-modal dialogs this would bring executing app behind along with the dialog
        StSwitchToFront switcher(false);
        
        activeDialog = RunCocoaDialog(this, commandRuntimeData);
        if(activeDialog == nullptr)
        {
            throw OSStatus(userCanceledErr);
        }
    }
    else
    { // is this a subcommand triggered from active dialog?
        activeDialog = OMCDialog::FindDialogByUUID(commandRuntimeData->GetAssociatedDialogUUID());
    }

    if(activeDialog != nullptr)
    {
        SelectionIterator* selIterator = activeDialog->GetSelectionIterator();
        activeDialog->CopyAllControlValues(currCommand.specialRequestedNibControls, selIterator);
    }

	CFObj<CFMutableStringRef> theCommand( CreateCommandStringWithText(currCommand.command, inStrRef, *commandRuntimeData, escapingMode) );
	CFObj<CFMutableStringRef> inputPipe( CreateCommandStringWithText(currCommand.inputPipe, inStrRef, *commandRuntimeData, kEscapeNone) );
	CFObj<CFDictionaryRef> environList( CreateEnvironmentVariablesDict(inStrRef, *commandRuntimeData) );

	CFObj<CFStringRef> dynamicCommandName( CreateDynamicCommandName(currCommand,
                                                                    *commandRuntimeData,
                                                                    currCommand.localizationTableName,
                                                                    localizationBundle) );
	CFObj<CFStringRef> objName; //what should the object name be for text?

	CFIndex maxTaskCount = 1;//text command processes one task anyway
	OmcHostTaskManager *taskManager = new OmcHostTaskManager( this, currCommand, dynamicCommandName, mBundleRef, maxTaskCount );

	ARefCountedObj<OmcExecutor> theExec;

	switch(executionMode)
	{
		case kExecTerminal:
		{
			bool isSh = IsShDefaultInTerminal();
			CFObj<CFStringRef> commandWithEnvSetup = CreateTerminalCommandWithEnvironmentSetup(theCommand,
                                                                                               currCommand,
                                                                                               *commandRuntimeData,
                                                                                               environList,
                                                                                               isSh);
			ExecuteInTerminal( commandWithEnvSetup, currCommand.openNewTerminalSession, currCommand.bringTerminalToFront );
		}
		break;
		
		case kExecITerm:
		{
			bool isSh = IsShDefaultInITem();
			CFObj<CFStringRef> commandWithEnvSetup = CreateTerminalCommandWithEnvironmentSetup(theCommand,
                                                                                               currCommand,
                                                                                               *commandRuntimeData,
                                                                                               environList,
                                                                                               isSh);
			ExecuteInITerm( commandWithEnvSetup, currCommand.iTermShellPath, currCommand.openNewTerminalSession, currCommand.bringTerminalToFront );
		}
		break;

		default:
		case kExecSilentPOpen:
			theExec.Adopt( new POpenExecutor(currCommand, environList) );
		break;
		
		case kExecSilentSystem:
			theExec.Adopt( new SystemExecutor() );
		break;
		
		case kExecPOpenWithOutputWindow:
			theExec.Adopt( new POpenWithOutputExecutor(currCommand, dynamicCommandName, externBundle, environList) );
		break;

		case kExecAppleScript:
			theExec.Adopt( new AppleScriptExecutor(currCommand, nullptr /*inDynamicName*/, externBundle, false /*useOutputWindow*/) );
		break;
		
		case kExecAppleScriptWithOutputWindow:
			theExec.Adopt( new AppleScriptExecutor(currCommand, dynamicCommandName, externBundle, true /*useOutputWindow*/) );
		break;

		case kExecPopenScriptFile:
			theExec.Adopt( new POpenScriptFileExecutor(currCommand, externBundle, environList) );
		break;
		
		case kExecPopenScriptFileWithOutputWindow:
			theExec.Adopt( new POpenScriptFileWithOutputExecutor(currCommand, dynamicCommandName, externBundle, environList) );
		break;
	}
	
	if(theExec != nullptr)
		taskManager->AddTask( theExec, commandRuntimeData, theCommand, inputPipe, objName );//retains theExec

	if(activeDialog != nullptr)
		taskManager->AddObserver( activeDialog->GetObserver() );

	if(mObserver != nullptr)
		taskManager->AddObserver( mObserver );

	taskManager->Start();

	return noErr;
}


#pragma mark -

//true - OK to proceed
//false - do not execute

//there are 2 levels for execute & cancel buttons strings:
//1. defined in command itself
//2. if still null, get localized default

Boolean
OnMyCommandCM::DisplayWarning(CommandDescription &currCommand, CommandRuntimeData &commandRuntimeData)
{
	if(currCommand.warningStr == NULL)
		return true;

	CFIndex	theLen = ::CFStringGetLength(currCommand.warningStr);
	if(theLen == 0)
		return true;
	
	CFBundleRef localizationBundle = NULL;
	CFObj<CFStringRef> warningStr( currCommand.warningStr, kCFObjRetain);
	if(currCommand.localizationTableName != NULL)//client wants to be localized
	{
		localizationBundle = GetCurrentCommandExternBundle();
		if(localizationBundle == NULL)
			localizationBundle = CFBundleGetMainBundle();
		warningStr.Adopt(::CFCopyLocalizedStringFromTableInBundle( currCommand.warningStr, currCommand.localizationTableName, localizationBundle, ""));
	}

	CFIndex execLen = 0;
	CFIndex cancelLen = 0;
	if(currCommand.warningExecuteStr != NULL)
	{
		execLen = ::CFStringGetLength(currCommand.warningExecuteStr);
		if(execLen == 0)
		{
			::CFRelease(currCommand.warningExecuteStr);
			currCommand.warningExecuteStr = NULL;
		}
	}

	if(currCommand.warningCancelStr != NULL)
	{
		cancelLen = ::CFStringGetLength(currCommand.warningCancelStr);
		if(cancelLen == 0)
		{
			::CFRelease(currCommand.warningCancelStr);
			currCommand.warningCancelStr = NULL;
		}
	}
	
	CFObj<CFStringRef> warningExecuteStr( currCommand.warningExecuteStr, kCFObjRetain );
	if(currCommand.warningExecuteStr == NULL)
		warningExecuteStr.Adopt( ::CFCopyLocalizedStringFromTableInBundle( CFSTR("Execute"), CFSTR("Private"), mBundleRef, "") );
	else if(currCommand.localizationTableName != NULL)//client wants to be localized
		warningExecuteStr.Adopt( ::CFCopyLocalizedStringFromTableInBundle( currCommand.warningExecuteStr, currCommand.localizationTableName, localizationBundle, "") );

	CFObj<CFStringRef> warningCancelStr( currCommand.warningCancelStr, kCFObjRetain );
	if(currCommand.warningCancelStr == NULL)
		warningCancelStr.Adopt( ::CFCopyLocalizedStringFromTableInBundle( CFSTR("Cancel"), CFSTR("Private"), mBundleRef, "") );
	else if(currCommand.localizationTableName != NULL)//client wants to be localized
		warningCancelStr.Adopt( ::CFCopyLocalizedStringFromTableInBundle( warningCancelStr, currCommand.localizationTableName, localizationBundle, "") );
	
	CFObj<CFStringRef> dynamicCommandName( CreateDynamicCommandName(currCommand,
                                                                    commandRuntimeData,
                                                                    currCommand.localizationTableName,
                                                                    localizationBundle) );
	if(dynamicCommandName == NULL)
		dynamicCommandName.Adopt(CFSTR("Warning"), kCFObjRetain);

	CFOptionFlags responseFlags = 0;
	/*SInt32 isSuccessfull = */(void)CFUserNotificationDisplayAlert (
										0.0, //timeout
										kCFUserNotificationCautionAlertLevel,
										NULL, //iconURL
										NULL, //soundURL
										NULL, //localizationURL
										dynamicCommandName, //alertHeader
										warningStr,
										warningExecuteStr,
										warningCancelStr,
										NULL, //otherButtonTitle,
										&responseFlags );
	
	if( (responseFlags & 0x03) == kCFUserNotificationDefaultResponse )//OK button
		return true;

	return false;
}

Boolean
DisplayVersionWarning(CFBundleRef inBundleRef, CFStringRef dynamicCommandName, CFStringRef inString, SInt32 requiredVersion, SInt32 currVersion)
{
	CFObj<CFStringRef> tryButtName( ::CFCopyLocalizedStringFromTableInBundle( CFSTR("Try Anyway"), CFSTR("Private"), inBundleRef, "") );

	CFObj<CFStringRef> cancelButtName( ::CFCopyLocalizedStringFromTableInBundle( CFSTR("Cancel"), CFSTR("Private"), inBundleRef, "") );

	CFObj<CFStringRef> requiredVersionStr( CreateVersionString(requiredVersion) );
	CFObj<CFStringRef> currVersionStr( CreateVersionString(currVersion) );

	CFObj<CFStringRef> warningText( ::CFStringCreateWithFormat(kCFAllocatorDefault, NULL, inString, (CFStringRef)requiredVersionStr, (CFStringRef)currVersionStr) );
	if(warningText == NULL)
		return false;

	if(dynamicCommandName == NULL)
		dynamicCommandName = CFSTR("Version Warning");
	
	CFOptionFlags responseFlags = 0;
	/*SInt32 isSuccessfull = */(void)CFUserNotificationDisplayAlert (
										0.0, //timeout
										kCFUserNotificationCautionAlertLevel,
										NULL, //iconURL
										NULL, //soundURL
										NULL, //localizationURL
										dynamicCommandName, //alertHeader
										warningText,
										tryButtName,
										cancelButtName,
										NULL, //otherButtonTitle,
										&responseFlags );
	
	if( (responseFlags & 0x03) == kCFUserNotificationDefaultResponse )// Execute/Go button
		return true;

	return false;
}

Boolean
DisplayAlert(CFBundleRef inBundleRef, CFStringRef dynamicCommandName, CFStringRef inAlertString, CFOptionFlags inAlertLevel /*= kCFUserNotificationStopAlertLevel*/ )
{
	CFObj<CFStringRef> alertString( ::CFCopyLocalizedStringFromTableInBundle( inAlertString, CFSTR("Private"), inBundleRef, "") );
	CFObj<CFStringRef> defaultButtName( ::CFCopyLocalizedStringFromTableInBundle( CFSTR("OK"), CFSTR("Private"), inBundleRef, "") );

	if(dynamicCommandName == NULL)
		dynamicCommandName = CFSTR("Error");

	CFOptionFlags responseFlags = 0;
	/*SInt32 isSuccessfull = */(void)CFUserNotificationDisplayAlert (
										0.0, //timeout
										inAlertLevel,
										NULL, //iconURL
										NULL, //soundURL
										NULL, //localizationURL
										dynamicCommandName, //alertHeader
										alertString,
										defaultButtName,
										NULL,
										NULL, //otherButtonTitle,
										&responseFlags );

	if( (responseFlags & 0x03) == kCFUserNotificationDefaultResponse )// Execute/Go button
		return true;

	return false;
}


UInt32 outFlags = kOmcCommandNoSpecialObjects;

OSStatus
OnMyCommandCM::GetCommandInfo(SInt32 inCommandRef, OMCInfoType infoType, void *outInfo)
{
//FindCommandIndex loads all commands

	SInt32 cmdIndex = -1;
	if(inCommandRef >= kCMCommandStart)
		cmdIndex = inCommandRef - kCMCommandStart;
	else
		return paramErr;

	if( (mCommandList == NULL) || (mCommandCount == 0) || (cmdIndex >= mCommandCount) )
		return -1;

	OSStatus err = noErr;
	CommandDescription &currCommand = mCommandList[cmdIndex];
	switch(infoType)
	{
		case kOmcInfo_CommandObjects:
		{
			PrescanCommandDescription( currCommand );
			UInt32 *outInfoData = (UInt32 *)outInfo;
			*outInfoData = currCommand.prescannedCommandInfo;
		}
		break;
		
		case kOmcInfo_ActivationType:
		{
			UInt32 *outInfoData = (UInt32 *)outInfo;
			*outInfoData = (UInt32)currCommand.activationMode;
		}	
		break;
			
		case kOmcInfo_ExecutionOptions:
		{
			UInt32 *outInfoData = (UInt32 *)outInfo;
			*outInfoData = (UInt32)currCommand.executionOptions;
		}
		break;

		default:
			err = paramErr;
		break;
	}
	return err;
}

#pragma mark -

//returns true if last command is active.
//makes sense if you have just one command and you want to check if it should be activated
//if we run in Shortcuts, runningInSpecialApp = true, inFrontAppName = NULL
//if we run in ShortcutsObserver, runningInSpecialApp = true, inFrontAppName != NULL

Boolean
OnMyCommandCM::PopulateItemsMenu( const AEDesc *inAEContext,
                                 CommandRuntimeData &commandRuntimeData,
                                 AEDescList* ioRootMenu,
                                 Boolean runningInSpecialApp,
                                 CFStringRef inFrontAppName)
{
	TRACE_CSTR("OnMyCommandCM. PopulateItemsMenu\n" );

	if( mCommandList == nullptr )
		return false;

//	OSStatus err = noErr;
	bool doActivate = false;
	CFStringRef submenuName = nullptr;
	
	SubmenuTree itemTree(ioRootMenu);
	
	CFStringRef rootMenuName = CFSTR("/");
	CFStringRef currAppName = mMyHostAppName;
	bool skipFinderWindowCheck = false;
	if(runningInSpecialApp)
	{
		currAppName = inFrontAppName;//currAppName != NULL: ShortcutObserver case, use front app
		if(currAppName == nullptr)//Shortcuts case - always show
			skipFinderWindowCheck = true;
	}
	
    OMCContextData &contextData = commandRuntimeData.GetContextData();
    
	for(UInt32 i = 0; i < mCommandCount; i++)
	{
		CommandDescription &currCommand = mCommandList[i];
		
		if( currCommand.isSubcommand ) //it is a subcommand, do not add to menu, main command is always 'top!'
			continue;

		doActivate = IsCommandEnabled(currCommand,
                                      contextData,
                                      inAEContext,
                                      currAppName,
                                      skipFinderWindowCheck);

		if(doActivate)
		{	
			CFObj<CFMutableStringRef> subPath;
			if(currCommand.submenuName == nullptr)
			{
				submenuName = rootMenuName;
			}
			else
			{
				submenuName = currCommand.submenuName;
				CFIndex subLen = ::CFStringGetLength(submenuName);
				UniChar firstChar = 0;
				if(subLen > 0)
					firstChar = ::CFStringGetCharacterAtIndex(submenuName, 0);
				
				//check for ".." which means root level
				if( firstChar == (UniChar)'.' )
				{
					CFIndex theLen = ::CFStringGetLength(submenuName);
					if( (theLen == 2) && (::CFStringGetCharacterAtIndex(submenuName, 1) == (UniChar)'.') )
					{
						submenuName = rootMenuName;
						firstChar = (UniChar)'/';
					}
				}
				else if(firstChar != (UniChar)'/')
				{
					CFMutableStringRef newName = ::CFStringCreateMutable( kCFAllocatorDefault, 0);
					if(newName != nullptr)
					{
						subPath.Adopt(newName);
						
						::CFStringAppend( newName, CFSTR("/") );
						::CFStringAppend( newName, submenuName );
						
						submenuName = newName;
					}
				}
			}
			
			//DEBUG_CSTR( "OMC->PopulateItemsMenu. About to call itemTree.AddMenuItem() for:\n" );
			//DEBUG_CFSTR(submenuName);

			//check if we need context text then load
			if( currCommand.nameIsDynamic )
			{
				ScanDynamicName( currCommand );
				if( currCommand.nameContainsDynamicText )
					CreateTextContext(currCommand, contextData, inAEContext);//load context text now
			}
			
			CFBundleRef localizationBundle = nullptr;
			if(currCommand.localizationTableName != nullptr)//client wants to be localized
			{
				localizationBundle = GetCurrentCommandExternBundle();
				if(localizationBundle == nullptr)
					localizationBundle = CFBundleGetMainBundle();
			}

			CFObj<CFStringRef> dynamicCommandName( CreateDynamicCommandName(currCommand,
                                                                            commandRuntimeData,
                                                                            currCommand.localizationTableName,
                                                                            localizationBundle) );
			itemTree.AddMenuItem(
								submenuName,
								dynamicCommandName,
								kCMCommandStart + i,
								0,
								kMenuNoModifiers);
		}
	}
	

//	DEBUG_CSTR( "OMC->PopulateItemsMenu. About to call itemTree.BuildSubmenuTree()\n" );
	itemTree.BuildSubmenuTree();
	
	return doActivate;
}

bool
OnMyCommandCM::IsCommandEnabled(CommandDescription &currCommand,
                                OMCContextData &contextData,
                                const AEDesc *inAEContext,
                                CFStringRef currAppName,
                                bool skipFinderWindowCheck)
{
	bool doActivate = false;
	bool appActivate = true;

	if( currCommand.disabled )
		return false;//disabled item

	if( (currCommand.appNames != NULL) && (currAppName != NULL) )
	{//we have a list of included or excluded names to check against
		//init to false if we want to activate only in listed apps (assuming we will not find a match)
		//or intit to true if this is the exlude list (again assuming we will not find a match)
		appActivate = !(currCommand.actOnlyInListedApps);
		
		ACFArr appNames(currCommand.appNames);
		CFIndex itemCount = appNames.GetCount();
		CFStringRef oneAppName;

		for(CFIndex j = 0; j < itemCount; j++)
		{
			if( appNames.GetValueAtIndex( j, oneAppName) )
			{
				if( kCFCompareEqualTo == ::CFStringCompare(currAppName, oneAppName, 0) )
				{//we have a match
					//the match means "activate" if this is the "include" list or it means deactivate if it is an "exclude" list
					appActivate = currCommand.actOnlyInListedApps;
					break;
				}
			}
		}
	}

	if( !appActivate )
		return false;//not showing in this app

//    OMCContextData &contextData = commandRuntimeData->GetContextData();
    
	//check the rest only if our host qualifies
	switch(currCommand.activationMode)
	{
		case kActiveAlways:
			doActivate = true;
		break;
		
		case kActiveFile:
		{
			doActivate = CheckAllObjects(contextData.objectList, CheckIfFile, NULL);
			
			if(doActivate)
			{
				Boolean needsFileTypeCheck = (( currCommand.activationTypes != NULL ) &&
										( currCommand.activationTypeCount != 0) );
				Boolean needsExtensionCheck = (currCommand.activationExtensions != NULL);
				if(needsExtensionCheck)
				{
					needsExtensionCheck = (::CFArrayGetCount(currCommand.activationExtensions) > 0);
				}

				if(needsFileTypeCheck && needsExtensionCheck)
				{
					doActivate = CheckAllObjects(contextData.objectList, CheckFileTypeOrExtension, &(currCommand));
				}
				else if(needsFileTypeCheck)
				{
					doActivate = CheckAllObjects(contextData.objectList, CheckFileType, &(currCommand));
				}
				else if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(contextData.objectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;
		
		case kActiveFolder:
		{
			doActivate = CheckAllObjects(contextData.objectList, CheckIfFolder, NULL);
		
			if(doActivate)
			{
				Boolean needsExtensionCheck = (currCommand.activationExtensions != NULL);
				if(needsExtensionCheck)
				{
					needsExtensionCheck = (::CFArrayGetCount(currCommand.activationExtensions) > 0);
				}
				if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(contextData.objectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;

		case kActiveFolderExcludeFinderWindow:
		{
			if(skipFinderWindowCheck)
				doActivate = true;
			else
				doActivate = !contextData.isOpenFolder;
			
			if(doActivate)
				doActivate = CheckAllObjects(contextData.objectList, CheckIfFolder, NULL);
		
			if(doActivate)
			{
				Boolean needsExtensionCheck = (currCommand.activationExtensions != NULL);
				if(needsExtensionCheck)
				{
					needsExtensionCheck = (::CFArrayGetCount(currCommand.activationExtensions) > 0);
				}
				if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(contextData.objectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;
		
		case kActiveFileOrFolder:
		{
			doActivate = CheckAllObjects(contextData.objectList, CheckIfFileOrFolder, NULL);
			if(doActivate)
			{
				Boolean needsFileTypeCheck = (( currCommand.activationTypes != NULL ) &&
										( currCommand.activationTypeCount != 0) );
				Boolean needsExtensionCheck = (currCommand.activationExtensions != NULL);
				if(needsExtensionCheck)
				{
					needsExtensionCheck = (::CFArrayGetCount(currCommand.activationExtensions) > 0);
				}

				if(needsFileTypeCheck && needsExtensionCheck)
				{
					doActivate = CheckAllObjects(contextData.objectList, CheckFileTypeOrExtension, &(currCommand));
				}
				else if(needsFileTypeCheck)
				{
					doActivate = CheckAllObjects(contextData.objectList, CheckFileType, &(currCommand));
				}
				else if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(contextData.objectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;
		
		
		case kActiveFileOrFolderExcludeFinderWindow:
		{
			if(skipFinderWindowCheck)
				doActivate = true;
			else
				doActivate = !contextData.isOpenFolder;
			
			if(doActivate)
				doActivate = CheckAllObjects(contextData.objectList, CheckIfFileOrFolder, NULL);

			if(doActivate)
			{
				Boolean needsFileTypeCheck = (( currCommand.activationTypes != NULL ) &&
										( currCommand.activationTypeCount != 0) );
				Boolean needsExtensionCheck = (currCommand.activationExtensions != NULL);
				if(needsExtensionCheck)
				{
					needsExtensionCheck = (::CFArrayGetCount(currCommand.activationExtensions) > 0);
				}

				if(needsFileTypeCheck && needsExtensionCheck)
				{
					doActivate = CheckAllObjects(contextData.objectList, CheckFileTypeOrExtension, &(currCommand));
				}
				else if(needsFileTypeCheck)
				{
					doActivate = CheckAllObjects(contextData.objectList, CheckFileType, &(currCommand));
				}
				else if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(contextData.objectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;

		case kActiveFinderWindow:
		{
			if(skipFinderWindowCheck)
				doActivate = true;
			else
				doActivate = contextData.isOpenFolder;

			if(doActivate)
			{
				Boolean needsExtensionCheck = (currCommand.activationExtensions != NULL);
				if(needsExtensionCheck)
				{
					needsExtensionCheck = (::CFArrayGetCount(currCommand.activationExtensions) > 0);
				}
				if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(contextData.objectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;
		
		case kActiveSelectedText:
			doActivate = contextData.isTextContext;
		break;

		case kActiveClipboardText:
			doActivate = contextData.isTextInClipboard;
		break;
		
		case kActiveSelectedOrClipboardText:
			doActivate = (contextData.isTextContext || contextData.isTextInClipboard);
		break;
	}
		
	if(doActivate && (currCommand.contextMatchString != NULL) )
	{
		if(contextData.objectList.size() > 0)
		{//path or name matching requested
			switch(currCommand.matchFileOptions)
			{
				case kMatchFileName:
					doActivate = CheckAllObjects(contextData.objectList, CheckFileNameMatch, &(currCommand));
				break;
				
				case kMatchFilePath:
					doActivate = CheckAllObjects(contextData.objectList, CheckFilePathMatch, &(currCommand));
				break;
			}
		}
		else if( (contextData.isTextContext || contextData.isTextInClipboard) )
		{//text matching requested
			CreateTextContext(currCommand, contextData, inAEContext);//load context text now
			doActivate = DoStringsMatch(currCommand.contextMatchString, contextData.contextText, currCommand.matchMethod, (CFStringCompareFlags)currCommand.matchCompareOptions );
		}
	}
	return doActivate;
}

bool
OnMyCommandCM::IsCommandEnabled(SInt32 inCmdIndex,
                                const AEDesc *inAEContext,
                                OMCContextData &contextData,
                                bool runningInSpecialApp,
                                CFStringRef inFrontAppName)
{
	if( (mCommandList == NULL) || (inCmdIndex < 0) || (inCmdIndex >= mCommandCount) )
		return false;

	CFStringRef currAppName = mMyHostAppName;
	bool skipFinderWindowCheck = false;
	if( runningInSpecialApp )
	{
		currAppName = inFrontAppName;//currAppName != NULL: ShortcutObserver case, use front app
		if(currAppName == NULL)//Shortcuts case - always show
			skipFinderWindowCheck = true;
	}

	CommandDescription &currCommand = mCommandList[inCmdIndex];
	return IsCommandEnabled(currCommand,
                            contextData,
                            inAEContext,
                            currAppName,
                            skipFinderWindowCheck);
}

inline Boolean
DoStringsMatch(CFStringRef inMatchString, CFStringRef inSearchedString, UInt8 matchMethod, CFStringCompareFlags compareOptions )
{
	if( (inMatchString == NULL) || (inSearchedString == NULL) )
		return false;

	switch(matchMethod)
	{
		case kMatchExact:
		{
			CFComparisonResult result = ::CFStringCompare(inSearchedString, inMatchString, compareOptions);
			return (result == kCFCompareEqualTo);
		}
		break;
		
		case kMatchContains:
		{
			CFRange foundRange = ::CFStringFind(inSearchedString, inMatchString, compareOptions);
			return (foundRange.location != kCFNotFound) && (foundRange.length > 0);
		}
		break;
		
		case kMatchRegularExpression:
		{
			regex_t regular_expression;
			std::string matchString = CMUtils::CreateUTF8StringFromCFString(inMatchString);
			if(matchString.size() == 0)
				return false;

			int regFlags = REG_EXTENDED | REG_NOSUB;
			if( (compareOptions & kCFCompareCaseInsensitive) != 0)
				regFlags |= REG_ICASE;

			if( ::regcomp(&regular_expression, matchString.c_str(), regFlags) == 0)
			{
				int result = -1;
				std::string searchedString = CMUtils::CreateUTF8StringFromCFString(inSearchedString);
				if(searchedString.size() > 0)
					result = ::regexec( &regular_expression, searchedString.c_str(), 0, NULL, 0);

				::regfree(&regular_expression);
				return (result == 0);
			}
			else
			{
				LOG_CSTR( "OMC->DoStringsMatch: regular expression compilation failed. Syntax error?\n" );
			}
		}
		break;
	}
	return false;
}

#pragma mark -

CFURLRef
CopyOMCPrefsURL()
{
	CFObj<CFURLRef> prefsFolderURL( CopyPreferencesDirURL() );
	if(prefsFolderURL == NULL)
		return NULL;
	
	return ::CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, prefsFolderURL, CFSTR("com.abracode.OnMyCommandCMPrefs.plist"), false /*isDirectory*/);
}

void
OnMyCommandCM::ReadPreferences()
{
	TRACE_CSTR("OnMyCommandCM. ReadPreferences\n" );

	//load prefs directly by reading from URL, bypassing the CFPreferences
	//Looks like agressive caching of CFPreferences (or a bug there) prevents us from seeing new changes saved in OMCEdit
	CFObj<CFURLRef> prefsURL( CopyOMCPrefsURL() );
	LoadCommandsFromPlistFile( prefsURL );
}

void
OnMyCommandCM::LoadCommandsFromPlistFile(CFURLRef inPlistFileURL)
{
	if( mCommandList != NULL )
	{
		DeleteCommandList();
	}

	mCommandCount = 0;
	
	if(inPlistFileURL == NULL)
		return;

	CFObj<CFPropertyListRef> thePlist( CreatePropertyList(inPlistFileURL, kCFPropertyListImmutable) );
	LoadCommandsFromPlistRef(thePlist);
}


void
OnMyCommandCM::LoadCommandsFromPlistRef(CFPropertyListRef inPlistRef)
{
	if( mCommandList != NULL )
	{
		DeleteCommandList();
	}

	mCommandCount = 0;

	CFDictionaryRef plistDict = ACFType<CFDictionaryRef>::DynamicCast(inPlistRef);
	if(plistDict == NULL)
		return;

	ACFDict properties(plistDict);

	CFIndex verNum = 2;
	properties.GetValue(CFSTR("VERSION"), verNum);
	if(verNum != 2)
		return;

	CFArrayRef commandArrayRef;
	if( !properties.GetValue(CFSTR("COMMAND_LIST"), commandArrayRef) )
		return;

	ParseCommandList(commandArrayRef);
}


Boolean
OnMyCommandCM::IsSubcommand(CFArrayRef inName, CFIndex inCommandIndex)
{
	if((inName == NULL) || (mCommandList == NULL))
		return false;

	for(CFIndex i = inCommandIndex-1; i >= 0; i--)
	{
		if( (mCommandList[i].name != NULL) && ::CFEqual(inName, mCommandList[i].name) /*&&
			((mCommandList[i].commandID == 'top!') || (mCommandList[i].isSubcommand))*/ )
		{//if I find a command with the same name before me, I am the subcommand
			return true;
		}
	}

	for(CFIndex i = inCommandIndex+1; i < (CFIndex)mCommandCount; i++)
	{
		if( (mCommandList[i].name != NULL) && ::CFEqual(inName, mCommandList[i].name) &&
			((mCommandList[i].commandID != NULL) && ::CFEqual(mCommandList[i].commandID, kOMCTopCommandID) ) )
		{//we look forward to top command with the same name, otherwise we cannot declare this command a subcommand
			return true;
		}
	}
	
	return false;
}

void
OnMyCommandCM::ParseCommandList(CFArrayRef commandArrayRef)
{
	if(commandArrayRef == NULL)
		return;

	ACFArr commands(commandArrayRef);
	CFIndex theCount = commands.GetCount();
	if(theCount == 0)
		return;

	mCommandList = new CommandDescription[theCount];
    assert(theCount <= UINT_MAX);
	mCommandCount = (UInt32)theCount;
	
	CFDictionaryRef theDict;
	
	for( CFIndex i = 0; i < theCount; i++ )
	{
		if( commands.GetValueAtIndex( i, theDict ) )
		{
			GetOneCommandParams( mCommandList[i], theDict, mExternBundleOverrideURL );
		}
		else
		{
			LOG_CSTR( "OnMyCommandCM. ParseCommandList: wrong array item: null or not dict\n" );
		}
	}

	//mark subcommands
	for( CFIndex i = 0; i < theCount; i++ )
	{
		if( (mCommandList[i].commandID != NULL) && ! ::CFEqual(mCommandList[i].commandID, kOMCTopCommandID) )
			mCommandList[i].isSubcommand = IsSubcommand(mCommandList[i].name, i);
	}
}


CFMutableStringRef
OnMyCommandCM::CreateCommandStringWithObjects(CFArrayRef inFragments,
                                              CommandRuntimeData &commandRuntimeData,
                                              UInt16 escSpecialCharsMode)
{
    OMCContextData &contextData = commandRuntimeData.GetContextData();
	if( (inFragments == nullptr) || (mCommandList == nullptr) || (mCommandCount == 0) || (contextData.objectList.size() == 0) || (mCurrCommandIndex >= mCommandCount) )
		return nullptr;

	CFMutableStringRef theCommand = CFStringCreateMutable(kCFAllocatorDefault, 0);
	if(theCommand == nullptr)
		return nullptr;

	CommandDescription &currCommand = GetCurrentCommand();

	ARefCountedObj<OMCDialog> activeDialog;
    activeDialog = OMCDialog::FindDialogByUUID(commandRuntimeData.GetAssociatedDialogUUID());

//	TRACE_CSTR("OnMyCommandCM. CreateCommandStringWithObjects\n" );

	if(currCommand.sortMethod == kSortMethodByName)
	{
		SortObjectListByName(contextData, (CFOptionFlags)currCommand.sortOptions, (bool)currCommand.sortAscending);
	}

	if( ((currCommand.prescannedCommandInfo & kOmcCommandContainsTextObject) != 0) && (contextData.clipboardText == nullptr) )
	{
        contextData.clipboardText.Adopt( CMUtils::CreateCFStringFromClipboardText(currCommand.textReplaceOptions), kCFObjDontRetain );
	}

	ACFArr fragments(inFragments);
	CFIndex theCount = fragments.GetCount();
	for(CFIndex i = 0; i < theCount; i++ )
	{
		CFStringRef fragmentRef = nullptr;
		if(fragments.GetValueAtIndex(i, fragmentRef))
		{
			AppendTextToCommand(theCommand, fragmentRef,
                                contextData.objectList.data(), contextData.objectList.size(), contextData.currObjectIndex,
                                contextData.clipboardText, currCommand,
                                commandRuntimeData, activeDialog,
								currCommand.mulObjSeparator, currCommand.mulObjPrefix, currCommand.mulObjSuffix,
								escSpecialCharsMode );
		}
	}
	
	return theCommand;
}

//normally command is not localized but this API is used to create dynamic comamnd name, which might be localized
CFMutableStringRef
OnMyCommandCM::CreateCommandStringWithText(CFArrayRef inFragments,
                                           CFStringRef inObjTextRef,
                                           CommandRuntimeData &commandRuntimeData,
                                           UInt16 escSpecialCharsMode,
											CFStringRef inLocTableName /*= NULL*/,
                                           CFBundleRef inLocBundleRef /*= NULL*/)
{
	if( (inFragments == nullptr) || (mCommandList == nullptr) || (mCommandCount == 0) || (mCurrCommandIndex >= mCommandCount) )
		return NULL;

	CFMutableStringRef theCommand = ::CFStringCreateMutable( kCFAllocatorDefault, 0 );
	if(theCommand == nullptr)
		return nullptr;

	CommandDescription &currCommand = GetCurrentCommand();
	ARefCountedObj<OMCDialog> activeDialog = OMCDialog::FindDialogByUUID(commandRuntimeData.GetAssociatedDialogUUID());

	ACFArr fragments(inFragments);
	CFIndex theCount = fragments.GetCount();

	for(CFIndex i = 0; i < theCount; i++ )
	{
		CFStringRef fragmentRef = nullptr;
		if( fragments.GetValueAtIndex(i, fragmentRef) )
		{
			AppendTextToCommand(theCommand, fragmentRef,
								nullptr, 0, -1,
								inObjTextRef, currCommand,
                                commandRuntimeData, activeDialog,
								nullptr, nullptr, nullptr,
								escSpecialCharsMode,
								inLocTableName, inLocBundleRef );
		}
	}
	
	return theCommand;
}

CFDictionaryRef
OnMyCommandCM::CreateEnvironmentVariablesDict(CFStringRef inObjTextRef, CommandRuntimeData &commandRuntimeData)
{
	CommandDescription &currCommand = GetCurrentCommand();

	if( currCommand.customEnvironVariables == nullptr )
		return nullptr;

	//mutable copy
	CFObj<CFMutableDictionaryRef> outEnviron( ::CFDictionaryCreateMutableCopy( kCFAllocatorDefault,
													::CFDictionaryGetCount(currCommand.customEnvironVariables),
													currCommand.customEnvironVariables) );

    OMCContextData &contextData = commandRuntimeData.GetContextData();
    if(contextData.objectList.size() > 0)
	{
		if(currCommand.sortMethod == kSortMethodByName)
		{
			SortObjectListByName(contextData, (CFOptionFlags)currCommand.sortOptions, (bool)currCommand.sortAscending);
		}

		if( ((currCommand.prescannedCommandInfo & kOmcCommandContainsTextObject) != 0) && (contextData.clipboardText == NULL) )
		{
            contextData.clipboardText.Adopt( CMUtils::CreateCFStringFromClipboardText(currCommand.textReplaceOptions), kCFObjDontRetain );
		}

		PopulateEnvironList( outEnviron, commandRuntimeData,
                            contextData.objectList.data(), contextData.objectList.size(), contextData.currObjectIndex,
                            contextData.clipboardText, currCommand,
							currCommand.mulObjSeparator, currCommand.mulObjPrefix, currCommand.mulObjSuffix);
	
	}
	else //if(inObjTextRef != NULL)
	{
		PopulateEnvironList( outEnviron, commandRuntimeData,
					nullptr, 0, -1,
					inObjTextRef, currCommand,
					nullptr, nullptr, nullptr);
	}

	return outEnviron.Detach();
}

CFMutableStringRef
OnMyCommandCM::CreateCombinedStringWithObjects(CFArrayRef inArray,
                                               CommandRuntimeData &commandRuntimeData,
                                               CFStringRef inLocTableName,
                                               CFBundleRef inLocBundleRef)
{
//	TRACE_CSTR("OnMyCommandCM. beginning of CreateCombinedStringWithObject\n" );

//this may be called without object too
//	if( mContextData.objectList == NULL )
//		return NULL;

	if(inArray == nullptr)
		return nullptr;

	ACFArr objects(inArray);
	CFIndex theCount = objects.GetCount();
	if(theCount == 0)
		return nullptr;

	CommandDescription &currCommand = GetCurrentCommand();
    OMCContextData &contextData = commandRuntimeData.GetContextData();

	ARefCountedObj<OMCDialog> activeDialog = OMCDialog::FindDialogByUUID(commandRuntimeData.GetAssociatedDialogUUID());
    
	CFMutableStringRef thePath = CFStringCreateMutable(kCFAllocatorDefault, 0);
	if(thePath == nullptr)
		return nullptr;

	for(CFIndex i = 0; i < theCount; i++ )
	{
		CFStringRef fragmentRef = nullptr;
		if( objects.GetValueAtIndex(i, fragmentRef) )
		{
			AppendTextToCommand(thePath, fragmentRef,
                                contextData.objectList.data(), contextData.objectList.size(), contextData.currObjectIndex,
								nullptr, currCommand,
                                commandRuntimeData, activeDialog,
								nullptr, nullptr, nullptr,
								kEscapeNone,
								inLocTableName, inLocBundleRef );
		}
	}
	
	return thePath;
}



void
OnMyCommandCM::AppendTextToCommand(CFMutableStringRef inCommandRef, CFStringRef inStrRef,
					OneObjProperties *inObjList, CFIndex inObjCount, CFIndex inCurrIndex,
					CFStringRef inObjTextRef, CommandDescription &currCommand,
                    CommandRuntimeData &commandRuntimeData, OMCDialog *activeDialog,
					CFStringRef inMultiSeparator, CFStringRef inMultiPrefix, CFStringRef inMultiSuffix,
					UInt16 escSpecialCharsMode, CFStringRef inLocTableName /*=nullptr*/, CFBundleRef inLocBundleRef/*=nullptr*/)
{
    OMCContextData &contextData = commandRuntimeData.GetContextData();
    
	CFStringRef newStrRef = NULL;
	CFObj<CFStringRef> newDel;
	bool releaseNewString = true;

	SpecialWordID specialWordID = GetSpecialWordID(inStrRef);

	switch(specialWordID)
	{
		case NO_SPECIAL_WORD:
		{
			newStrRef = inStrRef;//we do not own inStrRef so our deleter does not adopt it
			releaseNewString = false;
			if( (inStrRef != NULL) && (inLocTableName != NULL) && (inLocBundleRef != NULL) )//client wants us to localize text
			{
				newStrRef = ::CFCopyLocalizedStringFromTableInBundle( inStrRef, inLocTableName, inLocBundleRef, "");
				releaseNewString = true;
			}
		}
		break;
				
		case OBJ_TEXT:
			if(inObjTextRef != NULL)
				newStrRef = CreateEscapedStringCopy(inObjTextRef, escSpecialCharsMode);//we do not own inObjTextRef so we should never delete it
		break;
		
		case OBJ_PATH:
			newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
											CreateObjPath, NULL,
											inMultiSeparator, inMultiPrefix, inMultiSuffix,
											escSpecialCharsMode );
		break;
		
		case OBJ_PATH_NO_EXTENSION:
			newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
											CreateObjPathNoExtension, NULL,
											inMultiSeparator, inMultiPrefix, inMultiSuffix,
											escSpecialCharsMode );
		break;
		
		case OBJ_PARENT_PATH:
			newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
											CreateParentPath, NULL,
											inMultiSeparator, inMultiPrefix, inMultiSuffix,
											escSpecialCharsMode );
		break;
		
		case OBJ_NAME:
			newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
											CreateObjName, NULL,
											inMultiSeparator, inMultiPrefix, inMultiSuffix,
											escSpecialCharsMode );
		break;

		case OBJ_NAME_NO_EXTENSION:
			newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
											CreateObjNameNoExtension, NULL,
											inMultiSeparator, inMultiPrefix, inMultiSuffix,
											escSpecialCharsMode );
		break;
		
		case OBJ_EXTENSION_ONLY:
			newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
											CreateObjExtensionOnly, NULL,
											inMultiSeparator, inMultiPrefix, inMultiSuffix,
											escSpecialCharsMode );
		break;
		
		case OBJ_DISPLAY_NAME:
			newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
											CreateObjDisplayName, nullptr,
											inMultiSeparator, inMultiPrefix, inMultiSuffix,
											escSpecialCharsMode );
		break;
		
		case OBJ_COMMON_PARENT_PATH:
			if(commandRuntimeData.cachedCommonParentPath == nullptr)
            {
                commandRuntimeData.cachedCommonParentPath.Adopt( CreateCommonParentPath(inObjList, inObjCount), kCFObjDontRetain );
            }
	
			newStrRef = CreateEscapedStringCopy(commandRuntimeData.cachedCommonParentPath, escSpecialCharsMode);
		break;
		
		case OBJ_PATH_RELATIVE_TO_COMMON_PARENT:
			if(commandRuntimeData.cachedCommonParentPath == nullptr)
            {
                commandRuntimeData.cachedCommonParentPath.Adopt( CreateCommonParentPath(inObjList, inObjCount), kCFObjDontRetain );
            }
		
		
			newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
											CreateObjPathRelativeToBase, (void *)(CFStringRef)commandRuntimeData.cachedCommonParentPath,
											inMultiSeparator, inMultiPrefix, inMultiSuffix,
											escSpecialCharsMode );
		break;
		
		case DLG_INPUT_TEXT:
			newStrRef = CreateEscapedStringCopy(commandRuntimeData.inputText, escSpecialCharsMode);
		break;

		case DLG_SAVE_AS_PATH:
			newStrRef = CreatePathFromCFURL(contextData.saveAsPath, escSpecialCharsMode);
		break;
		
		case DLG_SAVE_AS_PARENT_PATH:
			newStrRef = CreateParentPathFromCFURL(contextData.saveAsPath, escSpecialCharsMode);
		break;
		
		case DLG_SAVE_AS_NAME:
			newStrRef = CreateNameFromCFURL(contextData.saveAsPath, escSpecialCharsMode);
		break;
		
		case DLG_SAVE_AS_NAME_NO_EXTENSION:
			newStrRef = CreateNameNoExtensionFromCFURL(contextData.saveAsPath, escSpecialCharsMode);
		break;
		
		case DLG_SAVE_AS_EXTENSION_ONLY:
			newStrRef = CreateExtensionOnlyFromCFURL(contextData.saveAsPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FILE_PATH:
			newStrRef = CreatePathFromCFURL(contextData.chooseFilePath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FILE_PARENT_PATH:
			newStrRef = CreateParentPathFromCFURL(contextData.chooseFilePath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FILE_NAME:
			newStrRef = CreateNameFromCFURL(contextData.chooseFilePath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FILE_NAME_NO_EXTENSION:
			newStrRef = CreateNameNoExtensionFromCFURL(contextData.chooseFilePath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FILE_EXTENSION_ONLY:
			newStrRef = CreateExtensionOnlyFromCFURL(contextData.chooseFilePath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FOLDER_PATH:
			newStrRef = CreatePathFromCFURL(contextData.chooseFolderPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FOLDER_PARENT_PATH:
			newStrRef = CreateParentPathFromCFURL(contextData.chooseFolderPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FOLDER_NAME:
			newStrRef = CreateNameFromCFURL(contextData.chooseFolderPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION:
			newStrRef = CreateNameNoExtensionFromCFURL(contextData.chooseFolderPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FOLDER_EXTENSION_ONLY:
			newStrRef = CreateExtensionOnlyFromCFURL(contextData.chooseFolderPath, escSpecialCharsMode);
		break;

		case DLG_CHOOSE_OBJECT_PATH:
			newStrRef = CreatePathFromCFURL(contextData.chooseObjectPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_OBJECT_PARENT_PATH:
			newStrRef = CreateParentPathFromCFURL(contextData.chooseObjectPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_OBJECT_NAME:
			newStrRef = CreateNameFromCFURL(contextData.chooseObjectPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION:
			newStrRef = CreateNameNoExtensionFromCFURL(contextData.chooseObjectPath, escSpecialCharsMode);
		break;

		case DLG_CHOOSE_OBJECT_EXTENSION_ONLY:
			newStrRef = CreateExtensionOnlyFromCFURL(contextData.chooseObjectPath, escSpecialCharsMode);
		break;

		case DLG_PASSWORD:
			newStrRef = CreateEscapedStringCopy(commandRuntimeData.inputText, escSpecialCharsMode);
		break;
		
		// this is deprecated. Abracode.framework paths as below are preferred since version 2.0
		case MY_BUNDLE_PATH:
		{
			if(mBundleRef != nullptr)
			{
				CFObj<CFURLRef> abracodeFrameworkPath( ::CFBundleCopyBundleURL(mBundleRef) );
				newStrRef = CreatePathFromCFURL(abracodeFrameworkPath, escSpecialCharsMode);
			}
			else
			{
				LOG_CSTR( "OMC: MY_BUNDLE_PATH. bundle ref is NULL\n" );
			}
		}
		break;

		case OMC_RESOURCES_PATH:
			newStrRef = CreateEscapedStringCopy(mOmcResourcesPath, escSpecialCharsMode);
		break;
		
		case OMC_SUPPORT_PATH:
			newStrRef = CreateEscapedStringCopy(mOmcSupportPath, escSpecialCharsMode);
		break;
	
		case APP_BUNDLE_PATH:
		case MY_HOST_BUNDLE_PATH:
			newStrRef = CreateEscapedStringCopy(mMyHostBundlePath, escSpecialCharsMode);
		break;
		
		case MY_EXTERNAL_BUNDLE_PATH:
		{
			if(currCommand.externalBundlePath != nullptr)
			{
				newStrRef = CreateEscapedStringCopy(currCommand.externalBundlePath, escSpecialCharsMode);
			}
			else
			{
				CFObj<CFStringRef> externBundleStr( CreateDefaultExternBundleString(currCommand.name) );
				newStrRef = CreateEscapedStringCopy(externBundleStr, escSpecialCharsMode);
			}
		}
		break;

//no need to escape process id
		case FRONT_PROCESS_ID:
		{
			pid_t frontPID = 0;
			if((mHostApp == kOMCHostApp_ShortcutsObserver) && (mFrontProcessPID != 0))
				frontPID = mFrontProcessPID;
			else
				frontPID = GetFrontAppPID();

			newStrRef = CFStringCreateWithFormat( kCFAllocatorDefault, nullptr, CFSTR("%d"), frontPID );
		}
		break;
		
		case FRONT_APPLICATION_NAME:
		{
			CFObj<CFStringRef> frontAppStr;
			if((mHostApp == kOMCHostApp_ShortcutsObserver) && (mFrontProcessPID != 0))
				frontAppStr.Adopt(CopyAppNameForPID(mFrontProcessPID) );

			if(frontAppStr == nullptr)
				frontAppStr.Adopt(CopyFrontAppName());
			
			if(frontAppStr != nullptr)
				newStrRef = CreateEscapedStringCopy(frontAppStr, escSpecialCharsMode);
		}
		break;

		case NIB_DLG_CONTROL_VALUE:
		case NIB_TABLE_VALUE:
		case NIB_TABLE_ALL_ROWS:
		case NIB_WEB_VIEW_VALUE:
        {
            if(activeDialog != nullptr)
            {
                newStrRef = activeDialog->CreateNibControlValue(specialWordID, inStrRef, escSpecialCharsMode, false);
            }
		}
		break;
		
//no need to escape guid
		case NIB_DLG_GUID:
		{
            if(activeDialog != nullptr)
            {
                newStrRef = activeDialog->GetDialogUUID();
                releaseNewString = false;
            }
		}
		break;
		
		case CURRENT_COMMAND_GUID:
		{
            newStrRef = commandRuntimeData.GetCommandUUID();
            releaseNewString = false;
		}
		break;
	}

	if(newStrRef != NULL)
	{
		if(releaseNewString)
			newDel.Adopt(newStrRef);
		::CFStringAppend( inCommandRef, newStrRef );
	}
}


void
OnMyCommandCM::PopulateEnvironList(CFMutableDictionaryRef ioEnvironList, CommandRuntimeData &commandRuntimeData,
					OneObjProperties *inObjList, CFIndex inObjCount, CFIndex inCurrIndex,
					CFStringRef inObjTextRef, CommandDescription &currCommand,
					CFStringRef inMultiSeparator, CFStringRef inMultiPrefix, CFStringRef inMultiSuffix)
{
    OMCContextData &contextData = commandRuntimeData.GetContextData();
    
	CFIndex itemCount = ::CFDictionaryGetCount(ioEnvironList);
	std::vector<void *> keyList(itemCount);//OK to create empty container if itemCount == 0
	if(itemCount > 0)
	{
		CFDictionaryGetKeysAndValues(ioEnvironList, (const void **)keyList.data(), NULL);
	}
	
	ARefCountedObj<OMCDialog> activeDialog;
    activeDialog = OMCDialog::FindDialogByUUID(commandRuntimeData.GetAssociatedDialogUUID());

	for(CFIndex i = 0; i < itemCount; i++)
	{
		CFStringRef newStrRef = NULL;
		CFObj<CFStringRef> newDel;
		bool releaseNewString = true;

		CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[(size_t)i] );
		SpecialWordID specialWordID = GetSpecialEnvironWordID(theKey);

		switch(specialWordID)
		{
			case NO_SPECIAL_WORD:
				newStrRef = NULL;//we do not have special dynamic value, so don't set it in dict
			break;
					
			case OBJ_TEXT: //always exported
				newStrRef = inObjTextRef;
				releaseNewString = false;//we do not own inObjTextRef so we should never delete it
			break;
			
			case OBJ_PATH: //always exported
				newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
												CreateObjPath, NULL,
												inMultiSeparator, inMultiPrefix, inMultiSuffix,
												kEscapeNone );
			break;
			
			case OBJ_PATH_NO_EXTENSION:
				newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
												CreateObjPathNoExtension, NULL,
												inMultiSeparator, inMultiPrefix, inMultiSuffix,
												kEscapeNone );
			break;
			
			case OBJ_PARENT_PATH:
				newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
												CreateParentPath, NULL,
												inMultiSeparator, inMultiPrefix, inMultiSuffix,
												kEscapeNone );
			break;
			
			case OBJ_NAME:
				newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
												CreateObjName, NULL,
												inMultiSeparator, inMultiPrefix, inMultiSuffix,
												kEscapeNone );
			break;

			case OBJ_NAME_NO_EXTENSION:
				newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
												CreateObjNameNoExtension, NULL,
												inMultiSeparator, inMultiPrefix, inMultiSuffix,
												kEscapeNone );
			break;
			
			case OBJ_EXTENSION_ONLY:
				newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
												CreateObjExtensionOnly, NULL,
												inMultiSeparator, inMultiPrefix, inMultiSuffix,
												kEscapeNone );
			break;
			
			case OBJ_DISPLAY_NAME:
				newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
												CreateObjDisplayName, NULL,
												inMultiSeparator, inMultiPrefix, inMultiSuffix,
												kEscapeNone );
			break;
			
			case OBJ_COMMON_PARENT_PATH:
				if(commandRuntimeData.cachedCommonParentPath == nullptr)
                {
                    commandRuntimeData.cachedCommonParentPath.Adopt( CreateCommonParentPath(inObjList, inObjCount), kCFObjDontRetain );
                }
		
				newStrRef = commandRuntimeData.cachedCommonParentPath;
				releaseNewString = false;
			break;
			
			case OBJ_PATH_RELATIVE_TO_COMMON_PARENT:
				if(commandRuntimeData.cachedCommonParentPath == nullptr)
                {
                    commandRuntimeData.cachedCommonParentPath.Adopt( CreateCommonParentPath(inObjList, inObjCount), kCFObjDontRetain );
                }
                
				newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
												CreateObjPathRelativeToBase, (void *)(CFStringRef)commandRuntimeData.cachedCommonParentPath,
												inMultiSeparator, inMultiPrefix, inMultiSuffix,
												kEscapeNone );
			break;
			
			case DLG_INPUT_TEXT:
				newStrRef = commandRuntimeData.inputText.Get();
				releaseNewString = false;
			break;

			case DLG_SAVE_AS_PATH:
				newStrRef = CreatePathFromCFURL(contextData.saveAsPath, kEscapeNone);
			break;
			
			case DLG_SAVE_AS_PARENT_PATH:
				newStrRef = CreateParentPathFromCFURL(contextData.saveAsPath, kEscapeNone);
			break;
			
			case DLG_SAVE_AS_NAME:
				newStrRef = CreateNameFromCFURL(contextData.saveAsPath, kEscapeNone);
			break;
			
			case DLG_SAVE_AS_NAME_NO_EXTENSION:
				newStrRef = CreateNameNoExtensionFromCFURL(contextData.saveAsPath, kEscapeNone);
			break;
			
			case DLG_SAVE_AS_EXTENSION_ONLY:
				newStrRef = CreateExtensionOnlyFromCFURL(contextData.saveAsPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FILE_PATH:
				newStrRef = CreatePathFromCFURL(contextData.chooseFilePath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FILE_PARENT_PATH:
				newStrRef = CreateParentPathFromCFURL(contextData.chooseFilePath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FILE_NAME:
				newStrRef = CreateNameFromCFURL(contextData.chooseFilePath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FILE_NAME_NO_EXTENSION:
				newStrRef = CreateNameNoExtensionFromCFURL(contextData.chooseFilePath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FILE_EXTENSION_ONLY:
				newStrRef = CreateExtensionOnlyFromCFURL(contextData.chooseFilePath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FOLDER_PATH:
				newStrRef = CreatePathFromCFURL(contextData.chooseFolderPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FOLDER_PARENT_PATH:
				newStrRef = CreateParentPathFromCFURL(contextData.chooseFolderPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FOLDER_NAME:
				newStrRef = CreateNameFromCFURL(contextData.chooseFolderPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION:
				newStrRef = CreateNameNoExtensionFromCFURL(contextData.chooseFolderPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FOLDER_EXTENSION_ONLY:
				newStrRef = CreateExtensionOnlyFromCFURL(contextData.chooseFolderPath, kEscapeNone);
			break;

			case DLG_CHOOSE_OBJECT_PATH:
				newStrRef = CreatePathFromCFURL(contextData.chooseObjectPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_OBJECT_PARENT_PATH:
				newStrRef = CreateParentPathFromCFURL(contextData.chooseObjectPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_OBJECT_NAME:
				newStrRef = CreateNameFromCFURL(contextData.chooseObjectPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION:
				newStrRef = CreateNameNoExtensionFromCFURL(contextData.chooseObjectPath, kEscapeNone);
			break;

			case DLG_CHOOSE_OBJECT_EXTENSION_ONLY:
				newStrRef = CreateExtensionOnlyFromCFURL(contextData.chooseObjectPath, kEscapeNone);
			break;

			case DLG_PASSWORD:
				newStrRef = commandRuntimeData.inputText.Get();
				releaseNewString = false;
			break;
			
			// this is deprecated. Abracode.framework paths as below are preferred since version 2.0
			case MY_BUNDLE_PATH:
			{
				if(mBundleRef != NULL)
				{
					CFObj<CFURLRef> myBundlePathURL( ::CFBundleCopyBundleURL(mBundleRef) );
					if(myBundlePathURL != NULL)
						newStrRef = CreatePathFromCFURL(myBundlePathURL, kEscapeNone);
				}
				else
				{
					LOG_CSTR( "OMC: MY_BUNDLE_PATH. bundle ref is NULL\n" );
				}
			}
			break;
			
			case OMC_RESOURCES_PATH: //always exported
			{
				newStrRef = mOmcResourcesPath;
				releaseNewString = false;
			}
			break;
			
			case OMC_SUPPORT_PATH: //always exported
			{
				newStrRef = mOmcSupportPath;
				releaseNewString = false;
			}
			break;

			case APP_BUNDLE_PATH: //always exported
			case MY_HOST_BUNDLE_PATH: //deprecated as of OMC 4.0
				newStrRef = mMyHostBundlePath;
				releaseNewString = false;
			break;
			
			case MY_EXTERNAL_BUNDLE_PATH:
			{
				if(currCommand.externalBundlePath != nullptr)
				{
					newStrRef = currCommand.externalBundlePath;
					releaseNewString = false;
				}
				else
				{
					newStrRef = CreateDefaultExternBundleString(currCommand.name);
				}
			}
			break;

			case FRONT_PROCESS_ID:
			{
				pid_t frontPID = 0;
				if((mHostApp == kOMCHostApp_ShortcutsObserver) && (mFrontProcessPID != 0))
					frontPID = mFrontProcessPID;
				else
					frontPID = GetFrontAppPID();
				
				newStrRef = CFStringCreateWithFormat( kCFAllocatorDefault, nullptr, CFSTR("%d"), frontPID );
			}
			break;
			
			case FRONT_APPLICATION_NAME:
			{
				CFObj<CFStringRef> frontAppStr;
				if((mHostApp == kOMCHostApp_ShortcutsObserver) && (mFrontProcessPID != 0))
					frontAppStr.Adopt(CopyAppNameForPID(mFrontProcessPID) );
				
				if(frontAppStr == nullptr)
					frontAppStr.Adopt(CopyFrontAppName());
				
				newStrRef = frontAppStr.Detach();
			}
			break;

			//regular control values are always exported with AddEnvironmentVariablesForAllControls below
			//case NIB_DLG_CONTROL_VALUE:
			//case NIB_TABLE_VALUE:
			
			//special on-demand value, which is costly to obtain
			case NIB_TABLE_ALL_ROWS:
			{
				if(activeDialog != nullptr)
					newStrRef = activeDialog->CreateNibControlValue(specialWordID, theKey, kEscapeNone, true);
			}
			break;
			
			case NIB_DLG_GUID: //always exported
			{
                newStrRef = commandRuntimeData.GetAssociatedDialogUUID();
                releaseNewString = false;
			}
			break;
			
			case CURRENT_COMMAND_GUID: //always exported. the side effect is that we now always check for next command in /tmp/OMC/current-command.id file
			{
                newStrRef = commandRuntimeData.GetCommandUUID();
                releaseNewString = false;
			}
			break;
			
			default:
			break;
		}

		if(newStrRef != NULL)
		{
			if(releaseNewString)
				newDel.Adopt(newStrRef, kCFObjDontRetain);
			::CFDictionarySetValue(ioEnvironList, theKey, newStrRef);
		}
	}
	
	if(activeDialog != nullptr)
		activeDialog->AddEnvironmentVariablesForAllControls(ioEnvironList);
}


CFStringRef
OnMyCommandCM::CreateDynamicCommandName(const CommandDescription &currCommand,
                                        CommandRuntimeData &commandRuntimeData,
                                        CFStringRef inLocTableName,
                                        CFBundleRef inLocBundleRef)
{
    OMCContextData &contextData = commandRuntimeData.GetContextData();
    
	CFStringRef commandName = NULL;
	if( (contextData.objectList.size() > 1) && (currCommand.namePlural != NULL) )
	{
		commandName = currCommand.namePlural;
		if(inLocTableName != NULL)
			commandName = ::CFCopyLocalizedStringFromTableInBundle( commandName, inLocTableName, inLocBundleRef, "");
		else
			::CFRetain(commandName);
	}
	else if( currCommand.nameIsDynamic && currCommand.nameContainsDynamicText && (contextData.contextText != NULL) )
	{
		//clip the text here to reasonable size,
		const CFIndex kMaxCharCount = 60;
		CFIndex totalLen = ::CFStringGetLength( contextData.contextText );
		CFIndex theLen = totalLen;
		CFObj<CFMutableStringRef> newString;
		bool textIsClipped = false;
		if(theLen > kMaxCharCount)
		{
			CFObj<CFStringRef> shortString( ::CFStringCreateWithSubstring(kCFAllocatorDefault, contextData.contextText, CFRangeMake(0, kMaxCharCount)) );
			newString.Adopt( ::CFStringCreateMutableCopy(kCFAllocatorDefault, kMaxCharCount + 4, shortString) );
			textIsClipped = true;
		}
		else
		{
			newString.Adopt( ::CFStringCreateMutableCopy(kCFAllocatorDefault, kMaxCharCount + 4, contextData.contextText) );
		}

		::CFStringTrimWhitespace( newString );
		totalLen = ::CFStringGetLength( newString );
		theLen = totalLen;

		CFObj<CFStringRef> subString;
		//first find the line break within first 60 chars
		CFObj<CFMutableCharacterSetRef> linebreakSet( ::CFCharacterSetCreateMutable(kCFAllocatorDefault) );
		::CFCharacterSetAddCharactersInRange( linebreakSet, CFRangeMake(0x0A, 1) );//LF
		::CFCharacterSetAddCharactersInRange( linebreakSet, CFRangeMake(0x0D, 1) );//CR
		CFRange linebreakRange = CFRangeMake(0, 0);
		Boolean isLinebreakFound = ::CFStringFindCharacterFromSet(newString, linebreakSet, CFRangeMake(0, theLen), 0, &linebreakRange);
		if( isLinebreakFound && (linebreakRange.location > 0) ) //allow at least 1 character before line break
		{
			theLen = linebreakRange.location;
			subString.Adopt( ::CFStringCreateWithSubstring(kCFAllocatorDefault, newString, CFRangeMake(0, theLen)) );
		}
		else if( textIsClipped )
		{//find last whitechar in the clipped string
			CFRange subRange = CFRangeMake(0, theLen);
			CFCharacterSetRef theWhiteCharsSet = ::CFCharacterSetGetPredefined( kCFCharacterSetWhitespaceAndNewline );
			Boolean whitespaceFound = ::CFStringFindCharacterFromSet(newString, theWhiteCharsSet, subRange, kCFCompareBackwards, &subRange);
			if( whitespaceFound && (subRange.location > 0) )
				theLen = subRange.location;
		
			subString.Adopt( ::CFStringCreateWithSubstring(kCFAllocatorDefault, newString, CFRangeMake(0, theLen)) );
		}
		else
		{
			subString.Adopt( newString, kCFObjRetain );
		}
		
		if(theLen < totalLen)
		{
			CFObj<CFMutableStringRef> shortenedString( ::CFStringCreateMutableCopy(kCFAllocatorDefault, kMaxCharCount + 4, subString) );
			::CFStringAppend(shortenedString, CFSTR("...") );
			commandName = CreateCommandStringWithText(currCommand.name,
                                                      shortenedString,
                                                      commandRuntimeData,
                                                      kEscapeNone,
                                                      inLocTableName,
                                                      inLocBundleRef);
		}
		else
		{//short enough and no newlines to use the whole string
			commandName = CreateCommandStringWithText(currCommand.name,
                                                      newString,
                                                      commandRuntimeData,
                                                      kEscapeNone,
                                                      inLocTableName,
                                                      inLocBundleRef);
		}
	}
	else
	{
		commandName = CreateCombinedStringWithObjects(currCommand.name,
                                                      commandRuntimeData,
                                                      inLocTableName,
                                                      inLocBundleRef);
	}

	return commandName;
}


//subcommand should have the same name as main command and unique command ID
//0 is not a valid subcommand number

SInt32
OnMyCommandCM::FindSubcommandIndex(CFArrayRef inName, CFStringRef inCommandID)
{
	if( (mCommandList == NULL) || (inCommandID == NULL) )
		return -1;
	
	for(UInt32 i = 0; i < mCommandCount; i++)
	{
		if( (mCommandList[i].commandID != NULL) && ::CFEqual(mCommandList[i].commandID, inCommandID) )
		{
			if(inName == NULL) //name not provided - use the first one found
				return i;
			
			if(mCommandList[i].name != NULL)
			{
				if( ::CFEqual(mCommandList[i].name, inName) )
				{
					return i;
				}
			}
		}
	}
	return -1;//not found
}

//this allows finding by id or by name. It is used by find by next command where ID may point to a command with different name

SInt32
OnMyCommandCM::FindCommandIndex(CFArrayRef inName, CFStringRef inCommandID)
{
	if( mCommandList == NULL )
		return -1;
	
	SInt32 foundByID = -1;
	SInt32 foundByName = -1;
	
	for(UInt32 i = 0; i < mCommandCount; i++)
	{
		if( (inCommandID != NULL) && (mCommandList[i].commandID != NULL) && ::CFEqual(mCommandList[i].commandID, inCommandID) )
		{
			if(inName == NULL) //name not provided - use the first one found by id
				return i;
			else if( (mCommandList[i].name != NULL) && ::CFEqual(mCommandList[i].name, inName) )
				return i; //name and id matched - best case scenario
			
			foundByID = i;
		}
		else if( (inName != NULL) && (mCommandList[i].name != NULL)  && ::CFEqual(mCommandList[i].name, inName) )
			foundByName = i;
	}
	
	//id is more important than name
	if(foundByID > -1)
		return foundByID;
	
	return foundByName; //last resort
}


//inCommandName is needed to find the subcommand with the same name

OSStatus
OnMyCommandCM::ExecuteSubcommand(CFArrayRef inCommandName, CFStringRef inCommandID, CommandRuntimeData *parentCommandRuntimeData, CFTypeRef inContext)
{
    CFStringRef dialogUUID = nullptr;
    if(parentCommandRuntimeData != nullptr)
    {
        dialogUUID = parentCommandRuntimeData->GetAssociatedDialogUUID();
    }

    SInt32 commandIndex;
	if((dialogUUID != NULL) && OMCDialog::IsPredefinedDialogCommandID(inCommandID))
		commandIndex = FindSubcommandIndex(inCommandName, inCommandID); //only strict subcommand for predefined dialog commands
	else																//(command name must match)
		commandIndex = FindCommandIndex(inCommandName, inCommandID);//relaxed rules when no dialog or custom command id
																	//(for example when used for next command)
	return ExecuteSubcommand(commandIndex, parentCommandRuntimeData, inContext);
}

OSStatus
OnMyCommandCM::ExecuteSubcommand(SInt32 commandIndex, CommandRuntimeData *parentCommandRuntimeData, CFTypeRef inContext)
{
    if(commandIndex < 0)
    {
        return eventNotHandledErr;
    }
    
    if((mCommandList == nullptr) || (mCommandCount == 0))
    {
        return eventNotHandledErr;
    }
    
    SInt32 parentCommandIndex = mCurrCommandIndex;
    OSStatus err = noErr;
    
	try
	{
		//we don't want errors from previous subcommands to persist
		//we start clean
		mError = noErr;

        err = CommonContextCheck( NULL, inContext, NULL, commandIndex );
		if(err == noErr)
        {
            err = ExecuteCommand(nullptr, commandIndex, parentCommandRuntimeData);
        }
	}
	catch(...)
	{
		err = -1;
	}

	if(err != noErr)
    {
        mError = err;
    }
    
	mCurrCommandIndex = parentCommandIndex;
	
	return err;
}


CFBundleRef
OnMyCommandCM::GetCurrentCommandExternBundle()
{
	CommandDescription &currCommand = GetCurrentCommand();

	if( currCommand.externBundleResolved )
		return currCommand.externBundle;//NULL or not NULL - we have been here before so don't repeat the costly steps
	
	currCommand.externBundleResolved = true;

	if( currCommand.externalBundlePath != nullptr )
	{
		CFObj<CFURLRef> bundleURL( ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, currCommand.externalBundlePath, kCFURLPOSIXPathStyle, true) );
		if(bundleURL != nullptr)
		{
			currCommand.externBundle = CMUtils::CFBundleCreate(bundleURL);
			if(currCommand.externBundle != nullptr)
				return currCommand.externBundle;
		}
	}

	//not explicitly set but might exist - so check it now
	currCommand.externBundle = CreateDefaultExternBundleRef(currCommand.name);
	
	return currCommand.externBundle;
}

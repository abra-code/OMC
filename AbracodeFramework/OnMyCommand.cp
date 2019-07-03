//**************************************************************************************
// Filename:	OnMyCommandCM.cp
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright � 2002-2005 Abracode, Inc.  All rights reserved.
//
// Description:	Executes Unix commands in Terminal.app or silently
//
//**************************************************************************************


#include "OnMyCommand.h"
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
//#include "OMCCocoaDialog.h"
#include "OMCDialog.h"
#include "OMCInputDialog.h"
#include "SelectionIterator.h"
#include "ACFPropertyList.h"
#include "ACFURL.h"

extern Boolean RunCocoaDialog(OnMyCommandCM *inPlugin);

enum
{
	kClearTextDialogIndx		= 128,
	kPasswordTextDialogIndx		= 129,
	kPopupMenuDialogIndx		= 130,
	kComboBoxDialogIndx			= 131
};


//const FourCharCode kTerminalAppSig = 'trmx';
const FourCharCode kITermAppSig = 'ITRM';
#define kTerminalAppBundleID "com.apple.Terminal"

CFStringRef kOMCTopCommandID = CFSTR("top!");

const CommandDescription kEmptyCommand =
{
	NULL,	//name
	NULL,	//namePlural
	NULL,	//command
	NULL,	//inputPipe
	NULL,	//activationTypes
	0,		//activationTypeCount
	NULL,	//activationExtensions
	kExecSilentPOpen,	//executionMode
	kExecutionOption_None, //executionOptions
	kActiveAlways,	//activationMode
	kEscapeWithBackslash,	//escapeSpecialCharsMode
	kMulObjProcessSeparately,	//multipleObjectProcessing
	kSortMethodNone, //sortMethod
	true,	//sortAscending
	0,		//sortOptions
	NULL,	//mulObjPrefix
	NULL,	//mulObjSuffix
	NULL,	//mulObjSeparator
	NULL,	//warningStr
	NULL,	//warningExecuteStr
	NULL,	//warningCancelStr
	NULL,	//submenuName
	kOmcCommandNoSpecialObjects, //prescannedCommandInfo
	false,	//isPrescanned
	true,	//bringTerminalToFront
	true,	//openNewTerminalSession
	false,	//simulatePaste
	false,  //nameIsDynamic
	false,  //nameContainsText
	kInputClearText, //inputDialogType
	NULL,	//inputDialogOK
	NULL,	//inputDialogCancel
	NULL,	//inputDialogMessage
	NULL,	//inputDialogDefault
	NULL,	//inputDialogMenuItems
	NULL,	//refresh

	NULL, //saveAsParams
	NULL, //chooseFileParams
	NULL, //chooseFolderParams
	NULL, //chooseObjectParams

	NULL, //saveAsPath;
	NULL, //chooseFilePath;
	NULL, //chooseFolderPath;
	NULL, //chooseObjectPath;

	NULL,	//outputWindowOptions
	NULL,	//nibDialog
//	NULL,	//dialogNibName
//	NULL,	//nibWindowName
//	'ini!',	//initSubcommandID
//	'end!', //endOKSubcommandID
//	'cnc!', //endCancelSubcommandID
	NULL,	//appNames
	0,		//textReplaceOptions
	NULL,	//commandID, "top!" = main command, NULL is not valid now
	NULL,	//nextCommandID
	NULL,	//externalBundlePath
	NULL,	//externBundle //populated on first request and cached
	NULL,	//popenShell
	NULL,	//customEnvironVariables
	false,	//actOnlyInListedApps
	false,	//useDeputy
	false,	//disabled
	false,	//isSubcommand
	MIN_OMC_VERSION, //requiredOMCVersion
	MIN_MAC_OS_VERSION, //requiredMacOSMinVersion
	MAX_MAC_OS_VERSION, //requiredMacOSMaxVersion
	NULL, //iTermShellPath
	NULL, //endNotification
	NULL, //progress
	0, //maxTaskCount
	NULL, //contextMatchString
	0, //matchCompareOptions
	kMatchExact, //matchMethod
	kMatchFileName, //matchFileOptions
	false, //externBundleResolved - costly call to find the extern bundle - do it once and flag it here
	NULL, //multipleSelectionIteratorParams
	NULL, //localizationTableName
	NULL, //currState
};

enum SpecialWordIDs
{
	NO_SPECIAL_WORD = 0,

	OBJ_TEXT,
	OBJ_PATH,
	OBJ_PATH_NO_EXTENSION,//deprecated
	OBJ_PARENT_PATH,
	OBJ_NAME,
	OBJ_NAME_NO_EXTENSION,
	OBJ_EXTENSION_ONLY,
	OBJ_DISPLAY_NAME,
	OBJ_COMMON_PARENT_PATH,
	OBJ_PATH_RELATIVE_TO_COMMON_PARENT,

	DLG_INPUT_TEXT,
	DLG_PASSWORD,//deprecated

	DLG_SAVE_AS_PATH,
	DLG_SAVE_AS_PARENT_PATH,
	DLG_SAVE_AS_NAME,
	DLG_SAVE_AS_NAME_NO_EXTENSION,
	DLG_SAVE_AS_EXTENSION_ONLY,

	DLG_CHOOSE_FILE_PATH,
	DLG_CHOOSE_FILE_PARENT_PATH,
	DLG_CHOOSE_FILE_NAME,
	DLG_CHOOSE_FILE_NAME_NO_EXTENSION,
	DLG_CHOOSE_FILE_EXTENSION_ONLY,

	DLG_CHOOSE_FOLDER_PATH,
	DLG_CHOOSE_FOLDER_PARENT_PATH,
	DLG_CHOOSE_FOLDER_NAME,
	DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION,
	DLG_CHOOSE_FOLDER_EXTENSION_ONLY,

	DLG_CHOOSE_OBJECT_PATH,
	DLG_CHOOSE_OBJECT_PARENT_PATH,
	DLG_CHOOSE_OBJECT_NAME,
	DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION,
	DLG_CHOOSE_OBJECT_EXTENSION_ONLY,
	
	MY_BUNDLE_PATH, //new paths for droplets mostly
	OMC_RESOURCES_PATH,
	OMC_SUPPORT_PATH,
	MY_HOST_BUNDLE_PATH, //MY_HOST_BUNDLE_PATH is preferred for droplets actually
	MY_EXTERNAL_BUNDLE_PATH, //points to EXTERNAL_BUNDLE_PATH defined in description. redundant but needed for portability
	NIB_DLG_GUID,
	NIB_DLG_CONTROL_VALUE,
	NIB_TABLE_VALUE,
	NIB_TABLE_ALL_ROWS,
	CURRENT_COMMAND_GUID,
	FRONT_PROCESS_ID,
	FRONT_APPLICATION_NAME
};

//we take advantage of the fact that __XXX__ word has the same length as OMC_XXX

static const SpecialWordAndID sSpecialWordAndIDList[] =
{
	//wordLen												// specialWord         //environName           //id
	{ sizeof("__OBJ_TEXT__")-1,								CFSTR("__OBJ_TEXT__"), CFSTR("OMC_OBJ_TEXT"),  OBJ_TEXT },
	{ sizeof("__OBJ_PATH__")-1,								CFSTR("__OBJ_PATH__"), CFSTR("OMC_OBJ_PATH"),  OBJ_PATH },
	{ sizeof("__OBJ_PARENT_PATH__")-1,						CFSTR("__OBJ_PARENT_PATH__"), CFSTR("OMC_OBJ_PARENT_PATH"),  OBJ_PARENT_PATH },
	{ sizeof("__OBJ_NAME__")-1,								CFSTR("__OBJ_NAME__"), CFSTR("OMC_OBJ_NAME"),  OBJ_NAME },
	{ sizeof("__OBJ_NAME_NO_EXTENSION__")-1,				CFSTR("__OBJ_NAME_NO_EXTENSION__"), CFSTR("OMC_OBJ_NAME_NO_EXTENSION"),  OBJ_NAME_NO_EXTENSION },
	{ sizeof("__OBJ_EXTENSION_ONLY__")-1,					CFSTR("__OBJ_EXTENSION_ONLY__"), CFSTR("OMC_OBJ_EXTENSION_ONLY"),  OBJ_EXTENSION_ONLY },
	{ sizeof("__OBJ_DISPLAY_NAME__")-1,						CFSTR("__OBJ_DISPLAY_NAME__"), CFSTR("OMC_OBJ_DISPLAY_NAME"),  OBJ_DISPLAY_NAME },
	{ sizeof("__OBJ_COMMON_PARENT_PATH__")-1,				CFSTR("__OBJ_COMMON_PARENT_PATH__"), CFSTR("OMC_OBJ_COMMON_PARENT_PATH"),  OBJ_COMMON_PARENT_PATH },
	{ sizeof("__OBJ_PATH_RELATIVE_TO_COMMON_PARENT__")-1,	CFSTR("__OBJ_PATH_RELATIVE_TO_COMMON_PARENT__"), CFSTR("OMC_OBJ_PATH_RELATIVE_TO_COMMON_PARENT"),  OBJ_PATH_RELATIVE_TO_COMMON_PARENT },

	{ sizeof("__DLG_INPUT_TEXT__")-1,						CFSTR("__DLG_INPUT_TEXT__"), CFSTR("OMC_DLG_INPUT_TEXT"),  DLG_INPUT_TEXT },

	{ sizeof("__DLG_SAVE_AS_PATH__")-1,						CFSTR("__DLG_SAVE_AS_PATH__"), CFSTR("OMC_DLG_SAVE_AS_PATH"),  DLG_SAVE_AS_PATH },
	{ sizeof("__DLG_SAVE_AS_PARENT_PATH__")-1,				CFSTR("__DLG_SAVE_AS_PARENT_PATH__"), CFSTR("OMC_DLG_SAVE_AS_PARENT_PATH"),  DLG_SAVE_AS_PARENT_PATH },
	{ sizeof("__DLG_SAVE_AS_NAME__")-1,						CFSTR("__DLG_SAVE_AS_NAME__"), CFSTR("OMC_DLG_SAVE_AS_NAME"),  DLG_SAVE_AS_NAME },
	{ sizeof("__DLG_SAVE_AS_NAME_NO_EXTENSION__")-1,		CFSTR("__DLG_SAVE_AS_NAME_NO_EXTENSION__"), CFSTR("OMC_DLG_SAVE_AS_NAME_NO_EXTENSION"),  DLG_SAVE_AS_NAME_NO_EXTENSION },
	{ sizeof("__DLG_SAVE_AS_EXTENSION_ONLY__")-1,			CFSTR("__DLG_SAVE_AS_EXTENSION_ONLY__"), CFSTR("OMC_DLG_SAVE_AS_EXTENSION_ONLY"),  DLG_SAVE_AS_EXTENSION_ONLY },

	{ sizeof("__DLG_CHOOSE_FILE_PATH__")-1,					CFSTR("__DLG_CHOOSE_FILE_PATH__"), CFSTR("OMC_DLG_CHOOSE_FILE_PATH"),  DLG_CHOOSE_FILE_PATH },
	{ sizeof("__DLG_CHOOSE_FILE_PARENT_PATH__")-1,			CFSTR("__DLG_CHOOSE_FILE_PARENT_PATH__"), CFSTR("OMC_DLG_CHOOSE_FILE_PARENT_PATH"),  DLG_CHOOSE_FILE_PARENT_PATH },
	{ sizeof("__DLG_CHOOSE_FILE_NAME__")-1,					CFSTR("__DLG_CHOOSE_FILE_NAME__"), CFSTR("OMC_DLG_CHOOSE_FILE_NAME"),  DLG_CHOOSE_FILE_NAME },
	{ sizeof("__DLG_CHOOSE_FILE_NAME_NO_EXTENSION__")-1,	CFSTR("__DLG_CHOOSE_FILE_NAME_NO_EXTENSION__"), CFSTR("OMC_DLG_CHOOSE_FILE_NAME_NO_EXTENSION"),  DLG_CHOOSE_FILE_NAME_NO_EXTENSION },
	{ sizeof("__DLG_CHOOSE_FILE_EXTENSION_ONLY__")-1,		CFSTR("__DLG_CHOOSE_FILE_EXTENSION_ONLY__"), CFSTR("OMC_DLG_CHOOSE_FILE_EXTENSION_ONLY"),  DLG_CHOOSE_FILE_EXTENSION_ONLY },

	{ sizeof("__DLG_CHOOSE_FOLDER_PATH__")-1,				CFSTR("__DLG_CHOOSE_FOLDER_PATH__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_PATH"),  DLG_CHOOSE_FOLDER_PATH },
	{ sizeof("__DLG_CHOOSE_FOLDER_PARENT_PATH__")-1,		CFSTR("__DLG_CHOOSE_FOLDER_PARENT_PATH__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_PARENT_PATH"),  DLG_CHOOSE_FOLDER_PARENT_PATH },
	{ sizeof("__DLG_CHOOSE_FOLDER_NAME__")-1,				CFSTR("__DLG_CHOOSE_FOLDER_NAME__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_NAME"),  DLG_CHOOSE_FOLDER_NAME },
	{ sizeof("__DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION__")-1,	CFSTR("__DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION"),  DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION },
	{ sizeof("__DLG_CHOOSE_FOLDER_EXTENSION_ONLY__")-1,		CFSTR("__DLG_CHOOSE_FOLDER_EXTENSION_ONLY__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_EXTENSION_ONLY"),  DLG_CHOOSE_FOLDER_EXTENSION_ONLY },

	{ sizeof("__DLG_CHOOSE_OBJECT_PATH__")-1,				CFSTR("__DLG_CHOOSE_OBJECT_PATH__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_PATH"),  DLG_CHOOSE_OBJECT_PATH },
	{ sizeof("__DLG_CHOOSE_OBJECT_PARENT_PATH__")-1,		CFSTR("__DLG_CHOOSE_OBJECT_PARENT_PATH__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_PARENT_PATH"),  DLG_CHOOSE_OBJECT_PARENT_PATH },
	{ sizeof("__DLG_CHOOSE_OBJECT_NAME__")-1,				CFSTR("__DLG_CHOOSE_OBJECT_NAME__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_NAME"),  DLG_CHOOSE_OBJECT_NAME },
	{ sizeof("__DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION__")-1,	CFSTR("__DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION"),  DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION },
	{ sizeof("__DLG_CHOOSE_OBJECT_EXTENSION_ONLY__")-1,		CFSTR("__DLG_CHOOSE_OBJECT_EXTENSION_ONLY__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_EXTENSION_ONLY"),  DLG_CHOOSE_OBJECT_EXTENSION_ONLY },

	{ sizeof("__OMC_RESOURCES_PATH__")-1,					CFSTR("__OMC_RESOURCES_PATH__"), CFSTR("OMC_OMC_RESOURCES_PATH"),  OMC_RESOURCES_PATH },//framework path
	{ sizeof("__OMC_SUPPORT_PATH__")-1,						CFSTR("__OMC_SUPPORT_PATH__"), CFSTR("OMC_OMC_SUPPORT_PATH"),  OMC_SUPPORT_PATH },//framework path
	{ sizeof("__MY_HOST_BUNDLE_PATH__")-1,					CFSTR("__MY_HOST_BUNDLE_PATH__"), CFSTR("OMC_MY_HOST_BUNDLE_PATH"),  MY_HOST_BUNDLE_PATH },//preferred for droplets actually
	{ sizeof("__MY_EXTERNAL_BUNDLE_PATH__")-1,				CFSTR("__MY_EXTERNAL_BUNDLE_PATH__"), CFSTR("OMC_MY_EXTERNAL_BUNDLE_PATH"),  MY_EXTERNAL_BUNDLE_PATH },//external bundle location
	{ sizeof("__NIB_DLG_GUID__")-1,							CFSTR("__NIB_DLG_GUID__"), CFSTR("OMC_NIB_DLG_GUID"),  NIB_DLG_GUID },
	{ sizeof("__CURRENT_COMMAND_GUID__")-1,					CFSTR("__CURRENT_COMMAND_GUID__"), CFSTR("OMC_CURRENT_COMMAND_GUID"),  CURRENT_COMMAND_GUID },
	
	{ sizeof("__FRONT_PROCESS_ID__")-1,						CFSTR("__FRONT_PROCESS_ID__"), CFSTR("OMC_FRONT_PROCESS_ID"),  FRONT_PROCESS_ID },
	{ sizeof("__FRONT_APPLICATION_NAME__")-1,				CFSTR("__FRONT_APPLICATION_NAME__"), CFSTR("OMC_FRONT_APPLICATION_NAME"),  FRONT_APPLICATION_NAME },
	
//deprecated synonyms, still supported but should not appear in OMCEdit choices
	{ sizeof("__INPUT_TEXT__")-1,							CFSTR("__INPUT_TEXT__"), CFSTR("OMC_INPUT_TEXT"),  DLG_INPUT_TEXT },
	{ sizeof("__OBJ_PATH_NO_EXTENSION__")-1,				CFSTR("__OBJ_PATH_NO_EXTENSION__"), CFSTR("OMC_OBJ_PATH_NO_EXTENSION"),  OBJ_PATH_NO_EXTENSION },//not needed since = OBJ_PARENT_PATH + OBJ_NAME_NO_EXTENSION
	{ sizeof("__PASSWORD__")-1,								CFSTR("__PASSWORD__"), CFSTR("OMC_PASSWORD"),  DLG_PASSWORD },
	{ sizeof("__SAVE_AS_PATH__")-1,							CFSTR("__SAVE_AS_PATH__"), CFSTR("OMC_SAVE_AS_PATH"),  DLG_SAVE_AS_PATH },
	{ sizeof("__SAVE_AS_PARENT_PATH__")-1,					CFSTR("__SAVE_AS_PARENT_PATH__"), CFSTR("OMC_SAVE_AS_PARENT_PATH"),  DLG_SAVE_AS_PARENT_PATH },
	{ sizeof("__SAVE_AS_FILE_NAME__")-1,					CFSTR("__SAVE_AS_FILE_NAME__"), CFSTR("OMC_SAVE_AS_FILE_NAME"),  DLG_SAVE_AS_NAME },
	{ sizeof("__MY_BUNDLE_PATH__")-1,						CFSTR("__MY_BUNDLE_PATH__"), CFSTR("OMC_MY_BUNDLE_PATH"),  MY_BUNDLE_PATH }//added for droplets, not very useful for CM
};

//min and max len defined for slight optimization in resolving special words
//the shortest is __OBJ_TEXT__
const CFIndex kMinSpecialWordLen = sizeof("__OBJ_TEXT__") - 1;
//the longest is __DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION__
const CFIndex kMaxSpecialWordLen = sizeof("__DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION__") - 1;

//there are also 2 dynamic names:
//										  __NIB_DIALOG_CONTROL_NNN_VALUE__
//										  __NIB_TABLE_NNN_COLUMN_MMM_VALUE__

#pragma mark -
#pragma mark **** IMPLEMENTATION ****


#ifdef _PRIVATE_FRAMEWORK_
	CFStringRef kBundleIDString = CFSTR("com.abracode.AbracodePrivateFramework");
#else
	CFStringRef kBundleIDString = CFSTR("com.abracode.AbracodeFramework");
#endif //_PRIVATE_FRAMEWORK_

/*
#ifdef _BUILD_DROPLET_
	CFStringRef kBundleIDString = CFSTR("com.abracode.CommandDroplet");
#else
	CFStringRef kBundleIDString = CFSTR("com.abracode.OnMyCommandCM");
#endif //_BUILD_DROPLET_
*/

OnMyCommandCM::OnMyCommandCM(CFPropertyListRef inPlistRef)
	: ACMPlugin( kBundleIDString ), mPlistURL(NULL),
	mSysVersion(100300), mCommandList(NULL), mCommandCount(0), mCurrCommandIndex(0),
	mCurrObjectIndex(0), mError(noErr),
	mIsTextInClipboard(false), mIsOpenFolder(false), mIsNullContext(false), mIsTextContext(false),
	mCMPluginMode(true), mRunningInShortcutsObserver(false)
{
	TRACE_CSTR( "OnMyCommandCM::OnMyCommandCM\n" );

	mFrontProcess.highLongOfPSN = 0;
	mFrontProcess.lowLongOfPSN = 0;

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
	TRACE_CSTR( "OnMyCommandCM::~OnMyCommandCM\n" );
	try
	{
		DeleteObjectList();
		DeleteCommandList();
	}
	catch(...)
	{
		LOG_CSTR( "OnMyCommandCM::~OnMyCommandCM: unknown exception has been caught\n" );
	}
}

OSStatus
OnMyCommandCM::Init(CFBundleRef inBundle)
{
	if(inBundle != NULL)//plugin has the bundle ref already, droplet sets it here
		mBundleRef.Adopt(inBundle, kCFObjRetain);

	SInt32 sysVerMajor = 10;
	SInt32 sysVerMinor = 4;
	SInt32 sysVerBugFix = 0;
	::Gestalt(gestaltSystemVersionMajor, &sysVerMajor);
	::Gestalt(gestaltSystemVersionMinor, &sysVerMinor);
	::Gestalt(gestaltSystemVersionBugFix, &sysVerBugFix);

	//eg. 100411 max 999999
	mSysVersion = 10000 * sysVerMajor + 100 * sysVerMinor + sysVerBugFix;

//	::Gestalt(gestaltSystemVersion, &mSysVersion);

//#if _DEBUG_
//	printf("OMC: Current system version = 0x%.8X, integer = %d\n", (unsigned int)mSysVersion, (int)mSysVersion);
//#endif

	ProcessSerialNumber psn = { 0, kCurrentProcess };
	FSRef myRef;
	OSStatus err = ::GetProcessBundleLocation(&psn, &myRef);
	if(err == noErr)
		mMyHostBundlePath.Adopt( ::CFURLCreateFromFSRef(kCFAllocatorDefault, &myRef), kCFObjDontRetain );

	mMyHostName.Adopt( CMUtils::CopyHostName(), kCFObjDontRetain );

#if  0 //_DEBUG_
	CFShow((CFURLRef)mMyHostBundlePath);
	CFShow((CFStringRef)mMyHostName);
#endif

	return err;
}

//classic API for CM
OSStatus
OnMyCommandCM::ExamineContext( const AEDesc *inAEContext, AEDescList *outCommandPairs )
{
	OSStatus err = Init(NULL);
	if(err != noErr)
		return err;
	
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
OnMyCommandCM::ExamineContext( CFTypeRef inCFContext, SInt32 inCommandRef )
{
	SInt32 cmdIndex = -1;
	if(inCommandRef >= kCMCommandStart)
		cmdIndex = mCurrCommandIndex = inCommandRef - kCMCommandStart;
	else
		mCurrCommandIndex = 0;

	return CommonContextCheck( NULL, inCFContext, NULL, cmdIndex );
}


OSStatus
OnMyCommandCM::CommonContextCheck( const AEDesc *inContext, CFTypeRef inCFContext, AEDescList *outCommandPairs, SInt32 inCmdIndex )
{
	TRACE_CSTR( "OnMyCommandCM::CommonContextCheck\n" );
	OSStatus err = noErr;

//it is OK to have NULL context
//	if( inContext == NULL )
//	{
//		DEBUG_CSTR( "OnMyCommandCM->CMPluginExamineContext error: inContext == NULL\n" );
//		return errAENotAEDesc;
//	}

#if _DEBUG_
	if(inContext != NULL)
	{
		DEBUG_CFSTR( CFSTR("OnMyCommandCM::ExamineContext. Data type is:") );
		CFObj<CFStringRef> dbgType( ::UTCreateStringForOSType(inContext->descriptorType) );
		DEBUG_CFSTR( (CFStringRef)dbgType );
	}
#endif

	ResetOutputWindowCascading();
	
	//from now on we assume that PostMenuCleanup will be called so we own the data
	//	Retain(); //no need to do it here and no need to Release() in PostMenuCleanup()

	mIsTextInClipboard = CMUtils::IsTextInClipboard();

	//remember if the context was null on CMPluginExamineContext
	//we cannot trust it when handling the selection later
	if(inContext != NULL)
		mIsNullContext = ((inContext->descriptorType == typeNull) || (inContext->dataHandle == NULL));
	else
		mIsNullContext = (inCFContext == NULL);

	if(inCFContext != NULL)
	{
		CFTypeID contextType = ::CFGetTypeID( inCFContext );
		if( contextType == ACFType<CFStringRef>::GetTypeID() )//text
		{
			mContextText.Adopt( (CFStringRef)inCFContext, kCFObjRetain);
			mIsTextContext = true;
		}
		else if( contextType == ACFType<CFArrayRef>::GetTypeID() ) //list of files
		{
			mContextFiles.Adopt(
					::CFArrayCreateMutable(kCFAllocatorDefault, mObjectList.size(), &kCFTypeArrayCallBacks),
					kCFObjDontRetain );

			CFArrayRef fileArray = (CFArrayRef)inCFContext;
			CFIndex fileCount = ::CFArrayGetCount(fileArray);
			if( (fileCount > 0) && (mContextFiles != NULL) )
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
							::CFArrayAppendValue( mContextFiles, (CFURLRef)oneUrl );
					}
				}
			}
		}
		else if( contextType == ACFType<CFURLRef>::GetTypeID() )
		{//make a list even if single file. preferrable because Finder in 10.3 or higher does that
			mContextFiles.Adopt(
								::CFArrayCreateMutable(kCFAllocatorDefault, 1, &kCFTypeArrayCallBacks),
								kCFObjDontRetain );
			::CFArrayAppendValue( mContextFiles, (CFURLRef)inCFContext );
		}
		else
		{
			LOG_CSTR( "OMC->CommonContextCheck: unknown context type\n" );
		}
	}

	Boolean runningInEditorApp = false;
	
	Boolean frontProcessIsFinder = false;
	CFObj<CFStringRef> frontProcessName;

	if(mMyHostName != NULL)
	{
#if IN_PROC_CM //64-bit apps no longer load CM plug-ins in-proc
		if( kCFCompareEqualTo == ::CFStringCompare( mMyHostName, CFSTR("Finder"), 0 ) )
		{
			TRACE_CSTR( "OnMyCommandCM->CMPluginExamineContext. running in Finder\n" );
		}
		else
#endif
        if( (kCFCompareEqualTo == ::CFStringCompare( mMyHostName, CFSTR("Shortcuts"), 0)) ||
				 (kCFCompareEqualTo == ::CFStringCompare( mMyHostName, CFSTR("Shortcuts32"), 0)) ||
				 (kCFCompareEqualTo == ::CFStringCompare( mMyHostName, CFSTR("OMCEdit"), 0)) )
		{
			runningInEditorApp = true;
		}
		else if( (kCFCompareEqualTo == ::CFStringCompare( mMyHostName, CFSTR("ShortcutObserver"), 0 )) ||
				 (kCFCompareEqualTo == ::CFStringCompare( mMyHostName, CFSTR("ShortcutObserver32"), 0 )) )
		{
			mRunningInShortcutsObserver = true;
			err = ::GetFrontProcess(&mFrontProcess);
			if(err == noErr)
			{
				err  = ::CopyProcessName (&mFrontProcess, &frontProcessName);
				if(frontProcessName != NULL)
				{
					if( kCFCompareEqualTo == ::CFStringCompare( frontProcessName, CFSTR("Finder"), 0 ) )
						frontProcessIsFinder = true;
				}
			}
		}
	}
	
#if OLD_CODE_USED_IN_INPROC_CM_PLUGINS
    if(mIsNullContext && mCMPluginMode)//for null context in CM mode try to get text from Cocoa host
	{
		TRACE_CSTR( "OnMyCommandCM->CMPluginExamineContext: inContext->descriptorType == typeNull\n" );
		mIsTextContext = (Boolean)cocoaAppHasStringSelection();
//	will need to show items marked as "always show"
//		if(mIsTextContext == false)
//			return errAENotAEDesc;//do not show CM when descriptor type is null and there is no selection in Cocoa app
	}	
#endif //OLD_CODE_USED_IN_INPROC_CM_PLUGINS
    
	if(mCommandList == NULL)
	{//not loaded yet?
		if( mPlistURL != NULL )
			LoadCommandsFromPlistFile(mPlistURL);
		else
			ReadPreferences();
	}

	Boolean anythingSelected = false;

	UInt32 theFlags = kListClear;
	if( !mIsNullContext && !mIsTextContext ) //we have some context that is not text
	{
		TRACE_CSTR( "OnMyCommandCM->CMPluginExamineContext: not null context descriptor\n" );
		//pre-allocate space for all object properties
		long listItemsCount = 0;
		err = paramErr;
		if(inContext != NULL)
		{
			err = ::AECountItems(inContext, &listItemsCount);
		}
		else if(mContextFiles != NULL)
		{
			listItemsCount = ::CFArrayGetCount(mContextFiles);
			err = noErr;
		}
		
		if(err  == noErr )
		{
			TRACE_CSTR( "OnMyCommandCM->CMPluginExamineContext: count of items in context: %d\n", (int)listItemsCount );

			if(listItemsCount > 0)
			{
                mObjectList.resize(listItemsCount);
				memset(mObjectList.data(), 0, listItemsCount*sizeof(OneObjProperties));
			}
		}

		if( mContextFiles != NULL )
			anythingSelected = CMUtils::ProcessObjectList( mContextFiles, theFlags, CFURLCheckFileOrFolder, this);
		else if(inContext != NULL)
			anythingSelected = CMUtils::ProcessObjectList( inContext, theFlags, FSRefCheckFileOrFolder, this );

	}

//update total count
    //currObjectIndex is incremented in FSRefCheckFileOrFolder for each valid object
    mObjectList.resize(mCurrObjectIndex);
	mCurrObjectIndex = 0;

	Boolean isFolder = false;
    if(mObjectList.size() == 1)
    {
        isFolder = CheckAllObjects(mObjectList, CheckIfFolder, NULL);
        if(isFolder)
        {
            Boolean isPackage = CheckAllObjects(mObjectList, CheckIfPackage, NULL);
            if(isPackage)
                isFolder = false;
        }
    }

	if(	anythingSelected && (mSysVersion >= 100300) && ((theFlags & kListOutMultipleObjects) == 0) && isFolder &&
		(mRunningInShortcutsObserver && frontProcessIsFinder) )
	{//single folder selected in Finder in 10.3 - check what it is
		mIsOpenFolder = CMUtils::IsClickInOpenFinderWindow(inContext, false);
		anythingSelected = ! mIsOpenFolder;
	}
	else if( !anythingSelected )
	{//not a list of objects - maybe an open window or desktop (pre-10.3 behavior)
		//check what was clicked
		FSRef folderRef;
		err = fnfErr;//anything to mark that there is no file
		if( (inContext != NULL) && (mIsNullContext == false) )
			err = CMUtils::GetFSRef( *inContext, folderRef );

		if(err == noErr)
		{
			DeleteObjectList();
            mObjectList.resize(1);
			memset(mObjectList.data(), 0, sizeof(OneObjProperties));
			
			if(mCMPluginMode)
			{
				err = FSRefCheckFileOrFolder( &folderRef, this );
				if(err == noErr)
				{
					isFolder = false;
					err = CMUtils::IsFolder( &folderRef, isFolder);
					if( (err == noErr) && isFolder )
					{
						mIsOpenFolder = true;
						TRACE_CSTR( "Open folder clicked\n" );
					}
				}
			}
		}
		else if( !mIsTextContext )
		{//maybe a selected text?
#if OLD_CODE_USED_IN_INPROC_CM_PLUGINS
			if( mCMPluginMode )
				mIsTextContext = (Boolean)cocoaAppHasStringSelection();
#endif

			if( (inContext != NULL) && !mIsTextContext && !mIsNullContext )
				mIsTextContext = CMUtils::AEDescHasTextData(*inContext);
		}
	}

	err = noErr;

	//menu population requested
	if(outCommandPairs != NULL)
	{
		(void)PopulateItemsMenu( inContext, outCommandPairs,
								runningInEditorApp || mRunningInShortcutsObserver,
								frontProcessName );
	}
	
	if(inCmdIndex >= 0)
	{
		bool isEnabled = IsCommandEnabled( inCmdIndex, inContext,
							runningInEditorApp || mRunningInShortcutsObserver,
							frontProcessName );
		if( !isEnabled )
			err = errAEWrongDataType;
	}
	

	return err;
}

Boolean
OnMyCommandCM::ExamineDropletFileContext(AEDescList *fileList)
{
	Boolean anythingToDo = false;
	UInt32 theFlags = kListClear;

	mCurrObjectIndex = 0;//FSRefCheckFileOrFolder increments this for each valid object

	if(fileList == NULL)
		return false;

	if( fileList->descriptorType != typeNull )
	{
		//pre-allocate space for all object properties
		long listItemsCount = 0;
		if( ::AECountItems(fileList, &listItemsCount) == noErr )
		{
			if(listItemsCount > 0)
			{
                mObjectList.resize(listItemsCount);
				memset(mObjectList.data(), 0, listItemsCount*sizeof(OneObjProperties));
			}
		}

		anythingToDo = CMUtils::ProcessObjectList( fileList, theFlags, OnMyCommandCM::FSRefCheckFileOrFolder, this );
	}

//update total count
	mObjectList.resize(mCurrObjectIndex);
	mCurrObjectIndex = 0;

	return anythingToDo;
}

// ---------------------------------------------------------------------------
// CMPluginHandleSelection
// ---------------------------------------------------------------------------
// Carry out the command that the user selected. The commandID indicates 
// which command was selected

//NO RETURNS IN THE MIDDLE!

// a new problem appeared in Mac OS 10.3.4 that was not seen before
//a null AEDesc is passed from Cocoa apps for CMPluginExamineContext
//but is corrupted (sometimes?) when it arrives to CMPluginHandleSelection

// pass NULL for inContext when executing with CF Context

OSStatus
OnMyCommandCM::HandleSelection( AEDesc *inContext, SInt32 inCommandID )
{
	TRACE_CSTR( "OnMyCommandCM::HandleSelection\n" );	

	if( (mCommandList == NULL) || (mCommandCount == 0) )
		return noErr;

	//from now on we assume that Release() will be called at the end of this function so we must not 
	//return somewhere in the middle of this!
	Retain();

	try
	{
		if(inCommandID >= kCMCommandStart)
		{
			mCurrCommandIndex = inCommandID - kCMCommandStart;
			if( mCurrCommandIndex >= mCommandCount )
				throw OSStatus(paramErr);
			
			CommandDescription &currCommand = mCommandList[mCurrCommandIndex];

			//take original command as parameter, not copy
			PrescanCommandDescription( currCommand );
			
			if(currCommand.currState == NULL)//top command may not have the command state object created yet
				currCommand.currState = new CommandState();

			//make a copy fo the description because when we show a dialog it may become invalid
			//StAEDesc contextCopy;
			//if(mIsNullContext == false)
			//{
			//	::AEDuplicateDesc(inContext, (AEDesc *)contextCopy);
			//}

			CFBundleRef localizationBundle = NULL;
			if(currCommand.localizationTableName != NULL)//client wants to be localized
			{
				localizationBundle = GetCurrentCommandExternBundle();
				if(localizationBundle == NULL)
					localizationBundle = CFBundleGetMainBundle();
			}

			//obtain text from selection before any dialogs are shown
			bool objListEmpty = (mObjectList.size() == 0);
			
			if( ((currCommand.prescannedCommandInfo & kOmcCommandContainsTextObject) != 0) && (mContextText == NULL) )
			{
				CreateTextContext(currCommand, inContext);
			}

			CFObj<CFStringRef> dynamicCommandName( CreateDynamicCommandName(currCommand, currCommand.localizationTableName, localizationBundle) );

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
			
			if( mSysVersion < currCommand.requiredMacOSMinVersion)
			{
				StSwitchToFront switcher;
				CFObj<CFStringRef> warningText( ::CFCopyLocalizedStringFromTableInBundle( CFSTR("TOO_LOW_MAC_OS"), 
																CFSTR("Private"), mBundleRef, "") );

				if( false == DisplayVersionWarning(mBundleRef, dynamicCommandName, warningText, currCommand.requiredMacOSMinVersion, mSysVersion) )
				{
					throw OSStatus(userCanceledErr);
				}
			}
			
			if(mSysVersion > currCommand.requiredMacOSMaxVersion)
			{
				StSwitchToFront switcher;
				CFObj<CFStringRef> warningText( ::CFCopyLocalizedStringFromTableInBundle( CFSTR("TOO_HIGH_MAC_OS"), 
																CFSTR("Private"), mBundleRef, "") );

				if( false == DisplayVersionWarning(mBundleRef, dynamicCommandName, warningText, currCommand.requiredMacOSMaxVersion, mSysVersion) )
				{
					throw OSStatus(userCanceledErr);
				}
			}
			
			if( currCommand.warningStr != NULL )
			{
				TRACE_CSTR("OnMyCommandCM About to display warning\n" );
				StSwitchToFront switcher;
				if( DisplayWarning(currCommand) == false )
				{
					throw OSStatus(userCanceledErr);
				}
			}
			
			if( ((currCommand.prescannedCommandInfo & kOmcCommandContainsInputText) != 0) && (mInputText == NULL) )
			{
				TRACE_CSTR( "OnMyCommandCM About to ask for input text\n" );
				StSwitchToFront switcher;

				//if( ShowInputDialog( currCommand, mInputText.GetReference() ) == false )
				if( RunCocoaInputDialog( this, mInputText.GetReference()) == false )
				{
					throw OSStatus(userCanceledErr);
				}
			}

			//if( (currCommand.dialogNibName != NULL) && (currCommand.nibWindowName != NULL) )//if dialog required
			if( currCommand.nibDialog != NULL )
			{
				ACFDict params( currCommand.nibDialog );
				Boolean isCocoa = false;
				params.GetValue( CFSTR("IS_COCOA"), isCocoa );

				//bring executing application to front. important when running within ShortcutsObserver
				//don't restore because for non-modal dialogs this would bring executing app behind along with the dialog
				StSwitchToFront switcher(false);
				
				if(isCocoa)
				{
					if( RunCocoaDialog( this ) == false )
						throw OSStatus(userCanceledErr);
				}
				else
				{
					CFObj<CFStringRef> dynamicCommandName( CreateDynamicCommandName(currCommand, currCommand.localizationTableName, localizationBundle) );
					DisplayAlert(mBundleRef, dynamicCommandName, CFSTR("CARBON_NIB_64_BIT"), kCFUserNotificationStopAlertLevel );
					throw OSStatus(userCanceledErr);
				}
			}

#if 0
			CFObj<CFURLRef> defaultLocationURL;
			if(currCommand.defaultNavLocation != NULL)
			{
				CFObj<CFMutableStringRef> defaultLocationStr( CreateCombinedStringWithObjects(currCommand.defaultNavLocation) );
				if(defaultLocationStr != NULL)
				{
					CFObj<CFStringRef> expandedLocationStr( CreatePathByExpandingTilde( defaultLocationStr ) );
					if(expandedLocationStr != NULL)
						defaultLocationURL.Adopt( ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, expandedLocationStr, kCFURLPOSIXPathStyle, true) );
				}
			}
#endif

			if( (currCommand.prescannedCommandInfo & kOmcCommandContainsSaveAsDialog) != 0 )
			{
				CFObj<CFStringRef> message;
				CFObj<CFArrayRef> defaultFileName;
				CFObj<CFArrayRef> defaultDirPath;
				UInt32 additionalFlags = 0;
				GetNavDialogParams( currCommand.saveAsParams, message.GetReference(), defaultFileName.GetReference(), defaultDirPath.GetReference(), additionalFlags );
				
				if(currCommand.saveAsPath != NULL)
				{
					CFRelease(currCommand.saveAsPath);
					currCommand.saveAsPath = NULL;
				}
				
				if( ((additionalFlags & kOMCFilePanelUseCachedPath) == 0) || (mCachedSaveAsPath == NULL) )
				{
					TRACE_CSTR("OnMyCommandCM About to display save as dialog\n" );
					CFObj<CFMutableStringRef> defaultName( CreateCombinedStringWithObjects(defaultFileName, currCommand.localizationTableName, localizationBundle) );
					
					CFObj<CFStringRef> expandedDirStr;
					CFObj<CFMutableStringRef> defaultLocationStr( CreateCombinedStringWithObjects(defaultDirPath, NULL, NULL) );
					if(defaultLocationStr != NULL)
						expandedDirStr.Adopt( CreatePathByExpandingTilde( defaultLocationStr ) );

					if( (currCommand.localizationTableName != NULL) && (localizationBundle != NULL) && (message != NULL) )
						message.Adopt( ::CFCopyLocalizedStringFromTableInBundle( message, currCommand.localizationTableName, localizationBundle, "") );

					StSwitchToFront switcher;
					currCommand.saveAsPath = CreateCFURLFromSaveAsDialog( dynamicCommandName, message, defaultName, expandedDirStr, additionalFlags);	
					if(currCommand.saveAsPath == NULL)
						throw OSStatus(userCanceledErr);

					if( (additionalFlags & kOMCFilePanelUseCachedPath) != 0 )
						mCachedSaveAsPath.Adopt( currCommand.saveAsPath, kCFObjRetain );
				}
				else
				{
					currCommand.saveAsPath = mCachedSaveAsPath;
					CFRetain(currCommand.saveAsPath);//will be released
				}
			}
			
			if( (currCommand.prescannedCommandInfo & kOmcCommandContainsChooseFileDialog) != 0 )
			{
				CFObj<CFStringRef> message;
				CFObj<CFArrayRef> defaultFileName;
				CFObj<CFArrayRef> defaultDirPath;
				UInt32 additionalFlags = 0;
				GetNavDialogParams( currCommand.chooseFileParams, message.GetReference(), defaultFileName.GetReference(), defaultDirPath.GetReference(), additionalFlags );

				if(currCommand.chooseFilePath != NULL)
				{
					CFRelease(currCommand.chooseFilePath);
					currCommand.chooseFilePath = NULL;
				}

				if( ((additionalFlags & kOMCFilePanelUseCachedPath) == 0) || (mCachedChooseFilePath == NULL) )
				{
					TRACE_CSTR("OnMyCommandCM About to display choose file dialog\n" );
					CFObj<CFMutableStringRef> defaultName( CreateCombinedStringWithObjects(defaultFileName, currCommand.localizationTableName, localizationBundle) );
					
					CFObj<CFStringRef> expandedDirStr;
					CFObj<CFMutableStringRef> defaultLocationStr( CreateCombinedStringWithObjects(defaultDirPath, NULL, NULL) );
					if(defaultLocationStr != NULL)
						expandedDirStr.Adopt( CreatePathByExpandingTilde( defaultLocationStr ) );

					if( (currCommand.localizationTableName != NULL) && (localizationBundle != NULL) && (message != NULL) )
						message.Adopt( ::CFCopyLocalizedStringFromTableInBundle( message, currCommand.localizationTableName, localizationBundle, "") );

					StSwitchToFront switcher;
					currCommand.chooseFilePath = CreateCFURLFromOpenDialog( dynamicCommandName, message, defaultName, defaultLocationStr, additionalFlags | kOMCFilePanelCanChooseFiles);	
					if(currCommand.chooseFilePath == NULL)
						throw OSStatus(userCanceledErr);

					if( (additionalFlags & kOMCFilePanelUseCachedPath) != 0 )
						mCachedChooseFilePath.Adopt( currCommand.chooseFilePath, kCFObjRetain );
				}
				else
				{
					currCommand.chooseFilePath = mCachedChooseFilePath;
					CFRetain(currCommand.chooseFilePath);//will be released
				}
			}

			if( (currCommand.prescannedCommandInfo & kOmcCommandContainsChooseFolderDialog) != 0 )
			{
				CFObj<CFStringRef> message;
				CFObj<CFArrayRef> defaultFileName;
				CFObj<CFArrayRef> defaultDirPath;
				UInt32 additionalFlags = 0;
				GetNavDialogParams( currCommand.chooseFolderParams, message.GetReference(), defaultFileName.GetReference(), defaultDirPath.GetReference(), additionalFlags );

				if(currCommand.chooseFolderPath != NULL)
				{
					CFRelease(currCommand.chooseFolderPath);
					currCommand.chooseFolderPath = NULL;
				}
				
				if( ((additionalFlags & kOMCFilePanelUseCachedPath) == 0) || (mCachedChooseFolderPath == NULL) )
				{
					TRACE_CSTR("OnMyCommandCM About to display choose folder dialog\n" );
					CFObj<CFMutableStringRef> defaultName( CreateCombinedStringWithObjects(defaultFileName, currCommand.localizationTableName, localizationBundle) );
					
					CFObj<CFStringRef> expandedDirStr;
					CFObj<CFMutableStringRef> defaultLocationStr( CreateCombinedStringWithObjects(defaultDirPath, NULL, NULL) );
					if(defaultLocationStr != NULL)
						expandedDirStr.Adopt( CreatePathByExpandingTilde( defaultLocationStr ) );
					
					if( (currCommand.localizationTableName != NULL) && (localizationBundle != NULL) && (message != NULL) )
						message.Adopt( ::CFCopyLocalizedStringFromTableInBundle( message, currCommand.localizationTableName, localizationBundle, "") );

					StSwitchToFront switcher;
					currCommand.chooseFolderPath = CreateCFURLFromOpenDialog( dynamicCommandName, message, defaultName, defaultLocationStr, additionalFlags | kOMCFilePanelCanChooseDirectories);	
					if(currCommand.chooseFolderPath == NULL)
						throw OSStatus(userCanceledErr);

					if( (additionalFlags & kOMCFilePanelUseCachedPath) != 0 )
						mCachedChooseFolderPath.Adopt( currCommand.chooseFolderPath, kCFObjRetain );
				}
				else
				{
					currCommand.chooseFolderPath = mCachedChooseFolderPath;
					CFRetain(currCommand.chooseFolderPath);//will be released
				}
			}

			if( (currCommand.prescannedCommandInfo & kOmcCommandContainsChooseObjectDialog) != 0 )
			{
				CFObj<CFStringRef> message;
				CFObj<CFArrayRef> defaultFileName;
				CFObj<CFArrayRef> defaultDirPath;
				UInt32 additionalFlags = 0;
				GetNavDialogParams( currCommand.chooseObjectParams, message.GetReference(), defaultFileName.GetReference(), defaultDirPath.GetReference(), additionalFlags );

				if(currCommand.chooseObjectPath != NULL)
				{
					CFRelease(currCommand.chooseObjectPath);
					currCommand.chooseObjectPath = NULL;
				}
				
				if( ((additionalFlags & kOMCFilePanelUseCachedPath) == 0) || (mCachedChooseObjectPath == NULL) )
				{
					TRACE_CSTR("OnMyCommandCM About to display choose object dialog\n" );
					CFObj<CFMutableStringRef> defaultName( CreateCombinedStringWithObjects(defaultFileName, currCommand.localizationTableName, localizationBundle) );
					
					CFObj<CFStringRef> expandedDirStr;
					CFObj<CFMutableStringRef> defaultLocationStr( CreateCombinedStringWithObjects(defaultDirPath, NULL, NULL) );
					if(defaultLocationStr != NULL)
						expandedDirStr.Adopt( CreatePathByExpandingTilde( defaultLocationStr ) );

					if( (currCommand.localizationTableName != NULL) && (localizationBundle != NULL) && (message != NULL) )
						message.Adopt( ::CFCopyLocalizedStringFromTableInBundle( message, currCommand.localizationTableName, localizationBundle, "") );

					StSwitchToFront switcher;
					currCommand.chooseObjectPath = CreateCFURLFromOpenDialog( dynamicCommandName, message, defaultName, defaultLocationStr, additionalFlags | kOMCFilePanelCanChooseFiles | kOMCFilePanelCanChooseDirectories);	
					if(currCommand.chooseObjectPath == NULL)
						throw OSStatus(userCanceledErr);
					
					if( (additionalFlags & kOMCFilePanelUseCachedPath) != 0 )
						mCachedChooseObjectPath.Adopt( currCommand.chooseObjectPath, kCFObjRetain );
				}
				else
				{
					currCommand.chooseObjectPath = mCachedChooseObjectPath;
					CFRetain(currCommand.chooseObjectPath);//will be released
				}
			}

			if( objListEmpty || mIsTextContext )//text context
			{
				TRACE_CSTR("OnMyCommandCM->CMPluginHandleSelection: about to process command with text selection\n" );
				ProcessCommandWithText( currCommand, mContextText );
			}
			else //file context
			{
				TRACE_CSTR("OnMyCommandCM About to proces file list\n" );
				ProcessObjects();
			}
			
			//we used to do some post-processing here but now most commands are async so we need to call Finalize when task ends
		}
		else
		{
			LOG_CSTR( "OMC->CMPluginHandleSelection: unknown menu item ID. Aliens?\n" );
		}

		TRACE_CSTR("OnMyCommandCM->CMPluginHandleSelection: finished successfully\n" );
	}
	catch(OSStatus &thrownError)
	{
		if(thrownError == userCanceledErr)
		{
			mError = userCanceledErr;
			TRACE_CSTR("OnMyCommandCM->CMPluginHandleSelection: user cancelled\n" );
		}
	}
	catch(...)
	{
		LOG_CSTR( "OMC->CMPluginHandleSelection: unknown error ocurred\n" );
		mError = -1;
	}

	//balance the retain made at the beginning of this function
	Release();

	return noErr;
}

void
OnMyCommandCM::PostMenuCleanup()
{
	TRACE_CSTR( "OnMyCommandCM::PostMenuCleanup\n" );
//	Release(); //nothing to do - this used to balance Retain() in context check but it is not there anymore
}


/*
//called when the task finishes (possibly asynchronously)
void
OnMyCommandCM::Finalize()
{
	TRACE_CSTR( "OnMyCommandCM::Finalize\n" );

	//all things called below are optional things called when commad succeeds
	// (this is not a claeanup method)
	// so if there was an error or user canceled, we don't want to perform any of those

	if( mError != noErr)
		return;

	TRACE_CSTR( "OnMyCommandCM::Finalize: About to refresh objects in Finder\n" );
	//we refresh objects in Finder at the very last moment so the files which are supposed to be created are indeed created
	
}
*/

void
OnMyCommandCM::SwapContext(OMCContextData &ioContextData)
{
	this->mContextFiles.Swap(ioContextData.mContextFiles);
	this->mContextText.Swap(ioContextData.mContextText);
	this->mObjectList.swap(ioContextData.mObjectList);
	this->mCommonParentPath.Swap(ioContextData.mCommonParentPath);
	
	CFIndex temp = this->mCurrObjectIndex;
	this->mCurrObjectIndex = ioContextData.mCurrObjectIndex;
	ioContextData.mCurrObjectIndex = temp;

	Boolean tempBool = this->mIsNullContext;
	this->mIsNullContext = ioContextData.mIsNullContext;
	ioContextData.mIsNullContext = tempBool;

	tempBool = this->mIsTextContext;
	this->mIsTextContext = ioContextData.mIsTextContext;
	ioContextData.mIsTextContext = tempBool;
}

/*
void
OnMyCommandCM::ResetContextData()
{
	DeleteObjectList();
	
	mContextFiles.Release();
	mContextText.Release();
	mCommonParentPath.Release();
	mInputText.Release();
	mCachedSaveAsPath.Release();
	mCachedChooseFilePath.Release();
	mCachedChooseFolderPath.Release();
	mCachedChooseObjectPath.Release();
	mNibControlValues.Release();
	mNibControlCustomProperties.Release();

	mError = noErr;
}
*/

CFTypeRef
OnMyCommandCM::GetCFContext()
{
	if( mObjectList.size() > 0 )
	{
		if(mContextFiles == NULL)
		{
			mContextFiles.Adopt(
				::CFArrayCreateMutable(kCFAllocatorDefault, mObjectList.size(), &kCFTypeArrayCallBacks),
				kCFObjDontRetain );
			
			if(mContextFiles != NULL)
			{	
				for(size_t i = 0; i < mObjectList.size(); i++)
				{
					CFObj<CFURLRef> urlRef( ::CFURLCreateFromFSRef(kCFAllocatorDefault, &(mObjectList[i].mRef)) );
					::CFArrayAppendValue( mContextFiles, (CFURLRef)urlRef );
				}
			}
		}

		return (CFMutableArrayRef)mContextFiles;
	}
	else if(mContextText != NULL)
	{
		return (CFStringRef)mContextText;
	}

	return NULL;
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

			if(mCommandList[i].saveAsPath != NULL)
				::CFRelease(mCommandList[i].saveAsPath);

			if(mCommandList[i].chooseFilePath != NULL)
				::CFRelease(mCommandList[i].chooseFilePath);

			if(mCommandList[i].chooseFolderPath != NULL)
				::CFRelease(mCommandList[i].chooseFolderPath);

			if(mCommandList[i].chooseObjectPath != NULL)
				::CFRelease(mCommandList[i].chooseObjectPath);

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
		
			delete mCommandList[i].currState;
			
		}

		delete [] mCommandList;
		mCommandList = NULL;
	}
	mCommandCount = 0;
}

void
OnMyCommandCM::DeleteObjectList()
{
    for(CFIndex i = 0; i < mObjectList.size(); i++)
    {
        OneObjProperties& oneObj = mObjectList[i];
        
        if( oneObj.mURLRef != NULL )
        {
            ::CFRelease( oneObj.mURLRef );
        }
        
        if( oneObj.mExtension != NULL )
        {
            ::CFRelease( oneObj.mExtension );
        }
        
        if( oneObj.mRefreshPath != NULL )
        {
            ::CFRelease( oneObj.mRefreshPath );
        }
    }
    mObjectList.clear();
	mCurrObjectIndex = 0;
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

//static
OSStatus
OnMyCommandCM::FSRefCheckFileOrFolder(const FSRef *inRef, void *ioData)
{
	if( (inRef == NULL) || (ioData == NULL) )
		return paramErr;

#if (_TRACE_ == 1)
	{
		TRACE_CSTR("OnMyCommandCM::FSRefCheckFileOrFolder: One file: \n");
		CFObj<CFURLRef> dbgURL( ::CFURLCreateFromFSRef( kCFAllocatorDefault, inRef) );
		CFObj<CFStringRef> dbgPath( ::CFURLCopyFileSystemPath( dbgURL, kCFURLPOSIXPathStyle) );
		TRACE_CFSTR( (CFStringRef)dbgPath );
	}
#endif //_TRACE_

	OnMyCommandCM *myData = (OnMyCommandCM *)ioData;

	if(myData->mObjectList.size() == 0)
		return paramErr;

//we are interested in real files or folders
//sometimes we get FSRef not valid (InternetExplorer)
	FSCatalogInfo theInfo;
	memset(&theInfo, 0, sizeof(theInfo));
	OSErr err = ::FSGetCatalogInfo(inRef, kFSCatInfoNodeFlags, &theInfo, NULL, NULL, NULL);
	if ( err == noErr )
	{//it is a file or folder. we can safely proceed
		LSItemInfoRecord itemInfo;
		memset(&itemInfo, 0, sizeof(itemInfo));
		LSRequestedInfo whichInfo = kLSRequestExtension | kLSRequestTypeCreator | kLSRequestBasicFlagsOnly | kLSRequestExtensionFlagsOnly;
		err = ::LSCopyItemInfoForRef( inRef, whichInfo, &itemInfo);
		if( err == noErr )
		{
			if( myData->mCurrObjectIndex < myData->mObjectList.size() )
			{
				OneObjProperties& objProperties = myData->mObjectList[myData->mCurrObjectIndex];
				
				objProperties.mRef = *inRef;
				objProperties.mExtension  = itemInfo.extension;
				objProperties.mType = itemInfo.filetype;
				objProperties.mFlags = itemInfo.flags;
				objProperties.mRefreshPath = NULL;
				
				myData->mCurrObjectIndex++; //client will use thins information know the exact number of valid items
			}
			else if(itemInfo.extension != NULL)
			{
				::CFRelease(itemInfo.extension);
			}
		}
	}
	
	return err;
}

//static
OSStatus
OnMyCommandCM::CFURLCheckFileOrFolder(CFURLRef inURLRef, void *ioData)
{
	if( (inURLRef == NULL) || (ioData == NULL) )
		return paramErr;

	OnMyCommandCM *myData = (OnMyCommandCM *)ioData;

	if(myData->mObjectList.size() == 0)
		return paramErr;

	FSRef oneRef;
	Boolean isOK = ::CFURLGetFSRef(inURLRef, &oneRef);
	if(isOK && (myData->mCurrObjectIndex < myData->mObjectList.size()) )
	{
		OneObjProperties& objProperties = myData->mObjectList[myData->mCurrObjectIndex];
		if(objProperties.mURLRef != nullptr)
			CFRelease(objProperties.mURLRef);
		objProperties.mURLRef = inURLRef;
		::CFRetain(objProperties.mURLRef);
		
		return FSRefCheckFileOrFolder(&oneRef, ioData);
	}
	return fnfErr;
}

OSStatus
OnMyCommandCM::ProcessObjects()
{
	if( (mCommandList == NULL) || (mCommandCount == 0) || (mObjectList.size() == 0) )
		return noErr;

	if( mCurrCommandIndex >= mCommandCount)
		return paramErr;

	CommandDescription &currCommand = mCommandList[mCurrCommandIndex];
	CFBundleRef externBundle = GetCurrentCommandExternBundle();
	CFBundleRef localizationBundle = NULL;
	if(currCommand.localizationTableName != NULL)//client wants to be localized
	{
		localizationBundle = externBundle;
		if(localizationBundle == NULL)
			localizationBundle = CFBundleGetMainBundle();
	}

	TRACE_CSTR("OnMyCommandCM. ProcessObjects\n" );
	
	CFObj<CFStringRef> dynamicCommandName( CreateDynamicCommandName(currCommand, currCommand.localizationTableName, localizationBundle) );

	CFIndex objectCount = mObjectList.size();
	if( currCommand.multipleObjectProcessing == kMulObjProcessTogether )
		objectCount = 1;

	CFIndex maxTaskCount = currCommand.maxTaskCount;
	if( maxTaskCount <= 0 )//max task count not specified explicitly, use reasonable default value
	{
		if(objectCount > 1)
		{
			host_basic_info *hostInfo = GetHostBasicInfo();
			if( hostInfo != NULL)
				maxTaskCount = (2 * hostInfo->avail_cpus /*logical_cpu*/);
		}
		else
			maxTaskCount = 1;//don't care becuase we will have only one task
	}

	OmcHostTaskManager *taskManager = new OmcHostTaskManager( this, currCommand, dynamicCommandName, mBundleRef, maxTaskCount );
	
	if( currCommand.refresh != NULL )
	{//refreshing needed - compose array of paths before performing any action
		for(CFIndex i = 0; i < mObjectList.size(); i++)
		{	
			TRACE_CSTR("OnMyCommandCM. create refresh path\n" );
			mCurrObjectIndex = i;
			CFObj<CFMutableStringRef> onePath( CreateCombinedStringWithObjects(currCommand.refresh, NULL, NULL) );
			mObjectList[i].mRefreshPath = CreatePathByExpandingTilde( onePath );//we own the string
		}
	}

	for(CFIndex i = 0; i < objectCount; i++)
	{
		if( currCommand.multipleObjectProcessing == kMulObjProcessTogether )
			mCurrObjectIndex = -1;//invalid index means process them all together
		else
			mCurrObjectIndex = i;

		CFObj<CFMutableStringRef> theCommand( CreateCommandStringWithObjects(currCommand.command, currCommand.escapeSpecialCharsMode) );

		if(theCommand == NULL)
			return memFullErr;

		CFObj<CFMutableStringRef> inputPipe( CreateCommandStringWithObjects(currCommand.inputPipe, kEscapeNone) );
		CFObj<CFDictionaryRef> environList( CreateEnvironmentVariablesDict(NULL) );

		ARefCountedObj<OmcExecutor> theExec;
		CFObj<CFStringRef> objName( CreateObjName( &(mObjectList[i]), NULL) );
	
		switch(currCommand.executionMode)
		{
			case kExecTerminal:
				ExecuteInTerminal( theCommand, currCommand.openNewTerminalSession, currCommand.bringTerminalToFront);
			break;
			
			case kExecITerm:
				ExecuteInITerm( theCommand, currCommand.iTermShellPath, currCommand.openNewTerminalSession, currCommand.bringTerminalToFront);
			break;

			case kExecSilentPOpen:
				theExec.Adopt( new POpenExecutor(currCommand, mBundleRef, environList) );
			break;
			
			case kExecSilentSystem:
				theExec.Adopt( new SystemExecutor(mBundleRef, currCommand.useDeputy) );
			break;
			
			case kExecPOpenWithOutputWindow:
				theExec.Adopt( new POpenWithOutputExecutor(currCommand, dynamicCommandName, mBundleRef, externBundle, environList) );
			break;
			
			case kExecAppleScript:
				theExec.Adopt( new AppleScriptExecutor(currCommand, NULL, mBundleRef, externBundle, false) );
			break;
			
			case kExecAppleScriptWithOutputWindow:
				theExec.Adopt( new AppleScriptExecutor(currCommand, dynamicCommandName, mBundleRef, externBundle, true) );
			break;
			
			case kExecShellScript:
				theExec.Adopt( new ShellScriptExecutor(currCommand, mBundleRef, environList) );
			break;
			
			case kExecShellScriptWithOutputWindow:
				theExec.Adopt( new ShellScriptWithOutputExecutor(currCommand, dynamicCommandName, mBundleRef, externBundle, environList) );
			break;
		}
		
		if(theExec != NULL)
		{
			taskManager->AddTask( theExec, theCommand, inputPipe, objName );//retains theExec
		}
	}

	if( (currCommand.currState != NULL) && (currCommand.currState->dialogGUID != NULL) )
	{
		OMCDialog *activeDialog = OMCDialog::FindDialogByGUID(currCommand.currState->dialogGUID);
		if(activeDialog != NULL)
			taskManager->AddObserver( activeDialog->GetObserver() );
	}
	if(mObserver != NULL)
		taskManager->AddObserver( mObserver );

	taskManager->Start();

	return noErr;
}


OSStatus
OnMyCommandCM::ProcessCommandWithText(const CommandDescription &currCommand, CFStringRef inStrRef)
{
	CFObj<CFMutableStringRef> theCommand( CreateCommandStringWithText(currCommand.command, inStrRef, currCommand.escapeSpecialCharsMode) );
	
	if(theCommand == NULL)
		return memFullErr;

	CFBundleRef externBundle = GetCurrentCommandExternBundle();
	CFBundleRef localizationBundle = NULL;
	if(currCommand.localizationTableName != NULL)//client wants to be localized
	{
		localizationBundle = externBundle;
		if(localizationBundle == NULL)
			localizationBundle = CFBundleGetMainBundle();
	}

	CFObj<CFMutableStringRef> inputPipe( CreateCommandStringWithText(currCommand.inputPipe, inStrRef, kEscapeNone) );
	CFObj<CFDictionaryRef> environList( CreateEnvironmentVariablesDict(inStrRef) );

	CFObj<CFStringRef> dynamicCommandName( CreateDynamicCommandName(currCommand, currCommand.localizationTableName, localizationBundle) );
	CFObj<CFStringRef> objName; //what should the object name be for text?

	CFIndex maxTaskCount = 1;//text command processes one task anyway
	OmcHostTaskManager *taskManager = new OmcHostTaskManager( this, currCommand, dynamicCommandName, mBundleRef, maxTaskCount );

	ARefCountedObj<OmcExecutor> theExec;
	

	switch(currCommand.executionMode)
	{
		case kExecTerminal:
			ExecuteInTerminal( theCommand, currCommand.openNewTerminalSession, currCommand.bringTerminalToFront );
		break;
		
		case kExecITerm:
			ExecuteInITerm( theCommand, currCommand.iTermShellPath, currCommand.openNewTerminalSession, currCommand.bringTerminalToFront );
		break;

		case kExecSilentPOpen:
			theExec.Adopt( new POpenExecutor(currCommand, mBundleRef, environList) );
		break;
		
		case kExecSilentSystem:
			theExec.Adopt( new SystemExecutor(mBundleRef, currCommand.useDeputy) );
		break;
		
		case kExecPOpenWithOutputWindow:
			theExec.Adopt( new POpenWithOutputExecutor(currCommand, dynamicCommandName, mBundleRef, externBundle, environList) );
		break;

		case kExecAppleScript:
			theExec.Adopt( new AppleScriptExecutor(currCommand, NULL, mBundleRef, externBundle, false) );
		break;
		
		case kExecAppleScriptWithOutputWindow:
			theExec.Adopt( new AppleScriptExecutor(currCommand, dynamicCommandName, mBundleRef, externBundle, true) );
		break;
		
		case kExecShellScript:
			theExec.Adopt( new ShellScriptExecutor(currCommand, mBundleRef, environList) );
		break;
		
		case kExecShellScriptWithOutputWindow:
			theExec.Adopt( new ShellScriptWithOutputExecutor(currCommand, dynamicCommandName, mBundleRef, externBundle, environList) );
		break;
	}
	
	if(theExec != NULL)
	{
		taskManager->AddTask( theExec, theCommand, inputPipe, objName );//retains theExec
	}

	if( (currCommand.currState != NULL) && (currCommand.currState->dialogGUID != NULL) )
	{
		OMCDialog *activeDialog = OMCDialog::FindDialogByGUID(currCommand.currState->dialogGUID);
		if(activeDialog != NULL)
			taskManager->AddObserver( activeDialog->GetObserver() );
	}

	if(mObserver != NULL)
		taskManager->AddObserver( mObserver );

	taskManager->Start();

	return noErr;
}

void
ExecuteInTerminal(CFStringRef inCommand, bool openInNewWindow, bool bringToFront)
{
	if(inCommand == NULL)
		return;

//	FourCharCode termAppSig = 'trmx';
	
	OSStatus err = noErr;
	StAEDesc theCommandDesc;

	//Send UTF-16 text
	err = CMUtils::CreateUniTextDescFromCFString(inCommand, theCommandDesc);

	if(err != noErr)
		return;

	SInt32 sysVersion;
	::Gestalt(gestaltSystemVersion, &sysVersion);
	

	err = SendEventToTerminal(theCommandDesc, sysVersion, openInNewWindow, bringToFront);

	if(err == noErr)
		return;//sucess situation - we may exit now

	//terminal not running probably
	TRACE_CSTR("\tExecuteInTerminal. Trying to launch the application with LS\n" );
	FSRef appRef;
	err = ::LSFindApplicationForInfo(kLSUnknownCreator, CFSTR(kTerminalAppBundleID), CFSTR("Terminal.app"), &appRef, NULL);

	if(err != noErr)
	{
		LOG_CSTR( "OMC->ExecuteInTerminal. Could not find Terminal application. We give up now.\n" );
		return;
	}

	LSLaunchFSRefSpec launchParams;
	launchParams.appRef = &appRef;
	launchParams.numDocs = 0;
	launchParams.itemRefs = NULL;
	launchParams.passThruParams = NULL;//appleEvent;
	launchParams.launchFlags = kLSLaunchDefaults;
	launchParams.asyncRefCon = NULL;
	err = ::LSOpenFromRefSpec( &launchParams, NULL);

	if(err == noErr)
	{//Terminal is launching right now.
	//We cannot send an event to it right away because it is not ready yet
	//We cannot install a launch notify handler because we do not know if our host will be happy about this
	//Installing a deferred task is too much work :-) so we go the easy way:
	//we will wait one second and send event. We will try 10 times every one second to give plenty of time for the app to launch

		for(int i = 1; i <= 10; i++)
		{//we only try 10 times and then give up
			::Delay(60, NULL); //wait 1 second before trying to send the event

			err = SendEventToTerminal(theCommandDesc, sysVersion, false, bringToFront);//after terminal launch a new window is open so never open another one
			
			if( (err == connectionInvalid) || (err == procNotFound) )
			{
				TRACE_CSTR("\tExecuteInTerminal. App still launching. Waiting...\n" );
				continue;
			}
			else 
				break;//either err == noErr (success), or some other error so we exit anyway
		}
		
		if(err != noErr)
		{
			LOG_CSTR( "OMC->ExecuteInTerminal. Event could not be sent to launched application, err = %d\n", (int)err );
		}
	}
	else
	{
		LOG_CSTR( "OMC->ExecuteInTerminal. LSOpenFromRefSpec failed, err = %d\n", (int)err );
	}
	
}

OSErr
SendEventToTerminal(const AEDesc &inCommandDesc, SInt32 sysVersion, bool openInNewWindow, bool bringToFront)
{
	OSErr err = noErr;
	AEKeyword theKeyword = (sysVersion >= 0x1020) ? keyDirectObject : 'cmnd';//Terminal in Mac OS 10.1.x needs different event

	if(sysVersion < 0x1020)
		openInNewWindow = true;//old Terminal does no support execution in specified window

	if( openInNewWindow )
	{
        err = CMUtils::SendAEWithObjToRunningApp( kTerminalAppBundleID, kAECoreSuite, kAEDoScript, theKeyword, inCommandDesc );
	}
	else
	{
		//find front window
		StAEDesc theFrontWindow;
        err = MoreAETellBundledAppToGetElementAt(
										kTerminalAppBundleID,
										cWindow,
										kAEFirst,
										typeWildCard,
										theFrontWindow);
		if(err == noErr)
		{
			/*
			StAEDesc theFrontWindowDesc;
			StAEDesc nullDescRec;
			StAEDesc positionDesc;
			long thePosition = 1; //window number one is the topmost window
			err = ::AECreateDesc( typeLongInteger, &thePosition,
									sizeof(thePosition), positionDesc);
				
			if(err == noErr)
			{
				err = ::CreateObjSpecifier( cWindow, nullDescRec, 
											formAbsolutePosition, positionDesc, false,  theFrontWindowDesc );
			}
			*/
            err = CMUtils::SendAEWithTwoObjToRunningApp( kTerminalAppBundleID, kAECoreSuite, kAEDoScript, theKeyword, inCommandDesc, keyAEFile, theFrontWindow/*Desc*/ );
		}
			
		if( (err != noErr) && (err != connectionInvalid) && (err != procNotFound) )
		{//if for any reason the event cannot be sent to topmost window, try opening new window
            err = CMUtils::SendAEWithObjToRunningApp( kTerminalAppBundleID, kAECoreSuite, kAEDoScript, theKeyword, inCommandDesc );
		}
	}

	if( (err == noErr) && bringToFront)
	{
		StAEDesc fakeDesc;
        err = CMUtils::SendAEWithObjToRunningApp( kTerminalAppBundleID, kAEMiscStandards, kAEActivate, 0, fakeDesc);
	}

	return err;
}


void
ExecuteInITerm(CFStringRef inCommand, CFStringRef inShellPath, bool openInNewWindow, bool bringToFront)
{
	if(inCommand == NULL)
		return;
	
	OSStatus err = noErr;
	StAEDesc theCommandDesc;

	err = CMUtils::CreateUniTextDescFromCFString(inCommand, theCommandDesc);

	if(err != noErr)
		return;

	SInt32 sysVersion;
	::Gestalt(gestaltSystemVersion, &sysVersion);
	

	err = SendEventToITerm(theCommandDesc, inShellPath, sysVersion, openInNewWindow, bringToFront, false);

	if(err == noErr)
		return;//sucess situation - we may exit now

	//terminal not running probably
	TRACE_CSTR("\tExecuteInITerm. Trying to launch the application with LS\n" );
	FSRef appRef;
	err = ::LSFindApplicationForInfo(kITermAppSig, NULL, CFSTR("iTerm.app"), &appRef, NULL);

	if(err != noErr)
	{
		TRACE_CSTR("\tExecuteInITerm. Could not find iTerm application. We give up now.\n" );
		return;
	}

	LSLaunchFSRefSpec launchParams;
	launchParams.appRef = &appRef;
	launchParams.numDocs = 0;
	launchParams.itemRefs = NULL;
	launchParams.passThruParams = NULL;//appleEvent;
	launchParams.launchFlags = kLSLaunchDefaults;
	launchParams.asyncRefCon = NULL;
	err = ::LSOpenFromRefSpec( &launchParams, NULL);

	if(err == noErr)
	{//iTerm is launching right now.
	//We cannot send an event to it right away because it is not ready yet
	//We cannot install a launch notify handler because we do not know if our host will be happy about this
	//Installing a deferred task is too much work :-) so we go the easy way:
	//we will wait one second and send event. We will try 10 times every one second to give plenty of time for the app to launch

		for(int i = 1; i <= 10; i++)
		{//we only try 10 times and then give up
			::Delay(60, NULL); //wait 1 second before trying to send the event

			StAEDesc fakeDesc;
			err = CMUtils::SendAEWithObjToRunningApp( kITermAppSig, kAEMiscStandards, kAEActivate, 0, fakeDesc);
			
			if( (err == connectionInvalid) || (err == procNotFound) )
			{
				TRACE_CSTR("\tExecuteInITerm. App still launching. Waiting...\n" );
				continue;
			}
			else if(err == noErr)
			{
				err = SendEventToITerm(theCommandDesc, inShellPath, sysVersion, false, bringToFront, true);//after terminal launch a new window is open so never open another one
				break;//either err == noErr (success), or some other error so we exit anyway
			}
		}
		
		if(err != noErr)
		{
			LOG_CSTR( "OMC->ExecuteInITerm. Event could not be sent to launched application, err = %d\n", (int)err );
		}
	}
	else
	{
		LOG_CSTR( "OMC->ExecuteInITerm. LSOpenFromRefSpec failed, err = %d\n", (int)err );
	}
	
}

OSErr
SendEventToITerm(const AEDesc &inCommandDesc, CFStringRef inShellPath, SInt32 sysVersion, bool openInNewWindow, bool bringToFront, bool justLaunching)
{
#pragma unused (sysVersion)

	const AEEventClass kITermSuite = 'ITRM';
	OSErr err = -1;
	
	StAEDesc termDesc;
	StAEDesc sessionDesc;
	bool hasTerm = false;
	bool tryNewSession = true;

    err = MoreAETellAppToGetAEDesc(	kITermAppSig,
									'Ctrm',
									typeWildCard,
									termDesc);
	hasTerm = (err == noErr);//current terminal exists

	if(hasTerm && (openInNewWindow == false))
	{
        err = MoreAETellAppObjectToGetAEDesc( kITermAppSig,
								termDesc,
								'Cssn',
								typeWildCard,
								sessionDesc);
		if(err == noErr)
		{//current session exists
            err = CMUtils::SendAEWithTwoObjToRunningApp( kITermAppSig, kITermSuite, 'Wrte', keyDirectObject, sessionDesc, 'iTxt', inCommandDesc );
			tryNewSession = (err != noErr);//don't try opening new session if this calls succeeds
		}
	}
	
	if(tryNewSession)
	{
		if(hasTerm == false)
		{
            err = MoreAETellAppToCreateNewElementIn(
										kITermAppSig,
										'Ptrm',
										NULL,
										NULL,
										typeWildCard,
										termDesc);
										
			hasTerm = (err == noErr);
		}
		
		if(hasTerm)
		{
            err = MoreAETellAppObjToInsertNewElement(
											kITermAppSig,
											termDesc,
											'Pssn',
											'Pssn',
											NULL,
											kAEAfter,
											typeWildCard,
											sessionDesc);
										
			StAEDesc shellDesc;
			if(inShellPath == NULL)
				inShellPath = CFSTR("/bin/tcsh");
			err = CMUtils::CreateUniTextDescFromCFString( inShellPath, shellDesc );
			if(err == noErr)
			{
                err = CMUtils::SendAEWithTwoObjToRunningApp( kITermAppSig, kITermSuite, 'Exec', keyDirectObject, sessionDesc, 'Cmnd', shellDesc );
                err = CMUtils::SendAEWithTwoObjToRunningApp( kITermAppSig, kITermSuite, 'Wrte', keyDirectObject, sessionDesc, 'iTxt', inCommandDesc );
			}
		}
	}

	if( (justLaunching == false) && (err == noErr) && bringToFront)
	{
		StAEDesc fakeDesc;
		err = CMUtils::SendAEWithObjToRunningApp( kITermAppSig, kAEMiscStandards, kAEActivate, 0, fakeDesc);
	}


	return err;
}

#pragma mark -

//true - OK to proceed
//false - do not execute

//there are 2 levels for execute & cancel buttons strings:
//1. defined in command itself
//2. if still null, get localized default

Boolean
OnMyCommandCM::DisplayWarning( CommandDescription &currCommand )
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
	
	CFObj<CFStringRef> dynamicCommandName( CreateDynamicCommandName(currCommand, currCommand.localizationTableName, localizationBundle) );
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

//optimization - called early to check if password or clipboard will be used 
void
OnMyCommandCM::PrescanCommandDescription( CommandDescription &currCommand )
{
	if( currCommand.isPrescanned )
		return;

//	TRACE_CSTR("OnMyCommandCM->PrescanCommandDescription\n" );
	if( currCommand.command != NULL )
		PrescanArrayOfObjects( currCommand, currCommand.command );

	if( currCommand.inputPipe != NULL )
		PrescanArrayOfObjects( currCommand, currCommand.inputPipe );
}

void
OnMyCommandCM::PrescanArrayOfObjects( CommandDescription &currCommand, CFArrayRef inObjects )
{
	ACFArr objects(inObjects);
	CFIndex theCount = objects.GetCount();
	CFStringRef fragmentRef;

	for(CFIndex i = 0; i < theCount; i++ )
	{
		if( objects.GetValueAtIndex(i, fragmentRef) )
		{
			SInt32 specialWordID = GetSpecialWordID(fragmentRef);
			if(specialWordID == NO_SPECIAL_WORD)
				FindEnvironmentVariables(currCommand, fragmentRef);
			else
				ProcessOnePrescannedWord(currCommand, specialWordID, fragmentRef, false);
		}
	}
	currCommand.isPrescanned = true;
}

void
OnMyCommandCM::ProcessOnePrescannedWord(CommandDescription &currCommand, SInt32 specialWordID, CFStringRef inSpecialWord, bool isEnvironVariable)
{
	switch(specialWordID)
	{
		case NO_SPECIAL_WORD:
//					TRACE_CSTR("NO_SPECIAL_WORD\n" );
			
		break;
		
		case OBJ_TEXT:
//					TRACE_CSTR("OBJ_TEXT\n" );
			currCommand.prescannedCommandInfo |= kOmcCommandContainsTextObject;
		break;
		
		case OBJ_PATH:
		case OBJ_PATH_NO_EXTENSION://deprecated
		case OBJ_PARENT_PATH:
		case OBJ_NAME:
		case OBJ_NAME_NO_EXTENSION:
		case OBJ_EXTENSION_ONLY:
		case OBJ_DISPLAY_NAME:
		case OBJ_COMMON_PARENT_PATH:
		case OBJ_PATH_RELATIVE_TO_COMMON_PARENT:
//					TRACE_CSTR("OBJ_PATH\n" );
			currCommand.prescannedCommandInfo |= kOmcCommandContainsFileObject;
		break;
		
		case DLG_INPUT_TEXT:
//					TRACE_CSTR("DLG_INPUT_TEXT\n" );
			currCommand.prescannedCommandInfo |= kOmcCommandContainsInputText;
		break;
		
		case DLG_SAVE_AS_PATH:
		case DLG_SAVE_AS_PARENT_PATH:
		case DLG_SAVE_AS_NAME:
		case DLG_SAVE_AS_NAME_NO_EXTENSION:
		case DLG_SAVE_AS_EXTENSION_ONLY:
//					TRACE_CSTR("DLG_SAVE_AS_PATH\n" );
			currCommand.prescannedCommandInfo |= kOmcCommandContainsSaveAsDialog;
		break;

		case DLG_CHOOSE_FILE_PATH:
		case DLG_CHOOSE_FILE_PARENT_PATH:
		case DLG_CHOOSE_FILE_NAME:
		case DLG_CHOOSE_FILE_NAME_NO_EXTENSION:
		case DLG_CHOOSE_FILE_EXTENSION_ONLY:
//					TRACE_CSTR("DLG_CHOOSE_FILE_PATH\n" );
			currCommand.prescannedCommandInfo |= kOmcCommandContainsChooseFileDialog;
		break;
		
		case DLG_CHOOSE_FOLDER_PATH:
		case DLG_CHOOSE_FOLDER_PARENT_PATH:
		case DLG_CHOOSE_FOLDER_NAME:
		case DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION:
		case DLG_CHOOSE_FOLDER_EXTENSION_ONLY:
//					TRACE_CSTR("DLG_CHOOSE_FOLDER_PATH\n" );
			currCommand.prescannedCommandInfo |= kOmcCommandContainsChooseFolderDialog;
		break;
		
		case DLG_CHOOSE_OBJECT_PATH:
		case DLG_CHOOSE_OBJECT_PARENT_PATH:
		case DLG_CHOOSE_OBJECT_NAME:
		case DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION:
		case DLG_CHOOSE_OBJECT_EXTENSION_ONLY:
//					TRACE_CSTR("DLG_CHOOSE_OBJECT_PATH\n" );
			currCommand.prescannedCommandInfo |= kOmcCommandContainsChooseObjectDialog;
		break;
		
		case DLG_PASSWORD:
//					TRACE_CSTR("DLG_PASSWORD\n" );
			currCommand.inputDialogType = kInputPasswordText;
			currCommand.prescannedCommandInfo |= kOmcCommandContainsInputText;
		break;
		
		case NIB_DLG_CONTROL_VALUE:
		{
//					TRACE_CSTR("NIB_DLG_CONTROL_VALUE\n" );
								
			SInt32 columnIndex = 0;
			CFObj<CFStringRef> controlID( CreateControlIDFromString(inSpecialWord, isEnvironVariable) );
			InitNibControlValueEntry(controlID, columnIndex);
		}
		break;

		case NIB_TABLE_VALUE:
		case NIB_TABLE_ALL_ROWS:
		{
//			TRACE_CSTR("NIB_TABLE_VALUE\n" );
			CFIndex columnIndex = 0;
			CFObj<CFStringRef> controlID( CreateTableIDAndColumnFromString(inSpecialWord, columnIndex, specialWordID == NIB_TABLE_ALL_ROWS, isEnvironVariable), kCFObjDontRetain );
			if( specialWordID == NIB_TABLE_ALL_ROWS )
			{
				 //saved as unique value in the dictionary
				CFObj<CFStringRef> newControlID( CreateControlIDByAddingModifiers(controlID, kControlModifier_AllRows) );
                controlID.Swap(newControlID);
			}
            InitNibControlValueEntry(controlID, columnIndex);
		}
		break;
	}
}

void
OnMyCommandCM::FindEnvironmentVariables(CommandDescription &currCommand, CFStringRef inString)
{
	if(inString == NULL)
		return;

	CFIndex theLen = ::CFStringGetLength(inString);
	if( theLen < (kMinSpecialWordLen+1) )
		return;

	CFStringInlineBuffer inlineBuff;
	::CFStringInitInlineBuffer( inString, &inlineBuff, CFRangeMake(0, theLen) );

	CFIndex i = 0;
	UniChar oneChar = 0;

	while( i < theLen )
	{
		oneChar = ::CFStringGetCharacterFromInlineBuffer( &inlineBuff, i );
		i++;
		if( (oneChar == '$') && ((i+kMinSpecialWordLen) < theLen) )
		{//may be environment variable - take a look at it, it must be in form of $OMC_XXX
			oneChar = ::CFStringGetCharacterFromInlineBuffer( &inlineBuff, i );
			if(oneChar == '{') //we allow the form of ${OMC_XXX}
				i++;

			if( (::CFStringGetCharacterFromInlineBuffer( &inlineBuff, i ) == 'O') &&
				(::CFStringGetCharacterFromInlineBuffer( &inlineBuff, i+1 ) == 'M') &&
				(::CFStringGetCharacterFromInlineBuffer( &inlineBuff, i+2 ) == 'C') &&
				(::CFStringGetCharacterFromInlineBuffer( &inlineBuff, i+3 ) == '_') )
			{
				CFIndex varStartOffset = i;
				CFIndex varLen = 4;
				i += 4;//skip "OMC_"
				while(i < theLen)
				{
					oneChar = CFStringGetCharacterFromInlineBuffer( &inlineBuff, i );
					i++;
					if( ((oneChar >= 'A') && (oneChar <= 'Z')) || (oneChar == '_') || ((oneChar >= '0') && (oneChar <= '9')) )
					{
						varLen++;
					}
					else
					{
						i--;//something else happened. we will want to re-read this character when we return to main loop
						break;
					}
				}
				
				if( (varLen >= kMinSpecialWordLen) && (varLen <= kMaxSpecialWordLen) )
				{
					CFObj<CFStringRef> varString( ::CFStringCreateWithSubstring(kCFAllocatorDefault, inString, CFRangeMake(varStartOffset,varLen)) );
					SInt32 specialWordID = GetSpecialEnvironWordID(varString);
					if( specialWordID != NO_SPECIAL_WORD )
					{
						ProcessOnePrescannedWord(currCommand, specialWordID, varString, true);
						
						if(currCommand.customEnvironVariables == NULL) 
							currCommand.customEnvironVariables = ::CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
						::CFDictionarySetValue(currCommand.customEnvironVariables, (CFStringRef)varString, CFSTR(""));
					}
				}
			}
		}
	}
}

void
OnMyCommandCM::ScanDynamicName( CommandDescription &currCommand )
{
	if( currCommand.name == NULL )
		return;

//	TRACE_CSTR("OnMyCommandCM->ScanDynamicName\n" );

	ACFArr command(currCommand.name);
	CFIndex theCount = command.GetCount();
	CFStringRef fragmentRef;

	for(CFIndex i = 0; i < theCount; i++ )
	{
		if( command.GetValueAtIndex(i, fragmentRef) )
		{
			SInt32 specialWordID = GetSpecialWordID(fragmentRef);
			switch(specialWordID)
			{
				case NO_SPECIAL_WORD:
				break;
				
				case OBJ_TEXT:
					currCommand.nameContainsText = true;
				break;
			}
		}
	}
	
}

//the code is generic to handle both simple controls and tables
//regular controls do not have columns and the use 0 for column number to store their values
//column index 0 is a meta value for table and means: get array of all column values (for selected row)
//this way a regular method of querrying controls works with table too: produces a selected row strings

void
OnMyCommandCM::InitNibControlValueEntry(CFStringRef inControlID, CFIndex columnIndex)
{
	if(inControlID == NULL)
		return;

	if(mNibControlValues == NULL)
	{
		mNibControlValues.Adopt( ::CFDictionaryCreateMutable(
							kCFAllocatorDefault,
							0,
							&kCFTypeDictionaryKeyCallBacks,//keyCallBacks,
							&kCFTypeDictionaryValueCallBacks ), kCFObjDontRetain);//values will be CFDictionaryRefs
	}

	if(mNibControlValues != NULL)
	{
		CFTypeRef resultValue = NULL;
		Boolean valuePresent = ::CFDictionaryGetValueIfPresent(
										mNibControlValues,
										inControlID,
										(const void **)&resultValue);

		CFObj<CFMutableDictionaryRef> columnIds;
		if( valuePresent && (ACFType<CFMutableDictionaryRef>::DynamicCast(resultValue) != NULL) )
		{
			columnIds.Adopt( (CFMutableDictionaryRef)resultValue, kCFObjRetain );
		}
		else
		{//create new dictionary
			columnIds.Adopt( ::CFDictionaryCreateMutable(
									kCFAllocatorDefault,
									0,
									NULL,//keyCallBacks,//SInt32 keys
									&kCFTypeDictionaryValueCallBacks), kCFObjDontRetain );
			
			::CFDictionarySetValue(
						mNibControlValues,
						inControlID,
						(const void *)(CFMutableDictionaryRef)columnIds);//add the new column id dict to main control id dict
			
			
		}

		if(columnIds != NULL)
		{
			::CFDictionarySetValue(
							columnIds,
							(const void *)columnIndex,
							(const void *)CFSTR(""));//put empty dummy string for now. it can be array if index is 0 (for all columns)
		}
	}
}


void
OnMyCommandCM::RefreshObjectsInFinder()
{
	if( mObjectList.size() == 0 )
		return;

	OSStatus err;
	
	AEDescList refreshList = {typeNull, NULL};
	err = ::AECreateList( NULL, 0, false, &refreshList );
	if(err != noErr) return;

	TRACE_CSTR("OnMyCommandCM. RefreshObjectsInFinder\n" );


	StAEDesc listDel(refreshList);

	for(CFIndex i = 0; i < mObjectList.size(); i++)
	{
		if( mObjectList[i].mRefreshPath != NULL)
		{

			DEBUG_CFSTR( mObjectList[i].mRefreshPath );

			CFObj<CFURLRef> oneURL( ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, mObjectList[i].mRefreshPath, kCFURLPOSIXPathStyle, false) );
			if(oneURL != NULL)
			{
				StAEDesc urlDesc;
				err = CMUtils::CreateAliasDesc( oneURL, urlDesc );
				
				if(err == noErr)
				{
					err = ::AEPutDesc( &refreshList, 0, urlDesc );
				}
				else
				{
					DEBUG_CSTR( "OMC->RefreshObjectsInFinder. CreateAliasDesc failed, err = %d\n", (int)err );
				}
//also, to make it more powerful when new files are deleted and created, we will call FNNotify for parent folder
				CFObj<CFURLRef> parentURL( ::CFURLCreateCopyDeletingLastPathComponent( kCFAllocatorDefault, oneURL ) );
				if(parentURL != NULL)
				{
 					FSRef fileRef;
					if( ::CFURLGetFSRef(parentURL, &fileRef) )
					{
						err = FNNotify( &fileRef, kFNDirectoryModifiedMessage, kNilOptions);
 						if(err != noErr)
 						{
 							DEBUG_CSTR( "OMC->RefreshObjectsInFinder. FNNotify failed, err = %d\n", (int)err );
 						}
 					}
 					else
 					{
 						DEBUG_CSTR( "OnMyCommandCM. RefreshObjectsInFinder. parent folder does not exist\n" );
 					}
 				}
			}
			else
			{
				DEBUG_CSTR( "OMC->RefreshObjectsInFinder. CFURLCreateWithFileSystemPath failed, err = %d\n", (int)err );
			}
		}
	}

	long listItemsCount = 0;
	if( ::AECountItems( &refreshList, &listItemsCount) == noErr )
	{
		if(listItemsCount > 0)
		{
			err = CMUtils::SendAppleEventToFinder( kAEFinderSuite, kAESync, refreshList, false );
			if(err != noErr)
			{
				DEBUG_CSTR( "OnMyCommandCM. RefreshObjectsInFinder. SendAppleEventToFinder failed\n" );
			}
			
			//some people recommend sending refresh event to Finder twice
			//but it does not seem to help because Finder sometimes just refuses to refresh
			//err = CMUtils::SendAppleEventToFinder( kAEFinderSuite, kAESync, refreshList, false );
		}
		else
		{
			DEBUG_CSTR( "OnMyCommandCM. RefreshObjectsInFinder. refresh list empty\n" );
		}
	}
}


#pragma mark -



//returns true if last command is active.
//makes sense if you have just one command and you want to check if it should be activated
//if we run in Shortcuts, runningInSpecialApp = true, inFrontAppName = NULL
//if we run in ShortcutsObserver, runningInSpecialApp = true, inFrontAppName != NULL

Boolean
OnMyCommandCM::PopulateItemsMenu( const AEDesc *inContext, AEDescList* ioRootMenu,
					Boolean runningInSpecialApp, CFStringRef inFrontAppName)
{
	TRACE_CSTR("OnMyCommandCM. PopulateItemsMenu\n" );

	if( mCommandList == NULL )
		return false;

//	OSStatus err = noErr;
	bool doActivate = false;
	CFStringRef submenuName = NULL;
	
	SubmenuTree itemTree(ioRootMenu);
	
	CFObj<CFStringRef> defaultMenuName( ::CFCopyLocalizedStringFromTableInBundle( CFSTR("/On My Command"), 
																CFSTR("Private"), mBundleRef, "") );
	CFStringRef rootMenuName = CFSTR("/");

	CFStringRef currAppName = mMyHostName;
	bool skipFinderWindowCheck = false;
	if( runningInSpecialApp )
	{
		currAppName = inFrontAppName;//currAppName != NULL: ShortcutObserver case, use front app
		if(currAppName == NULL)//Shortcuts case - always show
			skipFinderWindowCheck = true;
	}
	
	
	for(UInt32 i = 0; i < mCommandCount; i++)
	{
		CommandDescription &currCommand = mCommandList[i];
		
		if( currCommand.isSubcommand ) //it is a subcommand, do not add to menu, main command is always 'top!'
			continue;

		doActivate = IsCommandEnabled(currCommand, inContext, currAppName, skipFinderWindowCheck);

		if(doActivate)
		{	
			CFObj<CFMutableStringRef> subPath;
			if(currCommand.submenuName == NULL)
			{
				submenuName = defaultMenuName;
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
				
				if(firstChar != (UniChar)'/')
				{
					CFMutableStringRef newName = ::CFStringCreateMutable( kCFAllocatorDefault, 0);
					if(newName != NULL)
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
				if( currCommand.nameContainsText )
					CreateTextContext(currCommand, inContext);//load context text now
			}
			
			CFBundleRef localizationBundle = NULL;
			if(currCommand.localizationTableName != NULL)//client wants to be localized
			{
				localizationBundle = GetCurrentCommandExternBundle();
				if(localizationBundle == NULL)
					localizationBundle = CFBundleGetMainBundle();
			}

			CFObj<CFStringRef> dynamicCommandName( CreateDynamicCommandName(currCommand, currCommand.localizationTableName, localizationBundle) );
			itemTree.AddMenuItem(
								submenuName,
								dynamicCommandName,
								kCMCommandStart + i,
								(mSysVersion >= 100200),
								0,
								kMenuNoModifiers);
		}
	}
	

//	DEBUG_CSTR( "OMC->PopulateItemsMenu. About to call itemTree.BuildSubmenuTree()\n" );
	itemTree.BuildSubmenuTree();
	
	return doActivate;
}

bool
OnMyCommandCM::IsCommandEnabled(CommandDescription &currCommand, const AEDesc *inContext, CFStringRef currAppName, bool skipFinderWindowCheck)
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

	//check the rest only if our host qualifies
	switch(currCommand.activationMode)
	{
		case kActiveAlways:
			doActivate = true;
		break;
		
		case kActiveFile:
		{
			doActivate = CheckAllObjects(mObjectList, CheckIfFile, NULL);
			
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
					doActivate = CheckAllObjects(mObjectList, CheckFileTypeOrExtension, &(currCommand));
				}
				else if(needsFileTypeCheck)
				{
					doActivate = CheckAllObjects(mObjectList, CheckFileType, &(currCommand));
				}
				else if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(mObjectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;
		
		case kActiveFolder:
		{
			doActivate = CheckAllObjects(mObjectList, CheckIfFolder, NULL);
		
			if(doActivate)
			{
				Boolean needsExtensionCheck = (currCommand.activationExtensions != NULL);
				if(needsExtensionCheck)
				{
					needsExtensionCheck = (::CFArrayGetCount(currCommand.activationExtensions) > 0);
				}
				if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(mObjectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;

		case kActiveFolderExcludeFinderWindow:
		{
			if(skipFinderWindowCheck)
				doActivate = true;
			else
				doActivate = !mIsOpenFolder;
			
			if(doActivate)
				doActivate = CheckAllObjects(mObjectList, CheckIfFolder, NULL);
		
			if(doActivate)
			{
				Boolean needsExtensionCheck = (currCommand.activationExtensions != NULL);
				if(needsExtensionCheck)
				{
					needsExtensionCheck = (::CFArrayGetCount(currCommand.activationExtensions) > 0);
				}
				if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(mObjectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;
		
		case kActiveFileOrFolder:
		{
			doActivate = CheckAllObjects(mObjectList, CheckIfFileOrFolder, NULL);
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
					doActivate = CheckAllObjects(mObjectList, CheckFileTypeOrExtension, &(currCommand));
				}
				else if(needsFileTypeCheck)
				{
					doActivate = CheckAllObjects(mObjectList, CheckFileType, &(currCommand));
				}
				else if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(mObjectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;
		
		
		case kActiveFileOrFolderExcludeFinderWindow:
		{
			if(skipFinderWindowCheck)
				doActivate = true;
			else
				doActivate = !mIsOpenFolder;
			
			if(doActivate)
				doActivate = CheckAllObjects(mObjectList, CheckIfFileOrFolder, NULL);

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
					doActivate = CheckAllObjects(mObjectList, CheckFileTypeOrExtension, &(currCommand));
				}
				else if(needsFileTypeCheck)
				{
					doActivate = CheckAllObjects(mObjectList, CheckFileType, &(currCommand));
				}
				else if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(mObjectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;

		case kActiveFinderWindow:
		{
			if(skipFinderWindowCheck)
				doActivate = true;
			else
				doActivate = mIsOpenFolder;

			if(doActivate)
			{
				Boolean needsExtensionCheck = (currCommand.activationExtensions != NULL);
				if(needsExtensionCheck)
				{
					needsExtensionCheck = (::CFArrayGetCount(currCommand.activationExtensions) > 0);
				}
				if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(mObjectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;
		
		case kActiveSelectedText:
			doActivate = mIsTextContext;
		break;

		case kActiveClipboardText:
			doActivate = mIsTextInClipboard;
		break;
		
		case kActiveSelectedOrClipboardText:
			doActivate = (mIsTextContext || mIsTextInClipboard);
		break;
	}
		
	if(doActivate && (currCommand.contextMatchString != NULL) )
	{
		if(mObjectList.size() > 0)
		{//path or name matching requested
			switch(currCommand.matchFileOptions)
			{
				case kMatchFileName:
					doActivate = CheckAllObjects(mObjectList, CheckFileNameMatch, &(currCommand));
				break;
				
				case kMatchFilePath:
					doActivate = CheckAllObjects(mObjectList, CheckFilePathMatch, &(currCommand));
				break;
			}
		}
		else if( (mIsTextContext || mIsTextInClipboard) )
		{//text matching requested
			CreateTextContext(currCommand, inContext);//load context text now
			doActivate = DoStringsMatch(currCommand.contextMatchString, mContextText, currCommand.matchMethod, (CFStringCompareFlags)currCommand.matchCompareOptions );
		}
	}
	return doActivate;
}

bool
OnMyCommandCM::IsCommandEnabled(SInt32 inCmdIndex, const AEDesc *inContext, bool runningInSpecialApp, CFStringRef inFrontAppName)
{
	if( (mCommandList == NULL) || (inCmdIndex < 0) || (inCmdIndex >= mCommandCount) )
		return false;

	CFStringRef currAppName = mMyHostName;
	bool skipFinderWindowCheck = false;
	if( runningInSpecialApp )
	{
		currAppName = inFrontAppName;//currAppName != NULL: ShortcutObserver case, use front app
		if(currAppName == NULL)//Shortcuts case - always show
			skipFinderWindowCheck = true;
	}

	CommandDescription &currCommand = mCommandList[inCmdIndex];
	return IsCommandEnabled(currCommand, inContext, currAppName, skipFinderWindowCheck);
}

//all objects must meet the condition checked by procedure: logical AND

Boolean
CheckAllObjects(std::vector<OneObjProperties> &objList, ObjCheckingProc inProcPtr, void *inProcData)
{
	if( inProcPtr == nullptr )
		return false;

	for(size_t i = 0; i < objList.size(); i++)
	{
        if(false == (*inProcPtr)( &objList[i], inProcData ) )
            return false;
	}

	return true;
}

inline Boolean
CheckIfFile(OneObjProperties *inObj, void *)
{
	return ((inObj->mFlags & kLSItemInfoIsPlainFile) != 0);
}

inline Boolean
CheckIfFolder(OneObjProperties *inObj, void *)
{
	return ((inObj->mFlags & kLSItemInfoIsContainer) != 0);
}

inline Boolean
CheckIfFileOrFolder(OneObjProperties *inObj, void *)
{
	return ((inObj->mFlags & (kLSItemInfoIsPlainFile | kLSItemInfoIsContainer)) != 0);
}

inline Boolean
CheckIfPackage(OneObjProperties *inObj, void *)
{
	return ((inObj->mFlags & kLSItemInfoIsPackage) != 0);
}

inline Boolean
CheckFileType(OneObjProperties *inObj, void *inData)
{
	if(inData == NULL) return false;
	CommandDescription *commDesc = (CommandDescription *)inData;

	if( commDesc->activationTypes == NULL )
		return true;

	if( commDesc->activationTypeCount == 0)
		return true;
	
	for(UInt32 i = 0; i < commDesc->activationTypeCount; i++)
	{
		if( commDesc->activationTypes[i] == inObj->mType )
		{
			return true;//a match was found
		}
	}

	return false;
}

inline Boolean
CheckExtension(OneObjProperties *inObj, void *inData)
{
//	TRACE_CSTR("OnMyCommandCM. CheckExtension\n" );

	if(inData == NULL) return false;
	CommandDescription *commDesc = (CommandDescription *)inData;

	if(commDesc->activationExtensions == NULL)
		return true;//no extensions required - treat it as a match
	
	ACFArr extensions(commDesc->activationExtensions);
	CFIndex theCount = extensions.GetCount();
	
	if(theCount == 0)
		return true;//no extensions required - treat it as a match

	if(inObj->mExtension == NULL)
		return false;//no extension - it cannot be matched
	
	CFIndex	theLen = ::CFStringGetLength(inObj->mExtension);
	if(theLen == 0)
		return false;//no extension - it cannot be matched
	
	CFStringRef theExt;
	
	for(CFIndex i = 0; i < theCount; i++)
	{
		if( extensions.GetValueAtIndex(i, theExt) &&
			(kCFCompareEqualTo == ::CFStringCompare( inObj->mExtension, theExt, kCFCompareCaseInsensitive)) )
		{
			return true;//a match found
		}
	}
	return false;
}

inline Boolean
CheckFileTypeOrExtension(OneObjProperties *inObj, void *inData)
{
	return (CheckFileType(inObj, inData) || CheckExtension(inObj, inData));
}

inline Boolean
CheckFileNameMatch(OneObjProperties *inObj, void *inData)
{
	if(inData == NULL) return false;
	CommandDescription *commDesc = (CommandDescription *)inData;
	CFObj<CFStringRef> fileName( CreateObjName(inObj, NULL) );
	return DoStringsMatch(commDesc->contextMatchString, fileName, commDesc->matchMethod, (CFStringCompareFlags)commDesc->matchCompareOptions);
}

inline Boolean
CheckFilePathMatch(OneObjProperties *inObj, void *inData)
{
	if(inData == NULL) return false;
	CommandDescription *commDesc = (CommandDescription *)inData;
	CFObj<CFStringRef> filePath( CreateObjPath(inObj, NULL) );
	return DoStringsMatch(commDesc->contextMatchString, filePath, commDesc->matchMethod, (CFStringCompareFlags)commDesc->matchCompareOptions);
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

extern "C" SInt32
GetSpecialWordID(CFStringRef inStr)
{
#if 0
	TRACE_CSTR( "OnMyCommandCM->GetSpecialWordID\n" );
#endif

	if(inStr == NULL)
		return NO_SPECIAL_WORD;

  	CFIndex	strLen = ::CFStringGetLength(inStr);
	if( (strLen < kMinSpecialWordLen) || (strLen > kMaxSpecialWordLen))
		return NO_SPECIAL_WORD;

  	UniChar oneChar = ::CFStringGetCharacterAtIndex(inStr, 0);
	if(oneChar != '_')
		return NO_SPECIAL_WORD; //special word must start with underscore

	UInt32 theCount = sizeof(sSpecialWordAndIDList)/sizeof(SpecialWordAndID);
	for(UInt32 i = 0; i< theCount; i++)
	{
		if(sSpecialWordAndIDList[i].wordLen == strLen)
		{
			if(kCFCompareEqualTo == ::CFStringCompare( inStr, sSpecialWordAndIDList[i].specialWord, 0 ))
			{
				return sSpecialWordAndIDList[i].id;
			}
		}
	}
	
	if( ::CFStringHasPrefix(inStr, CFSTR("__NIB_DIALOG_CONTROL_")) &&
		::CFStringHasSuffix(inStr, CFSTR("_VALUE__")) )
	{
		return NIB_DLG_CONTROL_VALUE;
	}
	else if( ::CFStringHasPrefix(inStr, CFSTR("__NIB_TABLE_")) &&
			::CFStringHasSuffix(inStr, CFSTR("_VALUE__")) )
	{
		return NIB_TABLE_VALUE;
	}
	else if( ::CFStringHasPrefix(inStr, CFSTR("__NIB_TABLE_")) &&
			::CFStringHasSuffix(inStr, CFSTR("_ALL_ROWS__")) )
	{
		return NIB_TABLE_ALL_ROWS;
	}
	
	return NO_SPECIAL_WORD;
}

extern "C" SInt32
GetSpecialEnvironWordID(CFStringRef inStr)
{
#if 0
	TRACE_CSTR( "OnMyCommandCM->GetSpecialEnvironWordID\n" );
#endif

	if(inStr == NULL)
		return NO_SPECIAL_WORD;

  	CFIndex	strLen = ::CFStringGetLength(inStr);
	if( (strLen < kMinSpecialWordLen) || (strLen > kMaxSpecialWordLen))
		return NO_SPECIAL_WORD;

	UniChar firstChars[4] = { 0 };
	::CFStringGetCharacters( inStr, CFRangeMake(0, 4), firstChars);
	if( (firstChars[0] != 'O') || (firstChars[1] != 'M') || (firstChars[2] != 'C') || (firstChars[3] != '_') )
		return NO_SPECIAL_WORD; //special environ word must start with OMC_

	UInt32 theCount = sizeof(sSpecialWordAndIDList)/sizeof(SpecialWordAndID);
	for(UInt32 i = 0; i< theCount; i++)
	{
		if(sSpecialWordAndIDList[i].wordLen == strLen)
		{
			if(kCFCompareEqualTo == ::CFStringCompare( inStr, sSpecialWordAndIDList[i].environName, 0 ))
			{
				return sSpecialWordAndIDList[i].id;
			}
		}
	}
	
	if( ::CFStringHasPrefix(inStr, CFSTR("OMC_NIB_DIALOG_CONTROL_")) &&
		::CFStringHasSuffix(inStr, CFSTR("_VALUE")) )
	{
		return NIB_DLG_CONTROL_VALUE;
	}
	else if( ::CFStringHasPrefix(inStr, CFSTR("OMC_NIB_TABLE_")) &&
			::CFStringHasSuffix(inStr, CFSTR("_VALUE")) )
	{
		return NIB_TABLE_VALUE;
	}
	else if( ::CFStringHasPrefix(inStr, CFSTR("OMC_NIB_TABLE_")) &&
			::CFStringHasSuffix(inStr, CFSTR("_ALL_ROWS")) )
	{
		return NIB_TABLE_ALL_ROWS;
	}
	
	return NO_SPECIAL_WORD;
}

CFURLRef
CopyOMCPrefsURL()
{
	FSRef prefsFolder;
	memset(&prefsFolder, 0, sizeof(FSRef) );
	OSStatus err = ::FSFindFolder(kUserDomain, kPreferencesFolderType, kCreateFolder, &prefsFolder);
	if(err != noErr)
		return NULL;
	
	CFObj<CFURLRef> prefsFolderURL( ::CFURLCreateFromFSRef(kCFAllocatorDefault, &prefsFolder) );
	if(prefsFolderURL == NULL)
		return NULL;
	
	return ::CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, prefsFolderURL, CFSTR("com.abracode.OnMyCommandCMPrefs.plist"), false /*isDirectory*/);
}

void
OnMyCommandCM::ReadPreferences()
{
	TRACE_CSTR("OnMyCommandCM. ReadPreferences\n" );

/*
	if( mCommandList != NULL )
	{
		DeleteCommandList();
	}
	mCommandCount = 0;

	CFStringRef prefsIdentifier = CFSTR(CM_IMPL_PLUGIN_PREFS_INDENTIFIER);
	
	::CFPreferencesAppSynchronize( prefsIdentifier );

	Boolean isValid = false;
//	CFIndex theState = 0;

	CFIndex theVer = ::CFPreferencesGetAppIntegerValue( CFSTR("VERSION"), prefsIdentifier, &isValid );
	if( isValid && (theVer == 2) )
	{
		isValid = false;
		CFObj<CFPropertyListRef> resultRef( ::CFPreferencesCopyAppValue( CFSTR("COMMAND_LIST"), prefsIdentifier ) );
		CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast(resultRef);
		if( theArr != NULL )
		{
			ParseCommandList(theArr);
		}
		else
		{
			LOG_CSTR( "OMC->ReadPreferences: no COMMAND_LIST array\n" );
		}
	}
	else
	{
		LOG_CSTR( "OMC->ReadPreferences: invalid command description format version number\n" );
	}
*/
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

	CFIndex verNum = 0;
	properties.GetValue(CFSTR("VERSION"), verNum);
	if(verNum != 2)
		return;

	CFArrayRef commandArrayRef;
	if( !properties.GetValue(CFSTR("COMMAND_LIST"), commandArrayRef) )
		return;

	ParseCommandList(commandArrayRef);
}


Boolean
OnMyCommandCM::IsSubcommand(CFArrayRef inName, SInt32 inCommandIndex)
{
	if((inName == NULL) || (mCommandList == NULL))
		return false;

	for(SInt32 i = inCommandIndex-1; i >= 0; i--)
	{		
		if( (mCommandList[i].name != NULL) && ::CFEqual(inName, mCommandList[i].name) /*&&
			((mCommandList[i].commandID == 'top!') || (mCommandList[i].isSubcommand))*/ )
		{//if I find a command with the same name before me, I am the subcommand
			return true;
		}
	}

	for(SInt32 i = inCommandIndex+1; i < (SInt32)mCommandCount; i++)
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
	memset(mCommandList, 0, theCount*sizeof(CommandDescription));
	mCommandCount = theCount;
	
	CFDictionaryRef theDict;
	
	for( CFIndex i = 0; i < theCount; i++ )
	{
		mCommandList[i] = kEmptyCommand;
		if( commands.GetValueAtIndex( i, theDict ) )
		{
			GetOneCommandParams( mCommandList[i], theDict );
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

void
OnMyCommandCM::GetOneCommandParams(CommandDescription &outDesc, CFDictionaryRef inOneCommand)
{
//	TRACE_CSTR("OnMyCommandCM. GetOneCommandParams\n" );

	CFStringRef theStr;
	CFDictionaryRef theDict;
	CFArrayRef theArr;

	ACFDict oneCmd(inOneCommand);

//disabled?
	oneCmd.GetValue( CFSTR("DISABLED"), outDesc.disabled );

//name
	outDesc.nameIsDynamic = false;//optimization
	if( oneCmd.GetValue(CFSTR("NAME"), theStr) )
	{
		CFMutableArrayRef mutableArray = ::CFArrayCreateMutable( kCFAllocatorDefault, 1, &kCFTypeArrayCallBacks );
		::CFArrayAppendValue(mutableArray, theStr);
		outDesc.name = mutableArray;
	}
	else if( oneCmd.CopyValue(CFSTR("NAME"), outDesc.name) )
	{
		outDesc.nameIsDynamic = true;
	}
	else
	{
		LOG_CSTR( "OMC->GetOneCommandParams. NAME param not of type CFString or CFArray\n" );
	}

//commandID for command handler
//this keyword should only be present for subcommands aka command handlers
//reserved codes:
//	'top!' - for main/master command
//	'ini!' - for dialog initialization code
//reserve all keywords with first 3 lowercase letters and exlamation mark at the end
//outDesc.commandID is initialized to 'top!' if the keyword is missing

	oneCmd.CopyValue(CFSTR("COMMAND_ID"), outDesc.commandID);

	if(outDesc.commandID == NULL)
	{
		outDesc.commandID = kOMCTopCommandID;
		::CFRetain( outDesc.commandID );
	}

//if the command is disabled we do not bother reading the rest
	if(outDesc.disabled)
		return;

//name plural
	oneCmd.CopyValue(CFSTR("NAME_PLURAL"), outDesc.namePlural);

//command array
	if( !oneCmd.CopyValue(CFSTR("COMMAND"), outDesc.command) )
	{
		//we may end up here because the key does not exist or because it is not an array
		CFTypeRef resultRef = NULL;
		Boolean keyExists = ::CFDictionaryGetValueIfPresent( inOneCommand, CFSTR("COMMAND"), &resultRef );
		if(keyExists)
		{
			LOG_CSTR( "OMC->GetOneCommandParams. COMMAND param not of type CFArray\n" );
		}
	}

//execution
	if( oneCmd.GetValue(CFSTR("EXECUTION_MODE"), theStr) )
	{
//		TRACE_CSTR("\tGetOneCommandParams. EXECUTION_MODE string:\n" );
//		TRACE_CFSTR(theStr);

		if( (kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_silent"), 0)) ||
			(kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_silent_popen"), 0)) )
		{
			outDesc.executionMode = kExecSilentPOpen;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_silent_system"), 0 ) )
		{
			outDesc.executionMode = kExecSilentSystem;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_terminal"), 0 ) )
		{
			outDesc.executionMode = kExecTerminal;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_iterm"), 0 ) )
		{
			outDesc.executionMode = kExecITerm;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_popen_with_output_window"), 0 ) )
		{
			outDesc.executionMode = kExecPOpenWithOutputWindow;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_applescript"), 0 ) )
		{
			outDesc.executionMode = kExecAppleScript;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_applescript_with_output_window"), 0 ) )
		{
			outDesc.executionMode = kExecAppleScriptWithOutputWindow;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_shell_script"), 0 ) )
		{
			outDesc.executionMode = kExecShellScript;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_shell_script_with_output_window"), 0 ) )
		{
			outDesc.executionMode = kExecShellScriptWithOutputWindow;
		}
	}

//imput pipe array
	oneCmd.CopyValue(CFSTR("STANDARD_INPUT_PIPE"), outDesc.inputPipe);

//	if(false)
//	{
//		LOG_CSTR( "OMC->GetOneCommandParams. STANDARD_INPUT_PIPE param not of type CFArray\n" );
//	}

	if( outDesc.executionMode == kExecITerm )
		oneCmd.CopyValue(CFSTR("ITERM_SHELL_PATH"), outDesc.iTermShellPath);

//activation
	if( oneCmd.GetValue(CFSTR("ACTIVATION_MODE"), theStr) )
	{
//		TRACE_CSTR("\tGetOneCommandParams. ACTIVATION_MODE string:\n" );
//		TRACE_CFSTR(theStr);

		if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("act_always"), 0 ) )
		{
			outDesc.activationMode = kActiveAlways;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("act_file"), 0 ) )
		{
			outDesc.activationMode = kActiveFile;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("act_folder"), 0 ) )
		{
			outDesc.activationMode = kActiveFolder;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("act_file_or_folder"), 0 ) )
		{
			outDesc.activationMode = kActiveFileOrFolder;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("act_finder_window"), 0 ) )
		{
			outDesc.activationMode = kActiveFinderWindow;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("act_selected_text"), 0 ) )
		{
			outDesc.activationMode = kActiveSelectedText;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("act_clipboard_text"), 0 ) )
		{
			outDesc.activationMode = kActiveClipboardText;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("act_selected_or_clipboard_text"), 0 ) )
		{
			outDesc.activationMode = kActiveSelectedOrClipboardText;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("act_folder_not_finder_window"), 0 ) )
		{
			outDesc.activationMode = kActiveFolderExcludeFinderWindow;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("act_file_or_folder_not_finder_window"), 0 ) )
		{
			outDesc.activationMode = kActiveFileOrFolderExcludeFinderWindow;
		}
	}

//escaping
	if( oneCmd.GetValue(CFSTR("ESCAPE_SPECIAL_CHARS"), theStr) )
	{
//		TRACE_CSTR("\tGetOneCommandParams. ESCAPE_SPECIAL_CHARS string:\n" );
//		TRACE_CFSTR(theStr);
		outDesc.escapeSpecialCharsMode = GetEscapingMode(theStr);
	}

//file types
	if( oneCmd.GetValue(CFSTR("ACTIVATION_FILE_TYPES"), theArr) )
	{
		ACFArr fileTypes(theArr);
		CFIndex theCount = fileTypes.GetCount();
		if(theCount > 0)
		{
			outDesc.activationTypes = new FileType[theCount];
			memset( outDesc.activationTypes, 0, theCount*sizeof(FileType) );
			outDesc.activationTypeCount = theCount;
			CFStringRef typeStrRef;
			for(CFIndex i = 0; i < theCount; i++)
			{
				outDesc.activationTypes[i] = 0;
				if( fileTypes.GetValueAtIndex(i, typeStrRef) )
					outDesc.activationTypes[i] = CFStringToFourCharCode(typeStrRef);
			}
		}
	}

//extensions
	oneCmd.CopyValue(CFSTR("ACTIVATION_EXTENSIONS"), outDesc.activationExtensions);

//mutiple objects settings
	if( oneCmd.GetValue(CFSTR("MULTIPLE_OBJECT_SETTINGS"), theDict) )
		GetMultiCommandParams( outDesc, theDict );

//bring to front
	oneCmd.GetValue(CFSTR("TERM_BRING_TO_FRONT"), outDesc.bringTerminalToFront);

// new session
	oneCmd.GetValue(CFSTR("TERM_OPEN_NEW_SESSION"), outDesc.openNewTerminalSession);

//warning
	oneCmd.CopyValue(CFSTR("WARNING"), outDesc.warningStr);

//cancel button name
	oneCmd.CopyValue(CFSTR("WARNING_CANCEL"), outDesc.warningCancelStr);

//execute button name
	oneCmd.CopyValue(CFSTR("WARNING_EXECUTE"), outDesc.warningExecuteStr);

//submenu
	oneCmd.CopyValue(CFSTR("SUBMENU_NAME"), outDesc.submenuName);

//input dialog
	if( oneCmd.GetValue(CFSTR("INPUT_DIALOG"), theDict) )
		GetInputDialogParams( outDesc, theDict );

//Finder refresh path
	oneCmd.CopyValue(CFSTR("REFRESH_PATH"), outDesc.refresh);
	
//save as dialog
	oneCmd.CopyValue(CFSTR("SAVE_AS_DIALOG"), outDesc.saveAsParams);

//choose file dialog
	oneCmd.CopyValue(CFSTR("CHOOSE_FILE_DIALOG"), outDesc.chooseFileParams);

//choose folder dialog
	oneCmd.CopyValue(CFSTR("CHOOSE_FOLDER_DIALOG"), outDesc.chooseFolderParams);

//choose object dialog
	oneCmd.CopyValue(CFSTR("CHOOSE_OBJECT_DIALOG"), outDesc.chooseObjectParams);

//output window settings
	oneCmd.CopyValue(CFSTR("OUTPUT_WINDOW_SETTINGS"), outDesc.outputWindowOptions);

//simulate paste
	oneCmd.GetValue(CFSTR("PASTE_AFTER_EXECUTION"), outDesc.simulatePaste);

//activate in applications
	if( oneCmd.CopyValue(CFSTR("ACTIVATE_ONLY_IN"), outDesc.appNames) )
		outDesc.actOnlyInListedApps = true;
	else if( oneCmd.CopyValue(CFSTR("NEVER_ACTIVATE_IN"), outDesc.appNames) )
		outDesc.actOnlyInListedApps = false;

//nib dialog settings
	oneCmd.CopyValue(CFSTR("NIB_DIALOG"), outDesc.nibDialog);

//text replace option
	outDesc.textReplaceOptions = kTextReplaceNothing;
	if( oneCmd.GetValue(CFSTR("TEXT_REPLACE_OPTION"), theStr) )
	{
//		TRACE_CSTR("\tGetOneCommandParams. TEXT_REPLACE_OPTION string:\n" );
//		TRACE_CFSTR(theStr);

		if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("txt_replace_none"), 0 ) )
		{
			outDesc.textReplaceOptions = kTextReplaceNothing;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("txt_replace_lf_with_cr"), 0 ) )
		{
			outDesc.textReplaceOptions = kTextReplaceLFsWithCRs;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("txt_replace_cr_with_lf"), 0 ) )
		{
			outDesc.textReplaceOptions = kTextReplaceCRsWithLFs;
		}
	}

//nextCommandID
	oneCmd.CopyValue(CFSTR("NEXT_COMMAND_ID"), outDesc.nextCommandID);

//externalBundlePath
	if( mExternBundleOverrideURL != NULL)//extern bundle path override is used when OMC is passed a .omc package for execution instead of plist file
		outDesc.externalBundlePath = ::CFURLCopyFileSystemPath( mExternBundleOverrideURL, kCFURLPOSIXPathStyle );
	else if( oneCmd.GetValue(CFSTR("EXTERNAL_BUNDLE_PATH"), theStr) )
		outDesc.externalBundlePath = CreatePathByExpandingTilde( theStr );//keep the string, we are responsible for releasing it

//popenShell
	oneCmd.CopyValue(CFSTR("POPEN_SHELL"), outDesc.popenShell);

//customEnvironVariables
	outDesc.customEnvironVariables = NULL;
	CFDictionaryRef customEnvironVariables = NULL;
	oneCmd.GetValue(CFSTR("ENVIRONMENT_VARIABLES"), customEnvironVariables);
	if(customEnvironVariables != NULL)
		outDesc.customEnvironVariables = ::CFDictionaryCreateMutableCopy( kCFAllocatorDefault, 0, customEnvironVariables );

//using deputy for background execution?
	oneCmd.GetValue(CFSTR("SEND_TASK_TO_BACKGROUND_APP"), outDesc.useDeputy);

	oneCmd.CopyValue(CFSTR("END_NOTIFICATION"), outDesc.endNotification);

	oneCmd.CopyValue(CFSTR("PROGRESS"), outDesc.progress);

	oneCmd.GetValue(CFSTR("MAX_PARALLEL_TASK_COUNT"), outDesc.maxTaskCount);

	Boolean useNavDialogForMissingFileContext = true;
	oneCmd.GetValue(CFSTR("USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT"), useNavDialogForMissingFileContext);
	if(useNavDialogForMissingFileContext)
		outDesc.executionOptions |= kExecutionOption_UseNavDialogForMissingFileContext;

//name/path/text matching settings
	if( oneCmd.GetValue(CFSTR("ACTIVATION_OBJECT_STRING_MATCH"), theDict) )
		GetContextMatchingParams( outDesc, theDict );

	oneCmd.CopyValue(CFSTR("NIB_CONTROL_MULTIPLE_SELECTION_ITERATION"), outDesc.multipleSelectionIteratorParams);

//table name for localization - for droplets or external modules only
	oneCmd.CopyValue(CFSTR("LOCALIZATION_TABLE_NAME"), outDesc.localizationTableName);
	
//version requirements
	if( oneCmd.GetValue(CFSTR("REQUIRED_OMC_VERSION"), theStr) )
		outDesc.requiredOMCVersion = StringToVersion(theStr);

	if( oneCmd.GetValue(CFSTR("REQUIRED_MAC_OS_MIN_VERSION"), theStr) )
		outDesc.requiredMacOSMinVersion = StringToVersion(theStr);

	if( oneCmd.GetValue(CFSTR("REQUIRED_MAC_OS_MAX_VERSION"), theStr) )
		outDesc.requiredMacOSMaxVersion = StringToVersion(theStr);
}

void
GetMultiCommandParams(CommandDescription &outDesc, CFDictionaryRef inParams)
{
	CFStringRef theStr;
	ACFDict params(inParams);
	
	if( params.GetValue(CFSTR("PROCESSING_MODE"), theStr) )
	{
		if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("proc_separately"), 0 ) )
		{
			outDesc.multipleObjectProcessing = kMulObjProcessSeparately;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("proc_together"), 0 ) )
		{
			outDesc.multipleObjectProcessing = kMulObjProcessTogether;
		}
	}

	if(outDesc.multipleObjectProcessing == kMulObjProcessTogether)
	{//read other settings only when processing multiple objects together is turned on
		params.CopyValue(CFSTR("PREFIX"), outDesc.mulObjPrefix);
		params.CopyValue(CFSTR("SUFFIX"), outDesc.mulObjSuffix);
		params.CopyValue(CFSTR("SEPARATOR"), outDesc.mulObjSeparator);
		
		//handle \r \n \t strings that may be present here
		if( (outDesc.mulObjPrefix != NULL) && (::CFStringGetLength(outDesc.mulObjPrefix) > 1) )
		{
			CFMutableStringRef mutableString = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, outDesc.mulObjPrefix);
			if(mutableString != NULL)
			{
				ReplaceWhitespaceEscapesWithCharacters(mutableString);
				CFRelease(outDesc.mulObjPrefix);
				outDesc.mulObjPrefix = mutableString;
			}
		}
		
		if( (outDesc.mulObjSuffix != NULL) && (::CFStringGetLength(outDesc.mulObjSuffix) > 1) )
		{
			CFMutableStringRef mutableString = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, outDesc.mulObjSuffix);
			if(mutableString != NULL)
			{
				ReplaceWhitespaceEscapesWithCharacters(mutableString);
				CFRelease(outDesc.mulObjSuffix);
				outDesc.mulObjSuffix = mutableString;
			}
		}
		
		if( (outDesc.mulObjSeparator != NULL) && (::CFStringGetLength(outDesc.mulObjSeparator) > 1) )
		{
			CFMutableStringRef mutableString = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, outDesc.mulObjSeparator);
			if(mutableString != NULL)
			{
				ReplaceWhitespaceEscapesWithCharacters(mutableString);
				CFRelease(outDesc.mulObjSeparator);
				outDesc.mulObjSeparator = mutableString;
			}
		}
	}

	if( params.GetValue(CFSTR("SORT_METHOD"), theStr) )
	{
		if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("sort_by_name"), 0 ) )
		{
			outDesc.sortMethod = kSortMethodByName;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("sort_none"), 0 ) )
		{
			outDesc.sortMethod = kSortMethodNone;
		}
	}

	if(outDesc.sortMethod != kSortMethodNone)
	{
		CFDictionaryRef optionsDict;
		if( params.GetValue(CFSTR("SORT_OPTIONS"), optionsDict) )
		{
			ACFDict sortOptions(optionsDict);
			sortOptions.GetValue( CFSTR("SORT_ASCENDING"), outDesc.sortAscending );
			
			Boolean boolValue;
			if( sortOptions.GetValue(CFSTR("COMPARE_CASE_INSENSITIVE"), boolValue) && boolValue )
				outDesc.sortOptions |= kCFCompareCaseInsensitive;						
				
			if( sortOptions.GetValue(CFSTR("COMPARE_NONLITERAL"), boolValue) && boolValue )
				outDesc.sortOptions |= kCFCompareNonliteral;						

			if( sortOptions.GetValue(CFSTR("COMPARE_LOCALIZED"), boolValue) && boolValue )
				outDesc.sortOptions |= kCFCompareLocalized;						
				
			if( sortOptions.GetValue(CFSTR("COMPARE_NUMERICAL"), boolValue) && boolValue )
				outDesc.sortOptions |= kCFCompareNumerically;						
		}
	}
}

void
GetInputDialogParams(CommandDescription &outDesc, CFDictionaryRef inParams)
{
	CFStringRef theStr;

	ACFDict params(inParams);
	if( params.GetValue(CFSTR("INPUT_TYPE"), theStr) )
	{
		if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("input_clear_text"), 0 ) )
		{
			outDesc.inputDialogType = kInputClearText;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("input_password_text"), 0 ) )
		{
			outDesc.inputDialogType = kInputPasswordText;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("input_popup_menu"), 0 ) )
		{
			outDesc.inputDialogType = kInputPopupMenu;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("input_combo_box"), 0 ) )
		{
			outDesc.inputDialogType = kInputComboBox;
		}
	}
	
	params.CopyValue( CFSTR("OK_BUTTON_NAME"), outDesc.inputDialogOK );
	params.CopyValue( CFSTR("CANCEL_BUTTON_NAME"), outDesc.inputDialogCancel );
	params.CopyValue( CFSTR("MESSAGE"), outDesc.inputDialogMessage );

//default input dialog value can be array or string
	if( params.CopyValue(CFSTR("DEFAULT_VALUE"), outDesc.inputDialogDefault) )
	{
		;//array
	}
	else if( params.GetValue(CFSTR("DEFAULT"), theStr) )
	{
		CFMutableArrayRef mutableArray = ::CFArrayCreateMutable( kCFAllocatorDefault, 1, &kCFTypeArrayCallBacks );
		::CFArrayAppendValue(mutableArray, theStr);
		outDesc.inputDialogDefault = mutableArray;
	}

	if((outDesc.inputDialogType == kInputPopupMenu) || (outDesc.inputDialogType == kInputComboBox))
	{//read menu items only when dialog input type is popup menu
		params.CopyValue( CFSTR("INPUT_MENU"), outDesc.inputDialogMenuItems );
	}
}

void
GetNavDialogParams(CFDictionaryRef inParams, CFStringRef &outMessage, CFArrayRef &outDefaultName, CFArrayRef &outDefaultLocation, UInt32 &outAdditionalNavServiesFlags)
{
	ACFDict params(inParams);
	params.CopyValue( CFSTR("MESSAGE"), outMessage );
	params.CopyValue( CFSTR("DEFAULT_FILE_NAME"), outDefaultName );
	params.CopyValue( CFSTR("DEFAULT_LOCATION"), outDefaultLocation );
	
	outAdditionalNavServiesFlags = 0;
	Boolean boolValue;
	if( params.GetValue(CFSTR("SHOW_INVISIBLE_ITEMS"), boolValue) && boolValue )
		outAdditionalNavServiesFlags |= kOMCFilePanelAllowInvisibleItems;

	boolValue = true; //default is true: reuse cached path from main command or other subcommand
	params.GetValue(CFSTR("USE_PATH_CACHING"), boolValue);

	if(boolValue)
		outAdditionalNavServiesFlags |= kOMCFilePanelUseCachedPath;
}

CFStringRef sEscapeModes[] = 
{
	CFSTR("esc_none"), //kEscapeNone
	CFSTR("esc_with_backslash"), //kEscapeWithBackslash
	CFSTR("esc_with_percent"), //kEscapeWithPercent
	CFSTR("esc_with_percent_all"), //kEscapeWithPercentAll
	CFSTR("esc_for_applescript"), //kEscapeForAppleScript
	CFSTR("esc_wrap_with_single_quotes_for_shell") //kEscapeWrapWithSingleQuotesForShell
};

extern "C" UInt8
GetEscapingMode(CFStringRef theStr)
{
	UInt8 escapeSpecialCharsMode = kEscapeWithBackslash;

	for(UInt8 i = kEscapeModeFirst; i <= kEscapeModeLast; i++)
	{
		if( kCFCompareEqualTo == ::CFStringCompare( theStr, sEscapeModes[i], 0 ) )
		{
			escapeSpecialCharsMode = i;
			break;
		}
	}

	return escapeSpecialCharsMode;
}


extern "C" CFStringRef
GetEscapingModeString(UInt8 inEscapeMode)
{
	if( /*(inEscapeMode < kEscapeModeFirst) ||*/ (inEscapeMode > kEscapeModeLast) )
		inEscapeMode = kEscapeWithBackslash;//use default
	return sEscapeModes[inEscapeMode];
}

void
GetContextMatchingParams(CommandDescription &outDesc, CFDictionaryRef inParams)
{
	CFStringRef theStr;

	ACFDict params(inParams);
	params.CopyValue( CFSTR("MATCH_STRING"), outDesc.contextMatchString );

	if(outDesc.contextMatchString == NULL) //no need to read other params
		return;

	if( params.GetValue(CFSTR("MATCH_METHOD"), theStr) )
	{
		if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("match_exact"), 0 ) )
		{
			outDesc.matchMethod = kMatchExact;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("match_contains"), 0 ) )
		{
			outDesc.matchMethod = kMatchContains;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("match_regular_expression"), 0 ) )
		{
			outDesc.matchMethod = kMatchRegularExpression;
		}
	}

	if( params.GetValue(CFSTR("FILE_OPTIONS"), theStr) )
	{
		if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("match_file_name"), 0 ) )
		{
			outDesc.matchFileOptions = kMatchFileName;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("match_file_path"), 0 ) )
		{
			outDesc.matchFileOptions = kMatchFilePath;
		}
	}
	
	Boolean boolValue;
	if( params.GetValue(CFSTR("COMPARE_CASE_INSENSITIVE"), boolValue) && boolValue )
		outDesc.matchCompareOptions |= kCFCompareCaseInsensitive;						

}

/*
void
GetNibDialogSettings(CommandDescription &outDesc, CFDictionaryRef inParams)
{
	ACFDict params(inParams);
	params.CopyValue( CFSTR("NIB_NAME"), outDesc.dialogNibName );
	params.CopyValue( CFSTR("WINDOW_NAME"), outDesc.nibWindowName );

	CFStringRef theStr;
	if( params.GetValue( CFSTR("INIT_SUBCOMMAND_ID"), theStr ) )
		outDesc.initSubcommandID = CFStringToFourCharCode( theStr );

	if( params.GetValue( CFSTR("END_OK_SUBCOMMAND_ID"), theStr ) )
		outDesc.endOKSubcommandID = CFStringToFourCharCode( theStr );

	if( params.GetValue( CFSTR("END_CANCEL_SUBCOMMAND_ID"), theStr ) )
		outDesc.endCancelSubcommandID = CFStringToFourCharCode( theStr );
}
*/


//use OSType UTGetOSTypeFromString( CFStringRef inTag );
/*
FourCharCode
CFStringToFourCharCode(CFStringRef inStrRef)
{
	if(inStrRef == NULL)
		return 0;

	FourCharCode outValue = 0;
	Str31 pascalString = {0,0,0,0,0};//zero the fields we are interested in

	if( ::CFStringGetPascalString(inStrRef, pascalString, sizeof(pascalString), kCFStringEncodingMacRoman) )
	{
		short theLen = pascalString[0];
		if(theLen < 4)
		{
			*(long *)(pascalString+theLen+1) = 0L;//terminate with a couple of zeros
		}
		outValue = *(FourCharCode*)(pascalString+1);
	}
	return ::CFSwapInt32BigToHost(outValue);
}
*/

/* ReplaceSpecialCharsWithBackslashEscapes modifies path so the special characters in filename
will not be interpreted by shell.

As a test, I created in Finder a folder named:

	#`~!@$%^&*()_+={}[-]|\;'",.<>?/

This function created an escaped version of it:
	#\`~\!@\$%^\&\*\(\)_+=\{\}\[-\]\|\\\;\'\",.\<\>\?:

and it works fine in Terminal.

By the way: note that the '/' in Finder is represented as ':' in Terminal
You may create a file with ':' char in name in Terminal, but not in Finder
and you can create a file with '/' char in name in Finder but not in Terminal.
	
*/
void
ReplaceSpecialCharsWithBackslashEscapes(CFMutableStringRef inStrRef)
{
	if(inStrRef == NULL)
		return;

  	//replace spaces in path with backslash + space
  	CFIndex	idx = ::CFStringGetLength(inStrRef) - 1;
  	UniChar currChar = 0;
	while(idx >= 0)
	{
 		currChar = ::CFStringGetCharacterAtIndex( inStrRef, idx);
 		if( (currChar == ' ') || (currChar == '\\') || (currChar == '*') || (currChar == '?') || (currChar == '\t') ||
 			(currChar == '$') || (currChar == '\'') || (currChar == '\"') || (currChar == '!') || (currChar == '&') || 
 			(currChar == '(') || (currChar == ')') || (currChar == '{') || (currChar == '}') || (currChar == '[') ||
 			(currChar == ']') || (currChar == '|') || (currChar == ';') || (currChar == '<') || (currChar == '>') || 
 			(currChar == '`') || (currChar == 0x0A) || (currChar == 0x0D) )
 		{
	 		::CFStringInsert( inStrRef, idx, CFSTR("\\") );
		}
		idx--;
	}
}


void
ReplaceSpecialCharsWithEscapesForAppleScript(CFMutableStringRef inStrRef)
{
	if(inStrRef == NULL)
		return;

  	//replace double quotes & backslashes only
  	CFIndex	idx = ::CFStringGetLength(inStrRef) - 1;
  	UniChar currChar = 0;
	while(idx >= 0)
	{
 		currChar = ::CFStringGetCharacterAtIndex( inStrRef, idx);
 		if( (currChar == '\"') || (currChar == '\\') )
 		{
	 		::CFStringInsert( inStrRef, idx, CFSTR("\\") );
		}
		idx--;
	}
}

//replaces all single quotes with '\'' sequence and adds ' at the beginning and end
void
WrapWithSingleQuotesForShell(CFMutableStringRef inStrRef)
{
	if(inStrRef == NULL)
		return;
  	CFIndex	idx = ::CFStringGetLength(inStrRef) - 1;
	CFIndex lastCharIndex = idx;
  	UniChar currChar = 0;
	Boolean addInFront = true;
	Boolean addAtEnd = true;
	while(idx >= 0)
	{
 		currChar = ::CFStringGetCharacterAtIndex( inStrRef, idx);
 		if( currChar == '\'' )
 		{
			if(idx == lastCharIndex)
			{
				::CFStringAppend( inStrRef, CFSTR("\\'") );//append \' after existing '
				addAtEnd = false;
			}
			else if(idx == 0)
			{
				::CFStringInsert( inStrRef, idx, CFSTR("\\'") );//insert \' before existing '
				addInFront = false;
			}
			else
				::CFStringInsert( inStrRef, idx, CFSTR("'\\'") );//insert '\' before existing '
		}
		idx--;
	}

	if(addInFront)
		::CFStringInsert( inStrRef, 0, CFSTR("'") );//at the beginning

	if(addAtEnd)
		::CFStringAppend( inStrRef, CFSTR("'") );//at the end
}

//replaces \r, \n, \t, \\ with real values
void
ReplaceWhitespaceEscapesWithCharacters(CFMutableStringRef inStrRef)
{
	if(inStrRef == NULL)
		return;

  	CFIndex idx = 0;
	CFIndex	charCount = ::CFStringGetLength(inStrRef);
	if(charCount < 2)//0 or 1 characters cannot be a pair of escapers
		return;

  	UniChar currChar = ::CFStringGetCharacterAtIndex( inStrRef, 0 );
	UniChar nextChar = 0;
	while(idx < charCount )
	{
		//going backwards we get 2 characters at a time to looks for \r \n \t \\ pairs
		if( (idx+1) < charCount)
			nextChar = ::CFStringGetCharacterAtIndex( inStrRef, idx+1 );
			 
 		if( (currChar == '\\') && 
			((nextChar == 'r') || (nextChar == 'n') || (nextChar == 't') || (nextChar == '\\') ) )
 		{
			CFStringRef replacementString = NULL;
			switch(nextChar)
			{
				case 'r':
					replacementString = CFSTR("\r");
				break;
				
				case 'n':
					replacementString = CFSTR("\n");
				break;
				
				case 't':
					replacementString = CFSTR("\t");
				break;
				
				case '\\':
					replacementString = CFSTR("\\");
				break;
			}
			
			assert(replacementString != NULL);
			CFStringReplace(inStrRef, CFRangeMake(idx, 2), replacementString);
			charCount--;//the string is now shorter
			nextChar = 0; //we swallowed the next char

			if( (idx+1) < charCount )
			{
				//replacement disturbed the loop by changing 2 characters into 1,
				//prepare the next loop iteration
				//we fetch new nextChar after the replaced range
				//and it will be assigned to currChar right below for new iteration
				nextChar = ::CFStringGetCharacterAtIndex( inStrRef, idx+1 );
			}
		}

		idx++;
		currChar = nextChar;
		nextChar = 0;
	}
}

void
ReplaceWhitespaceCharactersWithEscapes(CFMutableStringRef inStrRef)
{
	if(inStrRef == NULL)
		return;

  	CFIndex	idx = ::CFStringGetLength(inStrRef) - 1;
  	UniChar currChar = 0;
	while(idx >= 0)
	{
 		currChar = ::CFStringGetCharacterAtIndex( inStrRef, idx );
 		if( (currChar == '\r') || (currChar == '\n') || (currChar == '\t') || (currChar == '\\') )
 		{
			CFStringRef replacementString = NULL;
			switch(currChar)
			{
				case '\r':
					replacementString = CFSTR("\\r");
				break;
				
				case '\n':
					replacementString = CFSTR("\\n");
				break;
				
				case '\t':
					replacementString = CFSTR("\\t");
				break;
				
				case '\\':
					replacementString = CFSTR("\\\\");
				break;
			}
			
			assert(replacementString != NULL);
			CFStringReplace(inStrRef, CFRangeMake(idx, 1), replacementString);
		}
		idx--;
	}

}

CFMutableStringRef
OnMyCommandCM::CreateCommandStringWithObjects(CFArrayRef inFragments, UInt16 escSpecialCharsMode)
{
	if( (inFragments == NULL) || (mCommandList == NULL) || (mCommandCount == 0) || (mObjectList.size() == 0) || (mCurrCommandIndex >= mCommandCount) )
		return NULL;

	CFMutableStringRef theCommand = ::CFStringCreateMutable( kCFAllocatorDefault, 0);
	if(theCommand == NULL)
		return NULL;

	CommandDescription &currCommand = mCommandList[mCurrCommandIndex];

//	TRACE_CSTR("OnMyCommandCM. CreateCommandStringWithObjects\n" );

	if(currCommand.sortMethod == kSortMethodByName)
	{
		SortObjectListByName((CFOptionFlags)currCommand.sortOptions, (bool)currCommand.sortAscending);
	}

	if( ((currCommand.prescannedCommandInfo & kOmcCommandContainsTextObject) != 0) && (mClipboardText == NULL) )
	{
		mClipboardText.Adopt( CMUtils::CreateCFStringFromClipboardText(currCommand.textReplaceOptions), kCFObjDontRetain );
	}

	ACFArr fragments(inFragments);
	CFIndex theCount = fragments.GetCount();
	CFStringRef fragmentRef;
	SelectionIterator *selIterator = NULL;
	if( (currCommand.currState != NULL) && (currCommand.currState->dialogGUID != NULL) )
	{
		OMCDialog *activeDialog = OMCDialog::FindDialogByGUID(currCommand.currState->dialogGUID);
		if(activeDialog != NULL)
			selIterator = activeDialog->GetSelectionIterator();
	}

	for(CFIndex i = 0; i < theCount; i++ )
	{
		if( fragments.GetValueAtIndex(i, fragmentRef) )
		{
			AppendTextToCommand(theCommand, fragmentRef,
								mObjectList.data(), mObjectList.size(), mCurrObjectIndex,
								mClipboardText, currCommand,
								currCommand.mulObjSeparator, currCommand.mulObjPrefix, currCommand.mulObjSuffix,
								escSpecialCharsMode, selIterator );
		}
	}
	
	return theCommand;
}

//normally command is not localized but this API is used to create dynamic comamnd name, which might be localized
CFMutableStringRef
OnMyCommandCM::CreateCommandStringWithText(CFArrayRef inFragments, CFStringRef inObjTextRef, UInt16 escSpecialCharsMode,
											CFStringRef inLocTableName /*= NULL*/, CFBundleRef inLocBundleRef /*= NULL*/)
{
	if( (inFragments == NULL) || (mCommandList == NULL) || (mCommandCount == 0) || (mCurrCommandIndex >= mCommandCount) )
		return NULL;

	CFMutableStringRef theCommand = ::CFStringCreateMutable( kCFAllocatorDefault, 0 );
	if(theCommand == NULL)
		return NULL;

	CommandDescription &currCommand = mCommandList[mCurrCommandIndex];

	ACFArr fragments(inFragments);
	CFIndex theCount = fragments.GetCount();
	CFStringRef fragmentRef;
	SelectionIterator *selIterator = NULL;
	if( (currCommand.currState != NULL) && (currCommand.currState->dialogGUID != NULL) )
	{
		OMCDialog *activeDialog = OMCDialog::FindDialogByGUID(currCommand.currState->dialogGUID);
		if(activeDialog != NULL)
			selIterator = activeDialog->GetSelectionIterator();
	}

	for(CFIndex i = 0; i < theCount; i++ )
	{
		if( fragments.GetValueAtIndex(i, fragmentRef) )
		{
			AppendTextToCommand(theCommand, fragmentRef,
								NULL, 0, -1,
								inObjTextRef, currCommand,
								NULL, NULL, NULL,
								escSpecialCharsMode, selIterator,
								inLocTableName, inLocBundleRef );
		}
	}
	
	return theCommand;
}

CFDictionaryRef
OnMyCommandCM::CreateEnvironmentVariablesDict(CFStringRef inObjTextRef)
{
	if( (mCommandList == NULL) || (mCommandCount == 0) || (mCurrCommandIndex >= mCommandCount) )
		return NULL;

	CommandDescription &currCommand = mCommandList[mCurrCommandIndex];

	if( currCommand.customEnvironVariables == NULL )
		return NULL;

	//mutable copy
	CFObj<CFMutableDictionaryRef> outEnviron( ::CFDictionaryCreateMutableCopy( kCFAllocatorDefault,
													::CFDictionaryGetCount(currCommand.customEnvironVariables),
													currCommand.customEnvironVariables) );
	SelectionIterator *selIterator = NULL;
	if( (currCommand.currState != NULL) && (currCommand.currState->dialogGUID != NULL) )
	{
		OMCDialog *activeDialog = OMCDialog::FindDialogByGUID(currCommand.currState->dialogGUID);
		if(activeDialog != NULL)
			selIterator = activeDialog->GetSelectionIterator();
	}

	if(mObjectList.size() > 0)
	{
		if(currCommand.sortMethod == kSortMethodByName)
		{
			SortObjectListByName((CFOptionFlags)currCommand.sortOptions, (bool)currCommand.sortAscending);
		}

		if( ((currCommand.prescannedCommandInfo & kOmcCommandContainsTextObject) != 0) && (mClipboardText == NULL) )
		{
			mClipboardText.Adopt( CMUtils::CreateCFStringFromClipboardText(currCommand.textReplaceOptions), kCFObjDontRetain );
		}

		PopulateEnvironList( outEnviron,
							mObjectList.data(), mObjectList.size(), mCurrObjectIndex,
							mClipboardText, currCommand,
							currCommand.mulObjSeparator, currCommand.mulObjPrefix, currCommand.mulObjSuffix,
							selIterator );
	
	}
	else //if(inObjTextRef != NULL)
	{
		PopulateEnvironList( outEnviron,
					NULL, 0, -1,
					inObjTextRef, currCommand,
					NULL, NULL, NULL,
					selIterator);
	}

	return outEnviron.Detach();
}

CFMutableStringRef
OnMyCommandCM::CreateCombinedStringWithObjects(CFArrayRef inArray, CFStringRef inLocTableName, CFBundleRef inLocBundleRef)
{
//	TRACE_CSTR("OnMyCommandCM. beginning of CreateCombinedStringWithObject\n" );

//this may be called without object too
//	if( mObjectList == NULL )
//		return NULL;

	if( mCurrCommandIndex >= mCommandCount)
		return NULL;

	CommandDescription &currCommand = mCommandList[mCurrCommandIndex];

	if (inArray == NULL)
		return NULL;
	
	ACFArr objects(inArray);
	CFIndex theCount = objects.GetCount();
	if(theCount == 0)
		return NULL;

	CFMutableStringRef thePath = ::CFStringCreateMutable( kCFAllocatorDefault, 0);

	if(thePath == NULL)
		return NULL;

//	TRACE_CSTR("OnMyCommandCM. inside CreateCombinedStringWithObject\n" );
	
	CFStringRef fragmentRef;
	SelectionIterator *selIterator = NULL;
	if( (currCommand.currState != NULL) && (currCommand.currState->dialogGUID != NULL) )
	{
		OMCDialog *activeDialog = OMCDialog::FindDialogByGUID(currCommand.currState->dialogGUID);
		if(activeDialog != NULL)
			selIterator = activeDialog->GetSelectionIterator();
	}
	
	for(CFIndex i = 0; i < theCount; i++ )
	{
		if( objects.GetValueAtIndex(i, fragmentRef) )
		{
			AppendTextToCommand(thePath, fragmentRef,
								mObjectList.data(), mObjectList.size(), mCurrObjectIndex,
								NULL, currCommand,
								NULL, NULL, NULL,
								kEscapeNone, selIterator,
								inLocTableName, inLocBundleRef );
		}
	}
	
	return thePath;
}



void
OnMyCommandCM::AppendTextToCommand(CFMutableStringRef inCommandRef, CFStringRef inStrRef,
					OneObjProperties *inObjList, CFIndex inObjCount, CFIndex inCurrIndex,
					CFStringRef inObjTextRef, CommandDescription &currCommand,
					CFStringRef inMultiSeparator, CFStringRef inMultiPrefix, CFStringRef inMultiSuffix,
					UInt16 escSpecialCharsMode, SelectionIterator *inSelIterator,
					CFStringRef inLocTableName /*= NULL*/, CFBundleRef inLocBundleRef/*= NULL*/)
{
	CFStringRef inInputStr = mInputText;

	CFStringRef newStrRef = NULL;
	CFObj<CFStringRef> newDel;
	bool deleteNewString = true;

	SInt32 specialWordID = GetSpecialWordID(inStrRef);

	switch(specialWordID)
	{
		case NO_SPECIAL_WORD:
		{
			newStrRef = inStrRef;//we do not own inStrRef so our deleter does not adopt it
			deleteNewString = false; 
			if( (inStrRef != NULL) && (inLocTableName != NULL) && (inLocBundleRef != NULL) )//client wants us to localize text
			{
				newStrRef = ::CFCopyLocalizedStringFromTableInBundle( inStrRef, inLocTableName, inLocBundleRef, "");
				deleteNewString = true;
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
											CreateObjDisplayName, NULL,
											inMultiSeparator, inMultiPrefix, inMultiSuffix,
											escSpecialCharsMode );
		break;
		
		case OBJ_COMMON_PARENT_PATH:
			if(mCommonParentPath == NULL)
				mCommonParentPath.Adopt( CreateCommonParentPath(inObjList, inObjCount), kCFObjDontRetain );
	
			newStrRef = CreateEscapedStringCopy(mCommonParentPath, escSpecialCharsMode);
		break;
		
		case OBJ_PATH_RELATIVE_TO_COMMON_PARENT:
			if(mCommonParentPath == NULL)
				mCommonParentPath.Adopt( CreateCommonParentPath(inObjList, inObjCount), kCFObjDontRetain );
		
		
			newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
											CreateObjPathRelativeToBase, (void *)(CFStringRef)mCommonParentPath,
											inMultiSeparator, inMultiPrefix, inMultiSuffix,
											escSpecialCharsMode );
		break;
		
		case DLG_INPUT_TEXT:
			newStrRef = CreateEscapedStringCopy(inInputStr, escSpecialCharsMode);
		break;

		case DLG_SAVE_AS_PATH:
			newStrRef = CreatePathFromCFURL(currCommand.saveAsPath, escSpecialCharsMode);
		break;
		
		case DLG_SAVE_AS_PARENT_PATH:
			newStrRef = CreateParentPathFromCFURL(currCommand.saveAsPath, escSpecialCharsMode);
		break;
		
		case DLG_SAVE_AS_NAME:
			newStrRef = CreateNameFromCFURL(currCommand.saveAsPath, escSpecialCharsMode);
		break;
		
		case DLG_SAVE_AS_NAME_NO_EXTENSION:
			newStrRef = CreateNameNoExtensionFromCFURL(currCommand.saveAsPath, escSpecialCharsMode);
		break;
		
		case DLG_SAVE_AS_EXTENSION_ONLY:
			newStrRef = CreateExtensionOnlyFromCFURL(currCommand.saveAsPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FILE_PATH:
			newStrRef = CreatePathFromCFURL(currCommand.chooseFilePath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FILE_PARENT_PATH:
			newStrRef = CreateParentPathFromCFURL(currCommand.chooseFilePath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FILE_NAME:
			newStrRef = CreateNameFromCFURL(currCommand.chooseFilePath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FILE_NAME_NO_EXTENSION:
			newStrRef = CreateNameNoExtensionFromCFURL(currCommand.chooseFilePath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FILE_EXTENSION_ONLY:
			newStrRef = CreateExtensionOnlyFromCFURL(currCommand.chooseFilePath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FOLDER_PATH:
			newStrRef = CreatePathFromCFURL(currCommand.chooseFolderPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FOLDER_PARENT_PATH:
			newStrRef = CreateParentPathFromCFURL(currCommand.chooseFolderPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FOLDER_NAME:
			newStrRef = CreateNameFromCFURL(currCommand.chooseFolderPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION:
			newStrRef = CreateNameNoExtensionFromCFURL(currCommand.chooseFolderPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_FOLDER_EXTENSION_ONLY:
			newStrRef = CreateExtensionOnlyFromCFURL(currCommand.chooseFolderPath, escSpecialCharsMode);
		break;

		case DLG_CHOOSE_OBJECT_PATH:
			newStrRef = CreatePathFromCFURL(currCommand.chooseObjectPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_OBJECT_PARENT_PATH:
			newStrRef = CreateParentPathFromCFURL(currCommand.chooseObjectPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_OBJECT_NAME:
			newStrRef = CreateNameFromCFURL(currCommand.chooseObjectPath, escSpecialCharsMode);
		break;
		
		case DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION:
			newStrRef = CreateNameNoExtensionFromCFURL(currCommand.chooseObjectPath, escSpecialCharsMode);
		break;

		case DLG_CHOOSE_OBJECT_EXTENSION_ONLY:
			newStrRef = CreateExtensionOnlyFromCFURL(currCommand.chooseObjectPath, escSpecialCharsMode);
		break;

		case DLG_PASSWORD:
			newStrRef = CreateEscapedStringCopy(inInputStr, escSpecialCharsMode);
		break;
		
		case MY_BUNDLE_PATH:
		{
			if(mBundleRef != NULL)
			{
				CFObj<CFURLRef> myBundlePath( ::CFBundleCopyBundleURL(mBundleRef) );
				newStrRef = CreatePathFromCFURL(myBundlePath, escSpecialCharsMode);
			}
			else
			{
				LOG_CSTR( "OMC: MY_BUNDLE_PATH. bundle ref is NULL\n" );
			}
		}
		break;

		case OMC_RESOURCES_PATH:
		{
			if(mBundleRef != NULL)
			{
				CFObj<CFURLRef> myBundleURL( ::CFBundleCopyBundleURL(mBundleRef) );
				if(myBundleURL != NULL)
				{
					CFObj<CFURLRef> resPath( ::CFURLCreateCopyAppendingPathComponent (
												kCFAllocatorDefault,
												myBundleURL,
												CFSTR("Versions/Current/Resources"),
												true) );
					newStrRef = CreatePathFromCFURL(resPath, escSpecialCharsMode);
				}
			}
			else
			{
				LOG_CSTR( "OMC: OMC_RESOURCES_PATH. bundle ref is NULL\n" );
			}
		}
		break;
		
		case OMC_SUPPORT_PATH:
		{
			if(mBundleRef != NULL)
			{
				CFObj<CFURLRef> myBundleURL( ::CFBundleCopyBundleURL(mBundleRef) );
				if(myBundleURL != NULL)
				{
					CFObj<CFURLRef> supportPath( ::CFURLCreateCopyAppendingPathComponent (
												kCFAllocatorDefault,
												myBundleURL,
												CFSTR("Versions/Current/Support"),
												true) );
					newStrRef = CreatePathFromCFURL(supportPath, escSpecialCharsMode);
				}
			}
			else
			{
				LOG_CSTR( "OMC: OMC_SUPPORT_PATH. bundle ref is NULL\n" );
			}
		}
		break;
	
		case MY_HOST_BUNDLE_PATH:
			newStrRef = CreatePathFromCFURL(mMyHostBundlePath, escSpecialCharsMode);
		break;
		
		case MY_EXTERNAL_BUNDLE_PATH:
		{
			if(currCommand.externalBundlePath != NULL)
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
			OSStatus err = noErr;
			ProcessSerialNumber frontPSN = { kNoProcess, kNoProcess };
			if( mRunningInShortcutsObserver && (mFrontProcess.highLongOfPSN != kNoProcess || mFrontProcess.lowLongOfPSN != kNoProcess) )
				frontPSN = mFrontProcess;
			else
				err = GetFrontProcess( &frontPSN );

			if( err == noErr )
			{
				pid_t frontPID = 0;
				err = GetProcessPID( &frontPSN, &frontPID );
				if(err == noErr)
				{
					newStrRef = CFStringCreateWithFormat( kCFAllocatorDefault, NULL, CFSTR("%d"), frontPID );
				}
			}
			
		}
		break;
		
		case FRONT_APPLICATION_NAME:
		{
			OSStatus err = noErr;
			ProcessSerialNumber frontPSN = { kNoProcess, kNoProcess };
			if( mRunningInShortcutsObserver && (mFrontProcess.highLongOfPSN != kNoProcess || mFrontProcess.lowLongOfPSN != kNoProcess) )
				frontPSN = mFrontProcess;
			else
				err = GetFrontProcess( &frontPSN );

			if( err == noErr )
			{
				CFObj<CFStringRef> frontAppStr;
				CopyProcessName( &frontPSN, &frontAppStr );
				newStrRef = CreateEscapedStringCopy(frontAppStr, escSpecialCharsMode);
			}
		}
		break;

		case NIB_DLG_CONTROL_VALUE:
		case NIB_TABLE_VALUE:
		case NIB_TABLE_ALL_ROWS:
		{
			newStrRef = CreateNibControlValue(specialWordID, currCommand, inStrRef, escSpecialCharsMode, inSelIterator, false);
		}
		break;
		
//no need to escape guid
		case NIB_DLG_GUID:
		{
			if(mCommandList != NULL)
			{
				CommandDescription &currCommand = mCommandList[mCurrCommandIndex];
				if( currCommand.currState != NULL )
				{
					newStrRef = currCommand.currState->dialogGUID;
					deleteNewString = false;
				}
			}
		}
		break;
		
		case CURRENT_COMMAND_GUID:
		{
			if(mCommandList != NULL)
			{
				CommandDescription &currCommand = mCommandList[mCurrCommandIndex];
				newStrRef = GetCommandUniqueID(currCommand);
				deleteNewString = false;
			}
		}
		break;
	}

	if(newStrRef != NULL)
	{
		if(deleteNewString)
			newDel.Adopt(newStrRef);
		::CFStringAppend( inCommandRef, newStrRef );
	}
}


void
OnMyCommandCM::PopulateEnvironList(CFMutableDictionaryRef ioEnvironList,
					OneObjProperties *inObjList, CFIndex inObjCount, CFIndex inCurrIndex,
					CFStringRef inObjTextRef, CommandDescription &currCommand,
					CFStringRef inMultiSeparator, CFStringRef inMultiPrefix, CFStringRef inMultiSuffix,
					SelectionIterator *inSelIterator)
{
	CFStringRef inInputStr = mInputText;

	CFIndex itemCount = ::CFDictionaryGetCount(ioEnvironList);
	if(itemCount == 0)
		return;

    std::vector<void *> keyList(itemCount);
	::CFDictionaryGetKeysAndValues(ioEnvironList, (const void **)keyList.data(), NULL);
	for(CFIndex i = 0; i < itemCount; i++)
	{
		CFStringRef newStrRef = NULL;
		CFObj<CFStringRef> newDel;
		bool deleteNewString = true;

		CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[(size_t)i] );
		SInt32 specialWordID = GetSpecialEnvironWordID(theKey);

		switch(specialWordID)
		{
			case NO_SPECIAL_WORD:
				newStrRef = NULL;//we do not have special dynamic value, so don't set it in dict
			break;
					
			case OBJ_TEXT:
				newStrRef = inObjTextRef;
				deleteNewString = false;//we do not own inObjTextRef so we should never delete it
			break;
			
			case OBJ_PATH:
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
				if(mCommonParentPath == NULL)
					mCommonParentPath.Adopt( CreateCommonParentPath(inObjList, inObjCount), kCFObjDontRetain );
		
				newStrRef = mCommonParentPath;
				deleteNewString = false;
			break;
			
			case OBJ_PATH_RELATIVE_TO_COMMON_PARENT:
				if(mCommonParentPath == NULL)
					mCommonParentPath.Adopt( CreateCommonParentPath(inObjList, inObjCount), kCFObjDontRetain );
			
			
				newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
												CreateObjPathRelativeToBase, (void *)(CFStringRef)mCommonParentPath,
												inMultiSeparator, inMultiPrefix, inMultiSuffix,
												kEscapeNone );
			break;
			
			case DLG_INPUT_TEXT:
				newStrRef = inInputStr;
				deleteNewString = false;
			break;

			case DLG_SAVE_AS_PATH:
				newStrRef = CreatePathFromCFURL(currCommand.saveAsPath, kEscapeNone);
			break;
			
			case DLG_SAVE_AS_PARENT_PATH:
				newStrRef = CreateParentPathFromCFURL(currCommand.saveAsPath, kEscapeNone);
			break;
			
			case DLG_SAVE_AS_NAME:
				newStrRef = CreateNameFromCFURL(currCommand.saveAsPath, kEscapeNone);
			break;
			
			case DLG_SAVE_AS_NAME_NO_EXTENSION:
				newStrRef = CreateNameNoExtensionFromCFURL(currCommand.saveAsPath, kEscapeNone);
			break;
			
			case DLG_SAVE_AS_EXTENSION_ONLY:
				newStrRef = CreateExtensionOnlyFromCFURL(currCommand.saveAsPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FILE_PATH:
				newStrRef = CreatePathFromCFURL(currCommand.chooseFilePath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FILE_PARENT_PATH:
				newStrRef = CreateParentPathFromCFURL(currCommand.chooseFilePath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FILE_NAME:
				newStrRef = CreateNameFromCFURL(currCommand.chooseFilePath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FILE_NAME_NO_EXTENSION:
				newStrRef = CreateNameNoExtensionFromCFURL(currCommand.chooseFilePath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FILE_EXTENSION_ONLY:
				newStrRef = CreateExtensionOnlyFromCFURL(currCommand.chooseFilePath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FOLDER_PATH:
				newStrRef = CreatePathFromCFURL(currCommand.chooseFolderPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FOLDER_PARENT_PATH:
				newStrRef = CreateParentPathFromCFURL(currCommand.chooseFolderPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FOLDER_NAME:
				newStrRef = CreateNameFromCFURL(currCommand.chooseFolderPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION:
				newStrRef = CreateNameNoExtensionFromCFURL(currCommand.chooseFolderPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_FOLDER_EXTENSION_ONLY:
				newStrRef = CreateExtensionOnlyFromCFURL(currCommand.chooseFolderPath, kEscapeNone);
			break;

			case DLG_CHOOSE_OBJECT_PATH:
				newStrRef = CreatePathFromCFURL(currCommand.chooseObjectPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_OBJECT_PARENT_PATH:
				newStrRef = CreateParentPathFromCFURL(currCommand.chooseObjectPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_OBJECT_NAME:
				newStrRef = CreateNameFromCFURL(currCommand.chooseObjectPath, kEscapeNone);
			break;
			
			case DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION:
				newStrRef = CreateNameNoExtensionFromCFURL(currCommand.chooseObjectPath, kEscapeNone);
			break;

			case DLG_CHOOSE_OBJECT_EXTENSION_ONLY:
				newStrRef = CreateExtensionOnlyFromCFURL(currCommand.chooseObjectPath, kEscapeNone);
			break;

			case DLG_PASSWORD:
				newStrRef = inInputStr;
				deleteNewString = false;
			break;
			
			//this is deprecated. framework paths are preferred in version 2.0
			case MY_BUNDLE_PATH:
			{
				if(mBundleRef != NULL)
				{
					CFObj<CFURLRef> myBundlePath( ::CFBundleCopyBundleURL(mBundleRef) );
					if(myBundlePath != NULL)
						newStrRef = CreatePathFromCFURL(myBundlePath, kEscapeNone);
				}
				else
				{
					LOG_CSTR( "OMC: MY_BUNDLE_PATH. bundle ref is NULL\n" );
				}
			}
			break;
			
			case OMC_RESOURCES_PATH:
			{
				if(mBundleRef != NULL)
				{
					CFObj<CFURLRef> myBundleURL( ::CFBundleCopyBundleURL(mBundleRef) );
					if(myBundleURL != NULL)
					{
						CFObj<CFURLRef> resPath( ::CFURLCreateCopyAppendingPathComponent (
													kCFAllocatorDefault,
													myBundleURL,
													CFSTR("Versions/Current/Resources"),
													true) );
						newStrRef = CreatePathFromCFURL(resPath, kEscapeNone);
					}
				}
				else
				{
					LOG_CSTR( "OMC: OMC_RESOURCES_PATH. bundle ref is NULL\n" );
				}
			}
			break;
			
			case OMC_SUPPORT_PATH:
			{
				if(mBundleRef != NULL)
				{
					CFObj<CFURLRef> myBundleURL( ::CFBundleCopyBundleURL(mBundleRef) );
					if(myBundleURL != NULL)
					{
						CFObj<CFURLRef> supportPath( ::CFURLCreateCopyAppendingPathComponent (
													kCFAllocatorDefault,
													myBundleURL,
													CFSTR("Versions/Current/Support"),
													true) );
						newStrRef = CreatePathFromCFURL(supportPath, kEscapeNone);
					}
				}
				else
				{
					LOG_CSTR( "OMC: OMC_SUPPORT_PATH. bundle ref is NULL\n" );
				}
			}
			break;

			case MY_HOST_BUNDLE_PATH:
				newStrRef = CreatePathFromCFURL(mMyHostBundlePath, kEscapeNone);
			break;
			
			case MY_EXTERNAL_BUNDLE_PATH:
			{
				if(currCommand.externalBundlePath != NULL)
				{
					newStrRef = currCommand.externalBundlePath;
					deleteNewString = false;
				}
				else
				{
					newStrRef = CreateDefaultExternBundleString(currCommand.name);
				}
			}
			break;

	//no need to escape process id
			case FRONT_PROCESS_ID:
			{
				OSStatus err = noErr;
				ProcessSerialNumber frontPSN = { kNoProcess, kNoProcess };
				if( mRunningInShortcutsObserver && (mFrontProcess.highLongOfPSN != kNoProcess || mFrontProcess.lowLongOfPSN != kNoProcess) )
					frontPSN = mFrontProcess;
				else
					err = GetFrontProcess( &frontPSN );

				if( err == noErr )
				{
					pid_t frontPID = 0;
					err = GetProcessPID( &frontPSN, &frontPID );
					if(err == noErr)
					{
						newStrRef = CFStringCreateWithFormat( kCFAllocatorDefault, NULL, CFSTR("%d"), frontPID );
					}
				}
				
			}
			break;
			
			case FRONT_APPLICATION_NAME:
			{
				OSStatus err = noErr;
				ProcessSerialNumber frontPSN = { kNoProcess, kNoProcess };
				if( mRunningInShortcutsObserver && (mFrontProcess.highLongOfPSN != kNoProcess || mFrontProcess.lowLongOfPSN != kNoProcess) )
					frontPSN = mFrontProcess;
				else
					err = GetFrontProcess( &frontPSN );

				if( err == noErr )
				{
					CFStringRef frontAppStr = NULL;
					CopyProcessName( &frontPSN, &frontAppStr );
					newStrRef = frontAppStr;
				}
			}
			break;

			case NIB_DLG_CONTROL_VALUE:
			case NIB_TABLE_VALUE:
			case NIB_TABLE_ALL_ROWS:
			{
				newStrRef = CreateNibControlValue(specialWordID, currCommand, theKey, kEscapeNone, inSelIterator, true);
			}
			break;
			
	//no need to escape guid
			case NIB_DLG_GUID:
			{
				if(mCommandList != NULL)
				{
					CommandDescription &currCommand = mCommandList[mCurrCommandIndex];
					if( currCommand.currState != NULL )
					{
						newStrRef = currCommand.currState->dialogGUID;
						deleteNewString = false;
					}
				}
			}
			break;
			
			case CURRENT_COMMAND_GUID:
			{
				if(mCommandList != NULL)
				{
					CommandDescription &currCommand = mCommandList[mCurrCommandIndex];
					newStrRef = GetCommandUniqueID(currCommand);
					deleteNewString = false;
				}
			}
			break;
		}

		if(newStrRef != NULL)
		{
			if(deleteNewString)
				newDel.Adopt(newStrRef);
			::CFDictionarySetValue(ioEnvironList, theKey, newStrRef);
		}
	}
}


CFStringRef
OnMyCommandCM::CreateDynamicCommandName(const CommandDescription &currCommand, CFStringRef inLocTableName, CFBundleRef inLocBundleRef)
{
	CFStringRef commandName = NULL;
	if( (mObjectList.size() > 1) && (currCommand.namePlural != NULL) )
	{
		commandName = currCommand.namePlural;
		if(inLocTableName != NULL)
			commandName = ::CFCopyLocalizedStringFromTableInBundle( commandName, inLocTableName, inLocBundleRef, "");
		else
			::CFRetain(commandName);
	}
	else if( currCommand.nameIsDynamic && currCommand.nameContainsText && (mContextText != NULL) )
	{
		//clip the text here to reasonable size,
		const CFIndex kMaxCharCount = 60;
		CFIndex totalLen = ::CFStringGetLength( mContextText );
		CFIndex theLen = totalLen;
		CFObj<CFMutableStringRef> newString;
		bool textIsClipped = false;
		if(theLen > kMaxCharCount)
		{
			CFObj<CFStringRef> shortString( ::CFStringCreateWithSubstring(kCFAllocatorDefault, mContextText, CFRangeMake(0, kMaxCharCount)) );
			newString.Adopt( ::CFStringCreateMutableCopy(kCFAllocatorDefault, kMaxCharCount + 4, shortString) );
			textIsClipped = true;
		}
		else
		{
			newString.Adopt( ::CFStringCreateMutableCopy(kCFAllocatorDefault, kMaxCharCount + 4, mContextText) );
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
			commandName = CreateCommandStringWithText(currCommand.name, shortenedString, kEscapeNone, inLocTableName, inLocBundleRef);
		}
		else
		{//short enough and no newlines to use the whole string
			commandName = CreateCommandStringWithText(currCommand.name, newString, kEscapeNone, inLocTableName, inLocBundleRef);
		}
	}
	else
	{
		commandName = CreateCombinedStringWithObjects(currCommand.name, inLocTableName, inLocBundleRef);
	}

	return commandName;
}

void
OnMyCommandCM::CreateTextContext(const CommandDescription &currCommand, const AEDesc *inContext)
{
	if(mContextText != NULL)
		return;//already created

	if( mIsTextContext && (currCommand.activationMode != kActiveClipboardText) )
	{
#if IN_PROC_CM //long deprecated by Apple
        mContextText.Adopt( currentCocoaStringSelection(), kCFObjDontRetain);
		if((mContextText != NULL) && (currCommand.textReplaceOptions != kTextReplaceNothing))
		{
			CFMutableStringRef mutableCopy = ::CFStringCreateMutableCopy(kCFAllocatorDefault, 0, mContextText);
			CFRange wholeRange = CFRangeMake(0, CFStringGetLength(mutableCopy));

			if(currCommand.textReplaceOptions == kTextReplaceLFsWithCRs)
				::CFStringFindAndReplace(mutableCopy, CFSTR("\n"), CFSTR("\r"), wholeRange, 0);
			else if(currCommand.textReplaceOptions == kTextReplaceCRsWithLFs)
				::CFStringFindAndReplace(mutableCopy, CFSTR("\r"), CFSTR("\n"), wholeRange, 0);
			mContextText.Adopt( mutableCopy, kCFObjDontRetain);
		}
#endif //IN_PROC_CM
		
		if( (inContext != NULL) && (mContextText == NULL) && (mIsNullContext == false) )
			mContextText.Adopt( CMUtils::CreateCFStringFromAEDesc( *inContext, currCommand.textReplaceOptions ), kCFObjDontRetain);
		
	}
	else if(mIsTextInClipboard)
	{
		mContextText.Adopt( CMUtils::CreateCFStringFromClipboardText(currCommand.textReplaceOptions), kCFObjDontRetain );
		mClipboardText.Adopt( mContextText, kCFObjRetain );
	}
}

#pragma mark -

CFStringRef
CreateObjPath(OneObjProperties *inObj, void *)
{
	if(inObj == NULL)
		return NULL;

	if(inObj->mURLRef == NULL)
		inObj->mURLRef = ::CFURLCreateFromFSRef( kCFAllocatorDefault, &(inObj->mRef) );

	if(inObj->mURLRef != NULL)
 		return ::CFURLCopyFileSystemPath(inObj->mURLRef, kCFURLPOSIXPathStyle);

 	return NULL;
}

CFStringRef
CreateObjPathNoExtension(OneObjProperties *inObj, void *)
{
	if(inObj == NULL)
		return NULL;

	if(inObj->mURLRef == NULL)
		inObj->mURLRef = ::CFURLCreateFromFSRef( kCFAllocatorDefault, &(inObj->mRef) );

	if(inObj->mURLRef != NULL)
  	{
		CFObj<CFURLRef> newURL( ::CFURLCreateCopyDeletingPathExtension( kCFAllocatorDefault, inObj->mURLRef ) );
		if(newURL != NULL)
 			return ::CFURLCopyFileSystemPath(newURL, kCFURLPOSIXPathStyle);
	}
	return NULL;
}


CFStringRef
CreateParentPath(OneObjProperties *inObj, void *)
{
	if(inObj == NULL)
		return NULL;

	if(inObj->mURLRef == NULL)
		inObj->mURLRef = ::CFURLCreateFromFSRef( kCFAllocatorDefault, &(inObj->mRef) );

	if(inObj->mURLRef != NULL)
  	{
 		CFObj<CFURLRef> newURL( ::CFURLCreateCopyDeletingLastPathComponent( kCFAllocatorDefault, inObj->mURLRef ) );
		if(newURL != NULL)
 			return ::CFURLCopyFileSystemPath(newURL, kCFURLPOSIXPathStyle);
	}
	return NULL;
}


CFStringRef
CreateObjName(OneObjProperties *inObj, void *)
{
	if(inObj == NULL)
		return NULL;

	if(inObj->mURLRef == NULL)
		inObj->mURLRef = ::CFURLCreateFromFSRef( kCFAllocatorDefault, &(inObj->mRef) );

	if(inObj->mURLRef != NULL)
		return ::CFURLCopyLastPathComponent(inObj->mURLRef);

	return NULL;
}

CFStringRef
CreateObjNameNoExtension(OneObjProperties *inObj, void *)
{
	if(inObj == NULL)
		return NULL;

	if(inObj->mURLRef == NULL)
		inObj->mURLRef = ::CFURLCreateFromFSRef( kCFAllocatorDefault, &(inObj->mRef) );

	if(inObj->mURLRef != NULL)
  	{
		CFObj<CFURLRef> newURL( ::CFURLCreateCopyDeletingPathExtension( kCFAllocatorDefault, inObj->mURLRef ) );
		if(newURL != NULL)
			return ::CFURLCopyLastPathComponent(newURL);
	}

	return NULL;
}


CFStringRef
CreateObjExtensionOnly(OneObjProperties *inObj, void *)
{//we already have the extension in our data
	if(inObj == NULL)
		return NULL;

	if(inObj->mExtension != NULL)
		return ::CFStringCreateCopy(kCFAllocatorDefault, inObj->mExtension);

	return NULL;
}


CFStringRef
CreateObjDisplayName(OneObjProperties *inObj, void *)
{
	if(inObj == NULL)
		return NULL;

	CFStringRef theName = NULL;
	OSStatus err = ::LSCopyDisplayNameForRef(  &(inObj->mRef), &theName );
	if(err == noErr)
	{
		return theName;
	}

	return NULL;
}

CFStringRef
CreateObjPathRelativeToBase(OneObjProperties *inObj, void *ioParam)
{
	if(inObj == NULL)
		return NULL;

	if(ioParam == NULL)
	{//no base is provided, fall back to full path
		return CreateObjPath(inObj, NULL);
	}

	CFStringRef commonParentPath = (CFStringRef)ioParam;

	if(inObj->mURLRef == NULL)
		inObj->mURLRef = ::CFURLCreateFromFSRef( kCFAllocatorDefault, &(inObj->mRef) );

	if(inObj->mURLRef != NULL)
  	{
 		CFObj<CFStringRef> fullPath( ::CFURLCopyFileSystemPath(inObj->mURLRef, kCFURLPOSIXPathStyle) );
 		if(fullPath != NULL)
 		{
 			//at this point we assume that fullPath starts with commonParentPath
 			//we do not check it
 			CFRange theRange;
 			theRange.location = 0;
    		theRange.length = ::CFStringGetLength(commonParentPath);

			//relative path will not be longer than full path
			CFMutableStringRef	relPath = ::CFStringCreateMutableCopy(kCFAllocatorDefault, ::CFStringGetLength(fullPath), fullPath);
 			::CFStringDelete(relPath, theRange);//delete the first part of the path which we assume is the same as base path
 			return relPath;
 		}
 	}
 	return NULL;
}


CFStringRef
CreateStringFromListOrSingleObject( OneObjProperties *inObjList, CFIndex inObjCount, CFIndex inCurrIndex,
									CreateObjProc inObjProc, void *ioParam,
									CFStringRef inMultiSeparator, CFStringRef inPrefix, CFStringRef inSuffix,
									UInt16 escSpecialCharsMode )
{
	if(inObjList == NULL)
		return NULL;

	OneObjProperties *oneObj;
	CFStringRef newStrRef = NULL;

	if(inCurrIndex == -1)//process all together
	{
		CFMutableStringRef mutableStr = ::CFStringCreateMutable(kCFAllocatorDefault, 0);
		for(CFIndex i = 0; i < inObjCount; i++)
		{
			oneObj = inObjList + i;
			newStrRef = (*inObjProc)( oneObj, ioParam );
			
			if(newStrRef != NULL)
			{
				CFStringRef  cpyStrRef = CreateEscapedStringCopy(newStrRef, escSpecialCharsMode);
				if(cpyStrRef != NULL)
				{
					CFObj<CFStringRef> strDel(newStrRef);//we have a copy, we may dispose of the original
					newStrRef = cpyStrRef;
				}
				
				CFObj<CFStringRef> newDel(newStrRef);

				if(inPrefix != NULL)
				{
					::CFStringAppend( mutableStr, inPrefix );
				}
				
				::CFStringAppend( mutableStr, newStrRef );
				
				if(inSuffix != NULL)
				{
					::CFStringAppend( mutableStr, inSuffix );
				}

				if( (inMultiSeparator != NULL) && i < (inObjCount-1) )
				{//add separator, but not after the last item
					::CFStringAppend( mutableStr, inMultiSeparator );
				}
			}
		}
		newStrRef = mutableStr;//assign new string to our main variable
	}
	else if(inCurrIndex < inObjCount)
	{//process just one
		oneObj = inObjList + inCurrIndex;
		newStrRef = (*inObjProc)( oneObj, ioParam );

		if( newStrRef != NULL )
  		{
  			CFStringRef  cpyStrRef = CreateEscapedStringCopy(newStrRef, escSpecialCharsMode);
			if(cpyStrRef != NULL)
			{
				CFObj<CFStringRef> strDel(newStrRef);//we have a copy, we may dispose of the original
				newStrRef = cpyStrRef;
			}
		}
	}

	return newStrRef;
}


CFStringRef
CreateCommonParentPath(OneObjProperties *inObjList, CFIndex inObjCount )
{
	if( (inObjList == NULL) || (inObjCount == 0) )
		return NULL;

	OneObjProperties *oneObj;
    std::vector<CFMutableArrayRef> arrayList(inObjCount);
	memset(arrayList.data(), 0, inObjCount*sizeof(CFMutableArrayRef));

//create parent paths starting from branches, going to the root,
//putting in reverse order, so it will be easier to iterate from the root later
	for (CFIndex i = 0; i < inObjCount; i++)
	{
		oneObj = inObjList + i;

		CFMutableArrayRef pathsArray = ::CFArrayCreateMutable( kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks );
		arrayList[i] = pathsArray;
		if(pathsArray != NULL)
		{
			CFURLRef newURL = ::CFURLCreateFromFSRef( kCFAllocatorDefault, &(oneObj->mRef) );

			//we dispose of all these URLs, we leave only strings derived from them
 			while(newURL != NULL)
 			{
 				CFObj<CFURLRef> urlDel(newURL);//delete previous when we are done
				newURL = ::CFURLCreateCopyDeletingLastPathComponent( kCFAllocatorDefault, newURL );
				if(newURL != NULL)
				{
					CFObj<CFStringRef> aPath( ::CFURLCopyFileSystemPath(newURL, kCFURLPOSIXPathStyle) );
					::CFArrayInsertValueAtIndex( pathsArray, 0, aPath.Get());//grand parent is inserted in front

					if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("/"), aPath.Get(), 0) ) //we reached the top
					{	
						::CFRelease(newURL);//delete current URL and end the loop
						newURL = NULL;
					}
				}
			}
		}
	}

//get minimum count of parent folders in all our paths
	CFIndex minCount = 0x7FFFFFFF;
	for(CFIndex i = 0; i < inObjCount; i++)
	{
		if(arrayList[i] != NULL)
		{
			CFIndex theCount = ::CFArrayGetCount(arrayList[i]);
			if(theCount < minCount)
				minCount = theCount;
		}
		else
		{
			minCount = 0;
			break;
		}
	}

	CFStringRef commonParentPath = NULL;

//find common parent
	if( (minCount > 0) && (minCount < 0x7FFFFFFF) )
	{//if minimum count is valid
	//at this point, all items in arrayList are non-NULL
		UInt32 commonPathLevel= 0;
		for( CFIndex pathLevel = 0; pathLevel < minCount; pathLevel++ )
		{
			//check given path level for each object
			CFTypeRef theItem = ::CFArrayGetValueAtIndex( arrayList[0], pathLevel);
			CFStringRef firstPath = ACFType<CFStringRef>::DynamicCast(theItem);
			Boolean allEqual = true;
			for(CFIndex i = 1; i < inObjCount; i++)
			{
				theItem = ::CFArrayGetValueAtIndex( arrayList[i], pathLevel);
				CFStringRef anotherPath = ACFType<CFStringRef>::DynamicCast(theItem);
				if( (firstPath != NULL) && (anotherPath != NULL) &&
					kCFCompareEqualTo != ::CFStringCompare( firstPath, anotherPath, 0 ) )
				{
					allEqual = false;
					break;
				}
			}
			
			if(allEqual == true)
			{//all paths are equal at this level
				commonPathLevel = pathLevel;
			}
			else
			{//we went too far, do not check any further
				break;
			}
		}

		CFTypeRef commonLevelItem = ::CFArrayGetValueAtIndex( arrayList[0], commonPathLevel);
		commonParentPath = ACFType<CFStringRef>::DynamicCast(commonLevelItem);
		//Assert(commonParentPath != NULL);
		
		if(commonParentPath != NULL)
		{
			//add slash at the end of parent path unless it is a root folder which has it already
			if( kCFCompareEqualTo == ::CFStringCompare( commonParentPath, CFSTR("/"), 0 ) )
			{
				::CFRetain(commonParentPath);//prevent from deleting, we return this string
			}
			else
			{//we are adding just one character
				CFMutableStringRef	modifStr = ::CFStringCreateMutableCopy( kCFAllocatorDefault,
																		::CFStringGetLength(commonParentPath)+1,
																		commonParentPath );
				if(modifStr != NULL)
				{
					::CFStringAppend( modifStr, CFSTR("/") );
					commonParentPath = modifStr;
				}
				else
					commonParentPath = NULL;//failed
			}

			DEBUG_CFSTR( commonParentPath );
		}
	}

//dispose of path arrays
	for(CFIndex i = 0; i < inObjCount; i++)
	{
		if(arrayList[i] != NULL)
		{
			::CFRelease( arrayList[i] );
			arrayList[i] = NULL;
		}
	}
	
	return commonParentPath;
}

#pragma mark -

extern "C"
{

CFStringRef
CreatePathFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode)
{
	CFStringRef newStrRef = NULL;
	if(inPath != NULL)
	{
		newStrRef = ::CFURLCopyFileSystemPath(inPath, kCFURLPOSIXPathStyle);
		CFStringRef cpyStrRef = CreateEscapedStringCopy(newStrRef, escSpecialCharsMode);
		if(cpyStrRef != NULL)
		{
			CFObj<CFStringRef> strDel(newStrRef);//we have a copy, we may dispose of the original
			newStrRef = cpyStrRef;
		}
	}
	return newStrRef;
}

CFStringRef
CreateParentPathFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode)
{
	CFStringRef newStrRef = NULL;
	if(inPath != NULL)
	{
		CFObj<CFURLRef> newURL( ::CFURLCreateCopyDeletingLastPathComponent( kCFAllocatorDefault, inPath ) );
		newStrRef = ::CFURLCopyFileSystemPath(newURL, kCFURLPOSIXPathStyle);
		CFStringRef  cpyStrRef = CreateEscapedStringCopy(newStrRef, escSpecialCharsMode);
		if(cpyStrRef != NULL)
		{
			CFObj<CFStringRef> strDel(newStrRef);//we have a copy, we may dispose of the original
			newStrRef = cpyStrRef;
		}
	}
	return newStrRef;
}

CFStringRef
CreateNameFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode)
{
	CFStringRef newStrRef = NULL;
	if(inPath != NULL)
	{
		newStrRef = ::CFURLCopyLastPathComponent(inPath);
		CFStringRef  cpyStrRef = CreateEscapedStringCopy(newStrRef, escSpecialCharsMode);
		if(cpyStrRef != NULL)
		{
			CFObj<CFStringRef> strDel(newStrRef);//we have a copy, we may dispose of the original
			newStrRef = cpyStrRef;
		}
	}
	return newStrRef;
}

CFStringRef
CreateNameNoExtensionFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode)
{
	CFStringRef newStrRef = NULL;
	if(inPath != NULL)
  	{
		CFObj<CFURLRef> newURL( ::CFURLCreateCopyDeletingPathExtension( kCFAllocatorDefault, inPath ) );
		if(newURL != NULL)
		{
			newStrRef = ::CFURLCopyLastPathComponent(newURL);
			CFStringRef  cpyStrRef = CreateEscapedStringCopy(newStrRef, escSpecialCharsMode);
			if(cpyStrRef != NULL)
			{
				CFObj<CFStringRef> strDel(newStrRef);//we have a copy, we may dispose of the original
				newStrRef = cpyStrRef;
			}		
		}
	}
	return newStrRef;
}

CFStringRef
CreateExtensionOnlyFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode)
{
	CFStringRef newStrRef = NULL;
	if(inPath != NULL)
  	{
		newStrRef = ::CFURLCopyPathExtension(inPath);
		CFStringRef  cpyStrRef = CreateEscapedStringCopy(newStrRef, escSpecialCharsMode);
		if(cpyStrRef != NULL)
		{
			CFObj<CFStringRef> strDel(newStrRef);//we have a copy, we may dispose of the original
			newStrRef = cpyStrRef;
		}
	}
	return newStrRef;
}

#pragma mark -

//this function always creates a copy of string so you may release original string when not needed
CFStringRef
CreateEscapedStringCopy(CFStringRef inStrRef, UInt16 escSpecialCharsMode)
{
	if( inStrRef != NULL )
  	{
  		if(escSpecialCharsMode == kEscapeWithBackslash)
  		{
  			CFMutableStringRef	modifStr = ::CFStringCreateMutableCopy(kCFAllocatorDefault, 0, inStrRef);
			if(modifStr != NULL)
			{
				ReplaceSpecialCharsWithBackslashEscapes(modifStr);
				return modifStr;
			}
		}
		else if( escSpecialCharsMode == kEscapeWithPercent )
		{
			return ::CFURLCreateStringByAddingPercentEscapes(NULL, inStrRef, NULL, NULL, kCFStringEncodingUTF8);
		}
		else if( escSpecialCharsMode == kEscapeWithPercentAll )
		{
			//escape all illegal URL chars and all non-alphanumeric legal chars
			//legal chars need to be escaped in order ot prevent conflicts in shell execution
			return ::CFURLCreateStringByAddingPercentEscapes(NULL, inStrRef, NULL,
							CFSTR("!$&'()*+,-./:;=?@_~"), kCFStringEncodingUTF8);
		}
		else if( escSpecialCharsMode == kEscapeForAppleScript )
		{
			CFMutableStringRef	modifStr = ::CFStringCreateMutableCopy(kCFAllocatorDefault, 0, inStrRef);
			if(modifStr != NULL)
			{
				ReplaceSpecialCharsWithEscapesForAppleScript(modifStr);
				return modifStr;
			}
		}
		else if( escSpecialCharsMode == kEscapeWrapWithSingleQuotesForShell )
		{
			CFMutableStringRef	modifStr = ::CFStringCreateMutableCopy(kCFAllocatorDefault, 0, inStrRef);
			if(modifStr != NULL)
			{
				WrapWithSingleQuotesForShell(modifStr);
				return modifStr;
			}
		}
		else
		{
			::CFRetain(inStrRef);
			return inStrRef;
		}
	}
	return NULL;
}

CFStringRef
CreateCombinedString( CFArrayRef inStringsArray, CFStringRef inSeparator, CFStringRef inPrefix, CFStringRef inSuffix, UInt16 escSpecialCharsMode )
{
	if(inStringsArray == NULL)
		return NULL;

	CFIndex itemCount = ::CFArrayGetCount(inStringsArray);

	CFMutableStringRef mutableStr = ::CFStringCreateMutable(kCFAllocatorDefault, 0);
	for(CFIndex i = 0; i < itemCount; i++)
	{
		CFTypeRef oneItem = ::CFArrayGetValueAtIndex(inStringsArray,i);
		CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( oneItem );
		if(oneString != NULL)
		{
			CFObj<CFStringRef> escapedString( CreateEscapedStringCopy(oneString, escSpecialCharsMode) );

			if(inPrefix != NULL)
			{
				::CFStringAppend( mutableStr, inPrefix );
			}
			
			::CFStringAppend( mutableStr, escapedString );
			
			if(inSuffix != NULL)
			{
				::CFStringAppend( mutableStr, inSuffix );
			}

			if( (inSeparator != NULL) && i < (itemCount-1) )
			{//add separator, but not after the last item
				::CFStringAppend( mutableStr, inSeparator );
			}
		}
	}
	return mutableStr;
}

}; //extern "C"

#pragma mark -


void
OnMyCommandCM::GetDialogControlValues( CommandDescription &currCommand, OMCDialog &inDialog )
{
	//get values for all controls in the dialog
	//the code is generic to handle tables
	//regular controls do not have columns and the use 0 for column number ot store their values
	//column index 0 is a meta value for table and means: get array of all column values
	//this way a regular method of querrying controls works with table too: produces a selected row strings
	if(mNibControlValues == NULL)
		return;

	//this is the optimized version to query only used controls
	CFIndex controlCount = ::CFDictionaryGetCount(mNibControlValues);
	if(controlCount <= 0)
		return;

    std::vector<CFStringRef> keyList(controlCount);
    std::vector<CFTypeRef> valueList(controlCount);
	::CFDictionaryGetKeysAndValues(mNibControlValues, (const void **)keyList.data(), (const void **)valueList.data() );

	for(CFIndex i = 0; i < controlCount; i++)
	{
		CFMutableDictionaryRef columnIds = ACFType<CFMutableDictionaryRef>::DynamicCast( valueList[i] );
		if(columnIds != NULL)
		{
			CFIndex columnCount = ::CFDictionaryGetCount(columnIds);
			if(columnCount > 0)
			{
				//get the list column ids which was filled during command prescan phase
                std::vector<intptr_t> columnIdList(columnCount);
				::CFDictionaryGetKeysAndValues(columnIds, (const void **)columnIdList.data(), NULL );
								
				//cache each column value requested for this control
				for(CFIndex j = 0; j < columnCount; j++)
				{
					CFIndex columnIndex = columnIdList[j];
					CFObj<CFDictionaryRef> customProperties;
					SelectionIterator *selIterator = NULL;//we do not support selection iterator for command which called us, only subcommands
					
					//SInt32 controlID = keyList[i];
					CFStringRef controlIDWithModifiers = keyList[i];
					UInt32 valueModifiers = 0;
                    CFObj<CFStringRef> controlID( CreateControlIDByStrippingModifiers(controlIDWithModifiers, valueModifiers) );

					if( (valueModifiers & kControlModifier_AllRows) != 0 )
					{
						selIterator = AllRowsIterator_Create();
					}
					CFObj<CFTypeRef> oneValue( inDialog.CopyControlValue(controlID, columnIndex, selIterator, &customProperties) );

					if(selIterator != NULL)
					{
						SelectionIterator_Release(selIterator);
						selIterator = NULL;
					}

					if(oneValue != NULL)
					{
						::CFDictionarySetValue( columnIds, (const void *)columnIndex, (const void *)(CFTypeRef)oneValue); //CFTypeRef is retained
					
						//custom escaping, prefix, suffix or separator
						if(customProperties != NULL)
						{
							if( mNibControlCustomProperties == NULL )//lazy creation. sophisticated, probably rare case
								mNibControlCustomProperties.Adopt( ::CFDictionaryCreateMutable(
																		kCFAllocatorDefault,
																		0,
																		NULL,//keyCallBacks,
																		&kCFTypeDictionaryValueCallBacks ),
																	kCFObjDontRetain);//values will be CFStringRefs
							if( mNibControlCustomProperties != NULL )
								::CFDictionarySetValue( mNibControlCustomProperties,
														(const void *)keyList[i],
														(const void *)(CFDictionaryRef)customProperties); //CFTypeRef is retained
						}
					}
				}
			}
		}
	}
}

//string or array of strings
CFStringRef
OnMyCommandCM::CreateNibControlValue(SInt32 inSpecialWordID, const CommandDescription &currCommand, CFStringRef inNibControlString, UInt16 escSpecialCharsMode, SelectionIterator *inSelIterator, bool isEnvStyle)
{
	CFObj<CFTypeRef> oneValue;
	CFIndex columnIndex = 0;//init to all columns
	CFObj<CFStringRef> controlID;	

	DEBUG_CFSTR(CFSTR("OnMyCommandCM::CreateNibControlValue"));

	if( inSpecialWordID == NIB_DLG_CONTROL_VALUE ) //regular control query
		controlID.Adopt( CreateControlIDFromString(inNibControlString, isEnvStyle), kCFObjDontRetain );
	else if( (inSpecialWordID == NIB_TABLE_VALUE) || (inSpecialWordID == NIB_TABLE_ALL_ROWS) ) //table control query
		controlID.Adopt( CreateTableIDAndColumnFromString(inNibControlString, columnIndex, inSpecialWordID == NIB_TABLE_ALL_ROWS, isEnvStyle), kCFObjDontRetain );

	DEBUG_CFSTR((CFStringRef)controlID);

	CFObj<CFDictionaryRef> customProperties; 
	OMCDialog *activeDialog = NULL;
	if( (currCommand.currState != NULL) && (currCommand.currState->dialogGUID != NULL) )
		activeDialog = OMCDialog::FindDialogByGUID(currCommand.currState->dialogGUID);
	
	if(activeDialog != NULL)
	{//fresh from current dialog
		DEBUG_CSTR("\tgetting value fresh from current dialog\n");
		SelectionIterator * newSelectionIterator = NULL;
		if( inSpecialWordID == NIB_TABLE_ALL_ROWS ) //use local special fake iterator to get all rows instead of selected
		{
			inSelIterator = AllRowsIterator_Create();
			newSelectionIterator = inSelIterator;
		}

		oneValue.Adopt( activeDialog->CopyControlValue(controlID, columnIndex, inSelIterator, &customProperties), kCFObjDontRetain );
		
		if(newSelectionIterator != NULL)
			SelectionIterator_Release(newSelectionIterator);
	}
	else
	{//cached from closed dialog
		DEBUG_CSTR("\tgetting cached value from closed dialog\n");

		if(mNibControlValues == NULL)
			return NULL;
		
		if( ::CFDictionaryGetCount(mNibControlValues) == 0)
			return NULL;
			
		if( inSpecialWordID == NIB_TABLE_ALL_ROWS )
        { //saved as unique value in the dictionary
            CFObj<CFStringRef> newControlID( CreateControlIDByAddingModifiers(controlID, kControlModifier_AllRows) );
            controlID.Swap(newControlID);
        }

		const void *theItem = ::CFDictionaryGetValue(mNibControlValues, (CFStringRef)controlID);

		CFDictionaryRef columnIds = ACFType<CFDictionaryRef>::DynamicCast(theItem);
		if(columnIds != NULL)
		{
			theItem = ::CFDictionaryGetValue(columnIds, (const void *)columnIndex);
			oneValue.Adopt( (CFTypeRef)theItem, kCFObjRetain );
			if( (oneValue != NULL) && (mNibControlCustomProperties != NULL) )
				customProperties.Adopt(
					ACFType<CFDictionaryRef>::DynamicCast(
						::CFDictionaryGetValue(mNibControlCustomProperties, (CFStringRef)controlID) ), kCFObjRetain );
		}
	}

	DEBUG_CSTR("\tstep 3\n");

	CFStringRef newStrRef = NULL;
	//it can be string or array of strings
	if(oneValue != NULL)
	{
		DEBUG_CSTR("\toneValue != NULL\n");

		CFStringRef prefix = NULL;
		CFStringRef suffix = NULL;
		CFStringRef separator =  CFSTR("\t"); //try to separate with tab always //was: for shell-execution we separate just with space

/*
		if( (currCommand.executionMode == kExecAppleScript) || (currCommand.executionMode == kExecAppleScriptWithOutputWindow) )
		{//for Apple script we prapare result for putting in a list: "a","b","c"
			prefix = CFSTR("\"");
			suffix = CFSTR("\"");
			separator = CFSTR(",");
		}
*/

		CFStringRef oneProperty = NULL;
		if( !isEnvStyle && (customProperties != NULL) ) //in environment variables we don't put escapings
		{
			oneProperty = ACFType<CFStringRef>::DynamicCast( ::CFDictionaryGetValue(customProperties, (const void *)kCustomEscapeMethodKey) ); 
			if(oneProperty != NULL)
				escSpecialCharsMode = GetEscapingMode(oneProperty);			
		}

		CFTypeID valType = ::CFGetTypeID( (CFTypeRef)oneValue );
		if( valType == ACFType<CFStringRef>::sTypeID )//regular string
		{
			newStrRef = CreateEscapedStringCopy( (CFStringRef)(CFTypeRef)oneValue, escSpecialCharsMode);
		}
		else if( valType == ACFType<CFArrayRef>::sTypeID )
		{
			if(customProperties != NULL)
			{
				oneProperty = ACFType<CFStringRef>::DynamicCast( ::CFDictionaryGetValue(customProperties, (const void *)kCustomPrefixKey) ); 
				if(oneProperty != NULL)
					prefix = oneProperty;

				oneProperty = ACFType<CFStringRef>::DynamicCast( ::CFDictionaryGetValue(customProperties, (const void *)kCustomSuffixKey) ); 
				if(oneProperty != NULL)
					suffix = oneProperty;

				oneProperty = ACFType<CFStringRef>::DynamicCast( ::CFDictionaryGetValue(customProperties, (const void *)kCustomSeparatorKey) ); 
				if(oneProperty != NULL)
					separator = oneProperty;

			}
			newStrRef = CreateCombinedString( (CFArrayRef)(CFTypeRef)oneValue, separator, prefix, suffix, escSpecialCharsMode );
		}

	}

	DEBUG_CSTR("\texiting CreateNibControlValue\n");

	return newStrRef;
}


//read values and delete the plist file immediately

CFDictionaryRef
ReadControlValuesFromPlist(CFStringRef inDialogUniqueID)
{
	CFObj<CFStringRef> filePathStr( ::CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("/tmp/OMC/%@.plist"), inDialogUniqueID ) );
	if(filePathStr == NULL)
		return NULL;
	
	DEBUG_CFSTR( (CFStringRef)filePathStr );
	
	CFObj<CFURLRef> fileURL( ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, filePathStr, kCFURLPOSIXPathStyle, false) );
	if(fileURL == NULL)
		return NULL;
	
    CFObj<CFPropertyListRef> thePlist( CreatePropertyList(fileURL, kCFPropertyListImmutable) );
    CFDictionaryRef resultDict = ACFType<CFDictionaryRef>::DynamicCast(thePlist);
    if(resultDict != NULL)
        thePlist.Detach();

    (void)DeleteFile(fileURL);

    return resultDict;
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

Boolean IsPredefinedDialogCommandID(CFStringRef inCommandID)
{
	if(inCommandID == NULL)
		return false;

	if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("omc.dialog.terminate.ok"), 0))
		return true;

	if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("omc.dialog.terminate.cancel"), 0))
		return true;

	if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("omc.dialog.initialize"), 0))
		return true;

	if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("omc.dialog.ok"), 0))
		return true;
	
	if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("omc.dialog.cancel"), 0))
		return true;

	if(CFStringGetLength(inCommandID) != 4)
		return false;
	
	//Carbon legacy - only 4 chars
	if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("ok  "), 0))
		return true;
	
	if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("cncl"), 0))
		return true;

	if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("ini!"), 0))
		return true;

	if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("end!"), 0))
		return true;

	if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("cnc!"), 0))
		return true;
	
	return false;
}

//inCommandName is needed to find the subcommand with the same name

OSStatus
OnMyCommandCM::ExecuteSubcommand( CFArrayRef inCommandName, CFStringRef inCommandID, OMCDialog *inDialog, CFTypeRef inContext )
{
	SInt32 commandIndex = -1;
	
	if( (inDialog != NULL) && IsPredefinedDialogCommandID(inCommandID) )
		commandIndex = FindSubcommandIndex(inCommandName, inCommandID); //only strict subcommand for predefined dialog commands
	else																//(command name must match)
		commandIndex = FindCommandIndex(inCommandName, inCommandID);//relaxed rules when no dialog or custom command id
																	//(for example when used for next command)
	return ExecuteSubcommand( commandIndex, inDialog, inContext );
}

OSStatus
OnMyCommandCM::ExecuteSubcommand( SInt32 commandIndex, OMCDialog *inDialog, CFTypeRef inContext )
{	
	if(commandIndex < 0)
		return eventNotHandledErr;

	if( (mCommandList == NULL) || (mCommandCount == 0) )
		return eventNotHandledErr;

	SInt32 mainCommandIndex = mCurrCommandIndex;
	OSStatus err = noErr;

	CommandDescription &subCommand = mCommandList[commandIndex];

	//preserve existing runtime state for subcommand
	CommandState *prevState = subCommand.currState;
	CommandState *newState = new CommandState();
	if(inDialog != NULL)
		newState->dialogGUID.Adopt(inDialog->GetDialogUniqueID(), kCFObjRetain);

	subCommand.currState = newState;

	OMCContextData *contextData = NULL;

	try
	{
		//we don't want errors from previous subcommands to persist
		//we start clean
		mError = noErr;

		if(inContext != NULL)
		{//temporarily put new context for subcommand execution
			contextData = new OMCContextData();
			SwapContext( *contextData ); //this puts existing context in contextData and empties the containers in OnMyCommandCM
			err = ExamineContext(inContext, kCMCommandStart+commandIndex);
		}

		if(err == noErr)
			err = HandleSelection(NULL, kCMCommandStart+commandIndex);
	}
	catch(...)
	{
		err = -1;
	}

	if(inContext != NULL)
	{
		SwapContext( *contextData );
		delete contextData;
	}

	if(err != noErr)
		mError = err;

	//restore previous runtime state
	subCommand.currState = prevState;
	delete newState;

	mCurrCommandIndex = mainCommandIndex;
	
	return err;
}


CFStringRef
GetCommandUniqueID(CommandDescription &currCommand)
{
	assert(currCommand.currState != NULL);
	if( currCommand.currState->commandGUID != NULL )
		return currCommand.currState->commandGUID;

	CFObj<CFUUIDRef>  myUUID( ::CFUUIDCreate(kCFAllocatorDefault) );
	if( myUUID != NULL )
	{
		currCommand.currState->commandGUID.Adopt(::CFUUIDCreateString(kCFAllocatorDefault, myUUID), kCFObjDontRetain);
		currCommand.currState->commandGUIDUsedByCommand = true;
	}

	return currCommand.currState->commandGUID;
}

//next commmand scheduling may happen after currCommand has exited the main execution function
//currCommand.currState may already be invalid
//however, the current command state is copied and preserved by the task manager
//so it can pass inCommandState here
CFStringRef
CopyNextCommandID(const CommandDescription &currCommand, const CommandState *inCommandState)
{
	static char sFilePath[1024];
	static char sCommandGUID[512];
	CFStringRef theNextID = currCommand.nextCommandID;//statically assigned id or NULL is default
	if(theNextID != NULL)
		::CFRetain(theNextID);

	//next command id may be saved only if GetCommandUniqueID() was called at least once
	//when it is called, the commandGUID is cached. otherwise don't bother checking for the file
	if( (inCommandState == NULL) ||
		!inCommandState->commandGUIDUsedByCommand ||
		((CFStringRef)inCommandState->commandGUID == NULL) )
		return theNextID;
	
	
	sCommandGUID[0] = 0;
	Boolean isOK = ::CFStringGetCString(inCommandState->commandGUID, sCommandGUID, sizeof(sCommandGUID), kCFStringEncodingUTF8);
	if(isOK)
	{
		snprintf(sFilePath, sizeof(sFilePath), "/tmp/OMC/%s.id", sCommandGUID);
		if( access(sFilePath, F_OK) == 0 )//check if file with next command id exists 
		{
			FILE *fp = fopen(sFilePath, "r");
			if(fp != NULL)
			{
				fgets(sCommandGUID, sizeof(sCommandGUID), fp);//now store the next command ID in sCommandGUID
				fclose(fp);
				
				size_t idLen = strlen(sCommandGUID);
				if(idLen > 0)
				{
					if(theNextID != NULL)
						::CFRelease(theNextID);//release the static one
					theNextID = ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)sCommandGUID, idLen, kCFStringEncodingUTF8, false);
				}
			}
			unlink(sFilePath);
		}
	}
	return theNextID;
}

extern "C" UInt32
StringToVersion(CFStringRef inString)
{
	if(inString == NULL)
		return 0;
	
	CFObj<CFArrayRef> numbersArr( ::CFStringCreateArrayBySeparatingStrings( kCFAllocatorDefault, inString, CFSTR(".") ) );
	if(numbersArr == NULL)
		return 0;

	CFIndex theCount = ::CFArrayGetCount(numbersArr);
	if(theCount > 3)
		theCount = 3;

	UInt8 versionNumbers[3];
	versionNumbers[0] = versionNumbers[1] = versionNumbers[2] = 0;
	for(CFIndex i = 0; i < theCount; i++)
	{
		CFStringRef oneNumString = (CFStringRef)::CFArrayGetValueAtIndex(numbersArr, i);
		if(oneNumString != NULL)
			versionNumbers[i] = (UInt8)::CFStringGetIntValue(oneNumString);
	}
	
	UInt32 outVersion = versionNumbers[0] * 10000 + versionNumbers[1] * 100 + versionNumbers[2];//new format
/*
	UInt8 highestByte = 0;
	if(versionNumbers[0] > 9)
	{
		highestByte = versionNumbers[0]/10;
		versionNumbers[0] = versionNumbers[0] % 10;
	}

	UInt32 outVersion = ((UInt32)(highestByte & 0x0F) << 12) | ((UInt32)(versionNumbers[0] & 0x0F) << 8) |
					((UInt32)(versionNumbers[1] & 0x0F) << 4) | ((UInt32)versionNumbers[2] & 0x0F);
*/
	return outVersion;
}

extern "C" CFStringRef
CreateVersionString(UInt32 inVersion)
{
//	inVersion = ::CFSwapInt32HostToBig(inVersion);

/*
	int higestByte = (inVersion & 0xF000) >> 12;
	int majorVersion = (inVersion & 0x0F00) >> 8;
	int minorVersion = (inVersion & 0x00F0) >> 4;
	int veryMinorVersion = (inVersion & 0x000F);
*/
	//new format
	int majorVersion = inVersion/10000;
	inVersion -= (10000 * majorVersion);
	int minorVersion = inVersion/100;
	inVersion -= (100 * minorVersion);
	int veryMinorVersion = inVersion;

//	CFStringRef higestStr = NULL;
	CFStringRef veryMinorStr = NULL;
	
//	if(higestByte != 0)
//		higestStr = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d"), higestByte);

	CFStringRef mainStr = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d.%d"), majorVersion, minorVersion);

	if(veryMinorVersion != 0)
		veryMinorStr = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR(".%d"), veryMinorVersion);
		
	CFMutableStringRef wholeStr = ::CFStringCreateMutable( kCFAllocatorDefault, 0);
//	if(higestStr != NULL)
//	{
//		::CFStringAppend( wholeStr, higestStr );
//		::CFRelease(higestStr);
//	}

	if(mainStr != NULL)
	{
		::CFStringAppend( wholeStr, mainStr );
		::CFRelease(mainStr);
	}
	
	if(veryMinorStr != NULL)
	{
		::CFStringAppend( wholeStr, veryMinorStr );
		::CFRelease(veryMinorStr);
	}
	
	return wholeStr;
}

extern "C" CFStringRef
CreatePathByExpandingTilde(CFStringRef inPath)
{
	if(inPath == NULL)
		return NULL;

	CFIndex theLen = ::CFStringGetLength( inPath );
	if(	theLen < 1)
	{
		::CFRetain(inPath);
		return inPath;
	}

	UniChar fistChar = ::CFStringGetCharacterAtIndex( inPath, 0 );
	if(fistChar != '~')
	{
		::CFRetain(inPath);
		return inPath;
	}

	FSRef homeFolderRef;
	OSStatus err = ::FSFindFolder(kUserDomain, kCurrentUserFolderType, kDontCreateFolder, &homeFolderRef);
	if(err == noErr)
	{
		CFObj<CFURLRef> urlRef( ::CFURLCreateFromFSRef(kCFAllocatorDefault, &homeFolderRef) );
		if(urlRef != NULL)
		{
			CFObj<CFStringRef> homePath( ::CFURLCopyFileSystemPath(urlRef, kCFURLPOSIXPathStyle) );
			if(homePath != NULL)
			{
				if(theLen > 1)
				{
					CFObj<CFStringRef> subPath( ::CFStringCreateWithSubstring(kCFAllocatorDefault, inPath, ::CFRangeMake(1, theLen-1)) );
					if(subPath != NULL)
					{
						CFStringRef outString = ::CFStringCreateWithFormat( kCFAllocatorDefault, NULL, CFSTR("%@%@"), (CFStringRef)homePath, (CFStringRef)subPath);
						DEBUG_CFSTR(outString);
						return outString;
					}
				}
				else
				{//just the tilde alone:
					return homePath.Detach();
				}
			}
		}

	}
	
	//error condition - return original path
	::CFRetain(inPath);
	return inPath;
}

class FileNameAndIndex
{
public:
	//take ownership of the string
	FileNameAndIndex(CFStringRef inName, CFIndex inIndex)
		: name(inName, kCFObjDontRetain), index(inIndex)
	{
	}

	CFObj<CFStringRef>	name;
	CFIndex				index;
};

CFComparisonResult
FileNameComparator( const void *val1, const void *val2, void *context)
{
	const FileNameAndIndex *file1 = (const FileNameAndIndex *) val1;
	const FileNameAndIndex *file2 = (const FileNameAndIndex *) val2;
	
	if( (val1 == NULL) || (val2 == NULL) || ((CFStringRef)file1->name == NULL) || ( (CFStringRef)file2->name == NULL) )
		return kCFCompareLessThan;//not equal, order not important

	CFOptionFlags compareOptions = 0;
	if(context != NULL)
		compareOptions = *(CFOptionFlags *)context;

	return ::CFStringCompare(file1->name, file2->name, compareOptions);
}


OSStatus
OnMyCommandCM::SortObjectListByName(CFOptionFlags compareOptions, bool sortAscending)
{
	if( mObjectList.size() <= 1 )
		return noErr;//no need to sort
	
    AUniquePtr<SortSettings> newSort(new SortSettings(kSortMethodByName, compareOptions, sortAscending));
	if( (mSortSettings != nullptr) && (*newSort == *mSortSettings) )
		return noErr;//already sorted by the same criteria

	CFObj<CFMutableArrayRef> sortArray( ::CFArrayCreateMutable(kCFAllocatorDefault, mObjectList.size(), NULL /*const CFArrayCallBacks *callBacks*/ ) );
	if(sortArray == NULL)
		return memFullErr;

	for (CFIndex i = 0; i < mObjectList.size(); i++)
	{
		CFStringRef objName = CreateObjName( &(mObjectList[i]), NULL);
		FileNameAndIndex *oneFileItem = new FileNameAndIndex(objName, i);//take ownership of filename
		::CFArrayAppendValue(sortArray, oneFileItem);
	}

	CFRange theRange = { 0, static_cast<CFIndex>(mObjectList.size()) };
	::CFArraySortValues(sortArray, theRange, FileNameComparator, &compareOptions);

	//now put the sorted values back into our list of OneObjProperties
    std::vector<OneObjProperties> newList( mObjectList.size() );
	
	for(CFIndex i = 0; i < mObjectList.size(); i++)
	{
		FileNameAndIndex *oneFileItem = (FileNameAndIndex *)::CFArrayGetValueAtIndex(sortArray,i);
		newList[sortAscending ? i : (mObjectList.size() -1 -i)] = mObjectList[oneFileItem->index]; //it used to be at oneFileItem->index, now it is at "i" index
		delete oneFileItem;
	}

	//delete the old list itself but not its content because it has been copied to new list and ownership of objects has been transfered
	mObjectList.swap(newList);
	
	mSortSettings.reset( newSort.detach() );

	return noErr;
}

CFBundleRef
OnMyCommandCM::GetCurrentCommandExternBundle()
{
	if( (mCommandList != NULL) && (mCurrCommandIndex < mCommandCount) )
	{
		CommandDescription &currCommand = mCommandList[mCurrCommandIndex];
		if( currCommand.externBundleResolved )
			return currCommand.externBundle;//NULL or not NULL - we have been here before so don't repeat the costly steps
		
		currCommand.externBundleResolved = true;

		if( currCommand.externalBundlePath != NULL )
		{
			CFObj<CFURLRef> bundleURL( ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, currCommand.externalBundlePath, kCFURLPOSIXPathStyle, true) );
			if(bundleURL != NULL)
			{
				currCommand.externBundle = CMUtils::CFBundleCreate(bundleURL);
				if(currCommand.externBundle != NULL)
					return currCommand.externBundle;
			}
		}

		//not explicitly set but might exist - so check it now
		currCommand.externBundle = CreateDefaultExternBundleRef(currCommand.name);
		
		return currCommand.externBundle;
	}

	return NULL;
}

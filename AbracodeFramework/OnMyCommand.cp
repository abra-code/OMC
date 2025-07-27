//**************************************************************************************
// Filename:	OnMyCommandCM.cp
//
// Description:	Main OnMyCommand enigne methods
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

CFStringRef kOMCTopCommandID = CFSTR("top!");

//we take advantage of the fact that __XXX__ word has the same length as OMC_XXX

static const SpecialWordAndID sSpecialWordAndIDList[] =
{
	//wordLen												// specialWord		 //environName		   //id			//always_export
	{ sizeof("__OBJ_TEXT__")-1,								CFSTR("__OBJ_TEXT__"), CFSTR("OMC_OBJ_TEXT"),  OBJ_TEXT, true },
	{ sizeof("__OBJ_PATH__")-1,								CFSTR("__OBJ_PATH__"), CFSTR("OMC_OBJ_PATH"),  OBJ_PATH, true },
	{ sizeof("__OBJ_PARENT_PATH__")-1,						CFSTR("__OBJ_PARENT_PATH__"), CFSTR("OMC_OBJ_PARENT_PATH"),  OBJ_PARENT_PATH, false },
	{ sizeof("__OBJ_NAME__")-1,								CFSTR("__OBJ_NAME__"), CFSTR("OMC_OBJ_NAME"),  OBJ_NAME, false },
	{ sizeof("__OBJ_NAME_NO_EXTENSION__")-1,				CFSTR("__OBJ_NAME_NO_EXTENSION__"), CFSTR("OMC_OBJ_NAME_NO_EXTENSION"),  OBJ_NAME_NO_EXTENSION, false },
	{ sizeof("__OBJ_EXTENSION_ONLY__")-1,					CFSTR("__OBJ_EXTENSION_ONLY__"), CFSTR("OMC_OBJ_EXTENSION_ONLY"),  OBJ_EXTENSION_ONLY, false },
	{ sizeof("__OBJ_DISPLAY_NAME__")-1,						CFSTR("__OBJ_DISPLAY_NAME__"), CFSTR("OMC_OBJ_DISPLAY_NAME"),  OBJ_DISPLAY_NAME, false },
	{ sizeof("__OBJ_COMMON_PARENT_PATH__")-1,				CFSTR("__OBJ_COMMON_PARENT_PATH__"), CFSTR("OMC_OBJ_COMMON_PARENT_PATH"),  OBJ_COMMON_PARENT_PATH, false },
	{ sizeof("__OBJ_PATH_RELATIVE_TO_COMMON_PARENT__")-1,	CFSTR("__OBJ_PATH_RELATIVE_TO_COMMON_PARENT__"), CFSTR("OMC_OBJ_PATH_RELATIVE_TO_COMMON_PARENT"),  OBJ_PATH_RELATIVE_TO_COMMON_PARENT, false },

	{ sizeof("__DLG_INPUT_TEXT__")-1,						CFSTR("__DLG_INPUT_TEXT__"), CFSTR("OMC_DLG_INPUT_TEXT"),  DLG_INPUT_TEXT, false },

	{ sizeof("__DLG_SAVE_AS_PATH__")-1,						CFSTR("__DLG_SAVE_AS_PATH__"), CFSTR("OMC_DLG_SAVE_AS_PATH"),  DLG_SAVE_AS_PATH, false },
	{ sizeof("__DLG_SAVE_AS_PARENT_PATH__")-1,				CFSTR("__DLG_SAVE_AS_PARENT_PATH__"), CFSTR("OMC_DLG_SAVE_AS_PARENT_PATH"),  DLG_SAVE_AS_PARENT_PATH, false },
	{ sizeof("__DLG_SAVE_AS_NAME__")-1,						CFSTR("__DLG_SAVE_AS_NAME__"), CFSTR("OMC_DLG_SAVE_AS_NAME"),  DLG_SAVE_AS_NAME, false },
	{ sizeof("__DLG_SAVE_AS_NAME_NO_EXTENSION__")-1,		CFSTR("__DLG_SAVE_AS_NAME_NO_EXTENSION__"), CFSTR("OMC_DLG_SAVE_AS_NAME_NO_EXTENSION"),  DLG_SAVE_AS_NAME_NO_EXTENSION, false },
	{ sizeof("__DLG_SAVE_AS_EXTENSION_ONLY__")-1,			CFSTR("__DLG_SAVE_AS_EXTENSION_ONLY__"), CFSTR("OMC_DLG_SAVE_AS_EXTENSION_ONLY"),  DLG_SAVE_AS_EXTENSION_ONLY, false },

	{ sizeof("__DLG_CHOOSE_FILE_PATH__")-1,					CFSTR("__DLG_CHOOSE_FILE_PATH__"), CFSTR("OMC_DLG_CHOOSE_FILE_PATH"),  DLG_CHOOSE_FILE_PATH, false },
	{ sizeof("__DLG_CHOOSE_FILE_PARENT_PATH__")-1,			CFSTR("__DLG_CHOOSE_FILE_PARENT_PATH__"), CFSTR("OMC_DLG_CHOOSE_FILE_PARENT_PATH"),  DLG_CHOOSE_FILE_PARENT_PATH, false },
	{ sizeof("__DLG_CHOOSE_FILE_NAME__")-1,					CFSTR("__DLG_CHOOSE_FILE_NAME__"), CFSTR("OMC_DLG_CHOOSE_FILE_NAME"),  DLG_CHOOSE_FILE_NAME, false },
	{ sizeof("__DLG_CHOOSE_FILE_NAME_NO_EXTENSION__")-1,	CFSTR("__DLG_CHOOSE_FILE_NAME_NO_EXTENSION__"), CFSTR("OMC_DLG_CHOOSE_FILE_NAME_NO_EXTENSION"),  DLG_CHOOSE_FILE_NAME_NO_EXTENSION, false },
	{ sizeof("__DLG_CHOOSE_FILE_EXTENSION_ONLY__")-1,		CFSTR("__DLG_CHOOSE_FILE_EXTENSION_ONLY__"), CFSTR("OMC_DLG_CHOOSE_FILE_EXTENSION_ONLY"),  DLG_CHOOSE_FILE_EXTENSION_ONLY, false },

	{ sizeof("__DLG_CHOOSE_FOLDER_PATH__")-1,				CFSTR("__DLG_CHOOSE_FOLDER_PATH__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_PATH"),  DLG_CHOOSE_FOLDER_PATH, false },
	{ sizeof("__DLG_CHOOSE_FOLDER_PARENT_PATH__")-1,		CFSTR("__DLG_CHOOSE_FOLDER_PARENT_PATH__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_PARENT_PATH"),  DLG_CHOOSE_FOLDER_PARENT_PATH, false },
	{ sizeof("__DLG_CHOOSE_FOLDER_NAME__")-1,				CFSTR("__DLG_CHOOSE_FOLDER_NAME__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_NAME"),  DLG_CHOOSE_FOLDER_NAME, false },
	{ sizeof("__DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION__")-1,	CFSTR("__DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION"),  DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION, false },
	{ sizeof("__DLG_CHOOSE_FOLDER_EXTENSION_ONLY__")-1,		CFSTR("__DLG_CHOOSE_FOLDER_EXTENSION_ONLY__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_EXTENSION_ONLY"),  DLG_CHOOSE_FOLDER_EXTENSION_ONLY, false },

	{ sizeof("__DLG_CHOOSE_OBJECT_PATH__")-1,				CFSTR("__DLG_CHOOSE_OBJECT_PATH__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_PATH"),  DLG_CHOOSE_OBJECT_PATH, false },
	{ sizeof("__DLG_CHOOSE_OBJECT_PARENT_PATH__")-1,		CFSTR("__DLG_CHOOSE_OBJECT_PARENT_PATH__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_PARENT_PATH"),  DLG_CHOOSE_OBJECT_PARENT_PATH, false },
	{ sizeof("__DLG_CHOOSE_OBJECT_NAME__")-1,				CFSTR("__DLG_CHOOSE_OBJECT_NAME__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_NAME"),  DLG_CHOOSE_OBJECT_NAME, false },
	{ sizeof("__DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION__")-1,	CFSTR("__DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION"),  DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION, false },
	{ sizeof("__DLG_CHOOSE_OBJECT_EXTENSION_ONLY__")-1,		CFSTR("__DLG_CHOOSE_OBJECT_EXTENSION_ONLY__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_EXTENSION_ONLY"),  DLG_CHOOSE_OBJECT_EXTENSION_ONLY, false },

	{ sizeof("__OMC_RESOURCES_PATH__")-1,					CFSTR("__OMC_RESOURCES_PATH__"), CFSTR("OMC_OMC_RESOURCES_PATH"),  OMC_RESOURCES_PATH, true },//framework path
	{ sizeof("__OMC_SUPPORT_PATH__")-1,						CFSTR("__OMC_SUPPORT_PATH__"), CFSTR("OMC_OMC_SUPPORT_PATH"),  OMC_SUPPORT_PATH, true },//framework path
	{ sizeof("__APP_BUNDLE_PATH__")-1,						CFSTR("__APP_BUNDLE_PATH__"), CFSTR("OMC_APP_BUNDLE_PATH"),  APP_BUNDLE_PATH, true },//preferred for applets
	{ sizeof("__MY_EXTERNAL_BUNDLE_PATH__")-1,				CFSTR("__MY_EXTERNAL_BUNDLE_PATH__"), CFSTR("OMC_MY_EXTERNAL_BUNDLE_PATH"),  MY_EXTERNAL_BUNDLE_PATH, false },//external bundle location
	{ sizeof("__NIB_DLG_GUID__")-1,							CFSTR("__NIB_DLG_GUID__"), CFSTR("OMC_NIB_DLG_GUID"),  NIB_DLG_GUID, true },
	{ sizeof("__CURRENT_COMMAND_GUID__")-1,					CFSTR("__CURRENT_COMMAND_GUID__"), CFSTR("OMC_CURRENT_COMMAND_GUID"),  CURRENT_COMMAND_GUID, true },
	
	{ sizeof("__FRONT_PROCESS_ID__")-1,						CFSTR("__FRONT_PROCESS_ID__"), CFSTR("OMC_FRONT_PROCESS_ID"),  FRONT_PROCESS_ID, false },
	{ sizeof("__FRONT_APPLICATION_NAME__")-1,				CFSTR("__FRONT_APPLICATION_NAME__"), CFSTR("OMC_FRONT_APPLICATION_NAME"),  FRONT_APPLICATION_NAME, false },
	
//deprecated synonyms, still supported but should not appear in OMCEdit choices
	{ sizeof("__MY_HOST_BUNDLE_PATH__")-1,					CFSTR("__MY_HOST_BUNDLE_PATH__"), CFSTR("OMC_MY_HOST_BUNDLE_PATH"),  MY_HOST_BUNDLE_PATH, false },//deprecated as of OMC 4.0
	{ sizeof("__INPUT_TEXT__")-1,							CFSTR("__INPUT_TEXT__"), CFSTR("OMC_INPUT_TEXT"),  DLG_INPUT_TEXT, false },
	{ sizeof("__OBJ_PATH_NO_EXTENSION__")-1,				CFSTR("__OBJ_PATH_NO_EXTENSION__"), CFSTR("OMC_OBJ_PATH_NO_EXTENSION"),  OBJ_PATH_NO_EXTENSION, false },//not needed since = OBJ_PARENT_PATH + OBJ_NAME_NO_EXTENSION
	{ sizeof("__PASSWORD__")-1,								CFSTR("__PASSWORD__"), CFSTR("OMC_PASSWORD"),  DLG_PASSWORD, false },
	{ sizeof("__SAVE_AS_PATH__")-1,							CFSTR("__SAVE_AS_PATH__"), CFSTR("OMC_SAVE_AS_PATH"),  DLG_SAVE_AS_PATH, false },
	{ sizeof("__SAVE_AS_PARENT_PATH__")-1,					CFSTR("__SAVE_AS_PARENT_PATH__"), CFSTR("OMC_SAVE_AS_PARENT_PATH"),  DLG_SAVE_AS_PARENT_PATH, false },
	{ sizeof("__SAVE_AS_FILE_NAME__")-1,					CFSTR("__SAVE_AS_FILE_NAME__"), CFSTR("OMC_SAVE_AS_FILE_NAME"),  DLG_SAVE_AS_NAME, false },
	{ sizeof("__MY_BUNDLE_PATH__")-1,						CFSTR("__MY_BUNDLE_PATH__"), CFSTR("OMC_MY_BUNDLE_PATH"),  MY_BUNDLE_PATH, false }//added for droplets, not very useful for CM
};

//min and max len defined for slight optimization in resolving special words
//the shortest is __OBJ_TEXT__
const CFIndex kMinSpecialWordLen = sizeof("__OBJ_TEXT__") - 1;
//the longest is __DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION__
const CFIndex kMaxSpecialWordLen = sizeof("__DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION__") - 1;

//there are also 2 dynamic names:
//										  __NIB_DIALOG_CONTROL_NNN_VALUE__
//										  __NIB_TABLE_NNN_COLUMN_MMM_VALUE__

static CFMutableDictionaryRef
CreateAllCoreEnvironmentVariablePlaceholders()
{
	CFMutableDictionaryRef outDict = ::CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	size_t theCount = sizeof(sSpecialWordAndIDList)/sizeof(SpecialWordAndID);
	for(size_t i = 0; i< theCount; i++)
	{
		if(sSpecialWordAndIDList[i].alwaysExport)
		{
			CFDictionaryAddValue(outDict, sSpecialWordAndIDList[i].environName, CFSTR("") /*placeholder*/);
		}
	}

	return outDict;
}

//this applier replaces key-values in destination mutable dictionary
static void SetKeyValueInMutableDict(const void *key, const void *value, void *context)
{
	assert(ACFType<CFMutableDictionaryRef>::DynamicCast(context) != nullptr); //only assert in debug, don't incur the cost in release
	CFMutableDictionaryRef destDict = reinterpret_cast<CFMutableDictionaryRef>(context);
	CFDictionarySetValue(destDict, key, value);
}

static void AddRequestedSpecialNibDialogValuesToMutableSet(const void *key, const void *value, void *context)
{
	assert(ACFType<CFMutableSetRef>::DynamicCast(context) != nullptr); //only assert in debug, don't incur the cost in release
	CFMutableSetRef destSet = reinterpret_cast<CFMutableSetRef>(context);
	
	assert(ACFType<CFStringRef>::DynamicCast(key) != nullptr);
	CFStringRef requestedKey = reinterpret_cast<CFStringRef>(key);
	
	SpecialWordID specialWordID = GetSpecialEnvironWordID(requestedKey);
	// currently only NIB_TABLE_ALL_ROWS is special because it is expensive
	// and not exported by default unless:
	// A. explicitly used in the command body in the plist
	// B. specifically requested in must export dictionary
	if( specialWordID == NIB_TABLE_ALL_ROWS )
		CFSetAddValue(destSet, requestedKey);
}

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
	OSStatus err = Init();
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
OnMyCommandCM::ExamineContext( CFTypeRef inContext, SInt32 inCommandRef )
{
	SInt32 cmdIndex = -1;
	if(inCommandRef >= kCMCommandStart)
		cmdIndex = mCurrCommandIndex = inCommandRef - kCMCommandStart;
	else
		mCurrCommandIndex = 0;

	return CommonContextCheck( NULL, inContext, NULL, cmdIndex );
}


OSStatus
OnMyCommandCM::CommonContextCheck( const AEDesc *inAEContext, CFTypeRef inContext, AEDescList *outCommandPairs, SInt32 inCmdIndex )
{
	TRACE_CSTR( "OnMyCommandCM::CommonContextCheck\n" );
	OSStatus err = noErr;

//it is OK to have NULL context
//	if( inAEContext == NULL )
//	{
//		DEBUG_CSTR( "OnMyCommandCM->CMPluginExamineContext error: inAEContext == NULL\n" );
//		return errAENotAEDesc;
//	}

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
	//	Retain(); //no need to do it here and no need to Release() in PostMenuCleanup()

	mIsTextInClipboard = CMUtils::IsTextInClipboard();

	//remember if the context was null on CMPluginExamineContext
	//we cannot trust it when handling the selection later
	if(inAEContext != NULL)
		mContextData.isNullContext = ((inAEContext->descriptorType == typeNull) || (inAEContext->dataHandle == NULL));
	else
		mContextData.isNullContext = (inContext == NULL);

    CFObj<CFMutableArrayRef> contextFiles;
    
	if(inContext != NULL)
	{
		CFTypeID contextType = ::CFGetTypeID( inContext );
		if( contextType == ACFType<CFStringRef>::GetTypeID() )//text
		{
            mContextData.contextText.Adopt( (CFStringRef)inContext, kCFObjRetain);
			mContextData.isTextContext = true;
		}
		else if( contextType == ACFType<CFArrayRef>::GetTypeID() ) //list of files
		{
			contextFiles.Adopt(
					::CFArrayCreateMutable(kCFAllocatorDefault, mContextData.objectList.size(), &kCFTypeArrayCallBacks),
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
	if( !mContextData.isNullContext && !mContextData.isTextContext ) //we have some context that is not text
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
				mContextData.objectList.resize(listItemsCount);
			}
		}
        
		if( contextFiles != NULL )
            validObjectCount = CMUtils::ProcessObjectList( contextFiles, theFlags, CFURLCheckFileOrFolder, &mContextData.objectList);
		else if(inAEContext != NULL)
            validObjectCount = CMUtils::ProcessObjectList( inAEContext, theFlags, CFURLCheckFileOrFolder, &mContextData.objectList );

        anythingSelected = (validObjectCount > 0);
	}

    //update total count
    mContextData.objectList.resize(validObjectCount);

	Boolean isFolder = false;
	if(mContextData.objectList.size() == 1)
	{
		isFolder = CheckAllObjects(mContextData.objectList, CheckIfFolder, NULL);
		if(isFolder)
		{
			Boolean isPackage = CheckAllObjects(mContextData.objectList, CheckIfPackage, NULL);
			if(isPackage)
				isFolder = false;
		}
	}

	if(	anythingSelected && ((theFlags & kListOutMultipleObjects) == 0) && isFolder &&
		(runningInShortcutsObserver && frontProcessIsFinder) )
	{//single folder selected in Finder - check what it is
		mIsOpenFolder = CMUtils::IsClickInOpenFinderWindow(inAEContext, false);
		anythingSelected = ! mIsOpenFolder;
	}
	else if( !anythingSelected && !mContextData.isTextContext )
	{//not a list of objects, maybe a selected text?
		if( (inAEContext != nullptr) && !mContextData.isNullContext )
			mContextData.isTextContext = CMUtils::AEDescHasTextData(*inAEContext);
	}

	err = noErr;

	CFObj<CFStringRef> frontProcessName = CopyFrontAppName();

	//menu population requested
	if(outCommandPairs != NULL)
	{
		(void)PopulateItemsMenu( inAEContext, outCommandPairs,
								runningInEditorApp || runningInShortcutsObserver,
								frontProcessName );
	}
	
	if(inCmdIndex >= 0)
	{
		bool isEnabled = IsCommandEnabled( inCmdIndex, inAEContext,
							runningInEditorApp || runningInShortcutsObserver,
							frontProcessName );
		if( !isEnabled )
			err = errAEWrongDataType;
	}
	

	return err;
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

// pass NULL for inAEContext when executing with CF Context

OSStatus
OnMyCommandCM::HandleSelection( AEDesc *inAEContext, SInt32 inCommandID )
{
	TRACE_CSTR( "OnMyCommandCM::HandleSelection\n" );	

	if( (mCommandList == NULL) || (mCommandCount == 0) )
		return noErr;

	//from now on we assume that Release() will be called at the end of this function so we must not 
	//return somewhere in the middle of this!
	Retain();

	try
	{
		if(inCommandID < kCMCommandStart)
		{
			LOG_CSTR( "OMC->CMPluginHandleSelection: unknown menu item ID. Aliens?\n" );
			throw OSStatus(paramErr);
		}

		mCurrCommandIndex = inCommandID - kCMCommandStart;
		if( mCurrCommandIndex >= mCommandCount )
			throw OSStatus(paramErr);
		
		CommandDescription &currCommand = mCommandList[mCurrCommandIndex];

		CGEventFlags keyboardModifiers = GetKeyboardModifiers();
		//only if lone control key is pressed we consider it a debug request
		currCommand.debugging = ((keyboardModifiers &
								(kCGEventFlagMaskAlphaShift | kCGEventFlagMaskShift | kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand)) == 0)
								&& ((keyboardModifiers & kCGEventFlagMaskControl) != 0);
		
		//take original command by reference, not copy
		PrescanCommandDescription( currCommand );
		
		//make a copy fo the description because when we show a dialog it may become invalid
		//StAEDesc contextCopy;
		//if(mContextData.isNullContext == false)
		//{
		//	::AEDuplicateDesc(inAEContext, (AEDesc *)contextCopy);
		//}

		CFBundleRef localizationBundle = NULL;
		if(currCommand.localizationTableName != NULL)//client wants to be localized
		{
			localizationBundle = GetCurrentCommandExternBundle();
			if(localizationBundle == NULL)
				localizationBundle = CFBundleGetMainBundle();
		}

		//obtain text from selection before any dialogs are shown
		bool objListEmpty = (mContextData.objectList.size() == 0);
		
		if( ((currCommand.prescannedCommandInfo & kOmcCommandContainsTextObject) != 0) && (mContextData.contextText == NULL) )
		{
			CreateTextContext(currCommand, inAEContext);
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

		ARefCountedObj<OMCCocoaDialog> activeDialog;

		//if( (currCommand.dialogNibName != NULL) && (currCommand.nibWindowName != NULL) )//if dialog required
		if( currCommand.nibDialog != NULL )
		{
			ACFDict params( currCommand.nibDialog );
			Boolean isCocoa = true;
//			params.GetValue( CFSTR("IS_COCOA"), isCocoa );

			//bring executing application to front. important when running within ShortcutsObserver
			//don't restore because for non-modal dialogs this would bring executing app behind along with the dialog
			StSwitchToFront switcher(false);
			
			if(isCocoa)
			{
				activeDialog = RunCocoaDialog( this );
				if( activeDialog == nullptr )
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

		if( objListEmpty || mContextData.isTextContext )//text context
		{
			TRACE_CSTR("OnMyCommandCM->CMPluginHandleSelection: about to process command with text selection\n" );
			ProcessCommandWithText( currCommand, mContextData.contextText );
		}
		else //file context
		{
			TRACE_CSTR("OnMyCommandCM About to proces file list\n" );
			ProcessObjects();
		}
		
		//we used to do some post-processing here but now most commands are async so we need to call Finalize when task ends

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

void
OnMyCommandCM::DeleteObjectList()
{
	mContextData.objectList.clear();
	mContextData.currObjectIndex = 0;
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

OSStatus
OnMyCommandCM::CFURLCheckFileOrFolder(CFURLRef inURLRef, size_t index, void *ioData)
{
	if( (inURLRef == nullptr) || (ioData == nullptr) )
		return paramErr;

    std::vector<OneObjProperties> &objectList = *(std::vector<OneObjProperties> *)ioData;

	if(index < objectList.size())
	{
		OneObjProperties& objProperties = objectList[index];
		objProperties.url.Adopt(inURLRef, kCFObjRetain);
		objProperties.extension.Adopt(CFURLCopyPathExtension(inURLRef));
		
		const void* keys[] = { kCFURLIsRegularFileKey, kCFURLIsDirectoryKey, kCFURLIsPackageKey };
		CFObj<CFArrayRef> propertyKeys(CFArrayCreate(kCFAllocatorDefault, keys, sizeof(keys)/sizeof(const void*), &kCFTypeArrayCallBacks));
		CFObj<CFDictionaryRef> fileProperties(CFURLCopyResourcePropertiesForKeys(inURLRef, propertyKeys, nullptr));

		ACFDict propertyDict(fileProperties);
		propertyDict.GetValue(kCFURLIsRegularFileKey, objProperties.isRegularFile);
		propertyDict.GetValue(kCFURLIsDirectoryKey, objProperties.isDirectory);
		propertyDict.GetValue(kCFURLIsPackageKey, objProperties.isPackage);

        return noErr;
	}
	return fnfErr;
}

static CFStringRef
CreateTerminalCommandWithEnvironmentSetup(CFStringRef inCommand, CommandDescription &currCommand, CFDictionaryRef environList, bool isSh)
{
	CFStringRef commandUUID = GetCommandUniqueID(currCommand);
	WriteEnvironmentSetupScriptToTmp(environList, commandUUID, isSh);
	CFObj<CFStringRef> envSetupCommand = CreateEnvironmentSetupCommandForShell(commandUUID, isSh);
	CFObj<CFMutableStringRef> commandWithEnvSetup = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, envSetupCommand);
	CFStringAppend(commandWithEnvSetup, inCommand);
	return commandWithEnvSetup.Detach();
}


OSStatus
OnMyCommandCM::ProcessObjects()
{
	if( (mCommandList == nullptr) || (mCommandCount == 0) || (mContextData.objectList.size() == 0) )
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

	TRACE_CSTR("OnMyCommandCM. ProcessObjects\n" );
	
	CFObj<CFStringRef> dynamicCommandName( CreateDynamicCommandName(currCommand, currCommand.localizationTableName, localizationBundle) );

	CFIndex objectCount = mContextData.objectList.size();
	if( currCommand.multipleObjectProcessing == kMulObjProcessTogether )
		objectCount = 1;

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
			maxTaskCount = 1;//don't care becuase we will have only one task
	}

	OmcHostTaskManager *taskManager = new OmcHostTaskManager( this, currCommand, dynamicCommandName, mBundleRef, maxTaskCount );

	ARefCountedObj<OMCDialog> activeDialog;
    activeDialog = OMCDialog::FindDialogByUUID(currCommand.runtimeUUIDs.dialogUUID);
    if(activeDialog != nullptr)
    {
        SelectionIterator* selIterator = activeDialog->GetSelectionIterator();
        activeDialog->CopyAllControlValues(currCommand.specialRequestedNibControls, selIterator);
    }

	if( currCommand.refresh != nullptr )
	{//refreshing needed - compose array of paths before performing any action
		for(CFIndex i = 0; i < mContextData.objectList.size(); i++)
		{	
			TRACE_CSTR("OnMyCommandCM. create refresh path\n" );
			mContextData.currObjectIndex = i;
			CFObj<CFMutableStringRef> onePath( CreateCombinedStringWithObjects(currCommand.refresh, NULL, NULL) );
			mContextData.objectList[i].refreshPath.Adopt(CreatePathByExpandingTilde(onePath));
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
		if( currCommand.multipleObjectProcessing == kMulObjProcessTogether )
			mContextData.currObjectIndex = -1;//invalid index means process them all together
		else
			mContextData.currObjectIndex = i;

		UInt8 escapingMode = currCommand.escapeSpecialCharsMode;
		if((executionMode == kExecPopenScriptFile) ||
			(executionMode == kExecPopenScriptFileWithOutputWindow))
			escapingMode = kEscapeNone; //the command is actually a path and will not be interpeted by any shell

		CFObj<CFMutableStringRef> theCommand( CreateCommandStringWithObjects(currCommand.command, escapingMode) );
		CFObj<CFMutableStringRef> inputPipe( CreateCommandStringWithObjects(currCommand.inputPipe, kEscapeNone) );
		CFObj<CFDictionaryRef> environList( CreateEnvironmentVariablesDict(NULL) );

		ARefCountedObj<OmcExecutor> theExec;
		CFObj<CFStringRef> objName( CreateObjName( &(mContextData.objectList[i]), NULL) );
			
		switch(executionMode)
		{
			case kExecTerminal:
			{
				bool isSh = IsShDefaultInTerminal();
				CFObj<CFStringRef> commandWithEnvSetup = CreateTerminalCommandWithEnvironmentSetup(theCommand, currCommand, environList, isSh);
				ExecuteInTerminal( commandWithEnvSetup, currCommand.openNewTerminalSession, currCommand.bringTerminalToFront);
			}
			break;
			
			case kExecITerm:
			{
				bool isSh = IsShDefaultInITem();
				CFObj<CFStringRef> commandWithEnvSetup = CreateTerminalCommandWithEnvironmentSetup(theCommand, currCommand, environList, isSh);
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
			taskManager->AddTask( theExec, theCommand, inputPipe, objName );//retains theExec
	}

	if(activeDialog != nullptr)
		taskManager->AddObserver( activeDialog->GetObserver() );

	if(mObserver != nullptr)
		taskManager->AddObserver( mObserver );

	taskManager->Start();

	return noErr;
}


OSStatus
OnMyCommandCM::ProcessCommandWithText(CommandDescription &currCommand, CFStringRef inStrRef)
{
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
    activeDialog = OMCDialog::FindDialogByUUID(currCommand.runtimeUUIDs.dialogUUID);
    if(activeDialog != nullptr)
    {
        SelectionIterator* selIterator = activeDialog->GetSelectionIterator();
        activeDialog->CopyAllControlValues(currCommand.specialRequestedNibControls, selIterator);
    }

	CFObj<CFMutableStringRef> theCommand( CreateCommandStringWithText(currCommand.command, inStrRef, escapingMode) );
	CFObj<CFMutableStringRef> inputPipe( CreateCommandStringWithText(currCommand.inputPipe, inStrRef, kEscapeNone) );
	CFObj<CFDictionaryRef> environList( CreateEnvironmentVariablesDict(inStrRef) );

	CFObj<CFStringRef> dynamicCommandName( CreateDynamicCommandName(currCommand, currCommand.localizationTableName, localizationBundle) );
	CFObj<CFStringRef> objName; //what should the object name be for text?

	CFIndex maxTaskCount = 1;//text command processes one task anyway
	OmcHostTaskManager *taskManager = new OmcHostTaskManager( this, currCommand, dynamicCommandName, mBundleRef, maxTaskCount );

	ARefCountedObj<OmcExecutor> theExec;

	switch(executionMode)
	{
		case kExecTerminal:
		{
			bool isSh = IsShDefaultInTerminal();
			CFObj<CFStringRef> commandWithEnvSetup = CreateTerminalCommandWithEnvironmentSetup(theCommand, currCommand, environList, isSh);
			ExecuteInTerminal( commandWithEnvSetup, currCommand.openNewTerminalSession, currCommand.bringTerminalToFront );
		}
		break;
		
		case kExecITerm:
		{
			bool isSh = IsShDefaultInITem();
			CFObj<CFStringRef> commandWithEnvSetup = CreateTerminalCommandWithEnvironmentSetup(theCommand, currCommand, environList, isSh);
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
		taskManager->AddTask( theExec, theCommand, inputPipe, objName );//retains theExec

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
			SpecialWordID specialWordID = GetSpecialWordID(fragmentRef);
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
		case NIB_TABLE_VALUE:
		case NIB_WEB_VIEW_VALUE:
		break;

		case NIB_TABLE_ALL_ROWS: //special expensive case not always exported, only on demand
		{
//			TRACE_CSTR("NIB_TABLE_VALUE\n" );
			if( currCommand.specialRequestedNibControls == nullptr)
				currCommand.specialRequestedNibControls = CFSetCreateMutable(kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);

			CFSetAddValue(currCommand.specialRequestedNibControls, inSpecialWord);
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
					SpecialWordID specialWordID = GetSpecialEnvironWordID(varString);
					if( specialWordID != NO_SPECIAL_WORD )
					{
						ProcessOnePrescannedWord(currCommand, specialWordID, varString, true);
						
						if(currCommand.customEnvironVariables == nullptr)
							currCommand.customEnvironVariables = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
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
	if( currCommand.name == nullptr )
		return;

//	TRACE_CSTR("OnMyCommandCM->ScanDynamicName\n" );

	ACFArr command(currCommand.name);
	CFIndex theCount = command.GetCount();
	CFStringRef fragmentRef;

	for(CFIndex i = 0; i < theCount; i++ )
	{
		if( command.GetValueAtIndex(i, fragmentRef) )
		{
			SpecialWordID specialWordID = GetSpecialWordID(fragmentRef);
			switch(specialWordID)
			{
				case NO_SPECIAL_WORD:
				break;
				
				case OBJ_TEXT:
					currCommand.nameContainsDynamicText = true;
				break;
				
				default:
				break;
			}
		}
	}
	
}


void
OnMyCommandCM::RefreshObjectsInFinder()
{
	if( mContextData.objectList.size() == 0 )
		return;

	TRACE_CSTR("OnMyCommandCM. RefreshObjectsInFinder\n" );

	for(CFIndex i = 0; i < mContextData.objectList.size(); i++)
	{
		if( mContextData.objectList[i].refreshPath != NULL)
		{
			DEBUG_CFSTR( mContextData.objectList[i].refreshPath );
			RefreshFileInFinder(mContextData.objectList[i].refreshPath);
		}
	}
}


#pragma mark -



//returns true if last command is active.
//makes sense if you have just one command and you want to check if it should be activated
//if we run in Shortcuts, runningInSpecialApp = true, inFrontAppName = NULL
//if we run in ShortcutsObserver, runningInSpecialApp = true, inFrontAppName != NULL

Boolean
OnMyCommandCM::PopulateItemsMenu( const AEDesc *inAEContext, AEDescList* ioRootMenu,
					Boolean runningInSpecialApp, CFStringRef inFrontAppName)
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
	
	for(UInt32 i = 0; i < mCommandCount; i++)
	{
		CommandDescription &currCommand = mCommandList[i];
		
		if( currCommand.isSubcommand ) //it is a subcommand, do not add to menu, main command is always 'top!'
			continue;

		doActivate = IsCommandEnabled(currCommand, inAEContext, currAppName, skipFinderWindowCheck);

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
					CreateTextContext(currCommand, inAEContext);//load context text now
			}
			
			CFBundleRef localizationBundle = nullptr;
			if(currCommand.localizationTableName != nullptr)//client wants to be localized
			{
				localizationBundle = GetCurrentCommandExternBundle();
				if(localizationBundle == nullptr)
					localizationBundle = CFBundleGetMainBundle();
			}

			CFObj<CFStringRef> dynamicCommandName( CreateDynamicCommandName(currCommand, currCommand.localizationTableName, localizationBundle) );
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
OnMyCommandCM::IsCommandEnabled(CommandDescription &currCommand, const AEDesc *inAEContext, CFStringRef currAppName, bool skipFinderWindowCheck)
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
			doActivate = CheckAllObjects(mContextData.objectList, CheckIfFile, NULL);
			
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
					doActivate = CheckAllObjects(mContextData.objectList, CheckFileTypeOrExtension, &(currCommand));
				}
				else if(needsFileTypeCheck)
				{
					doActivate = CheckAllObjects(mContextData.objectList, CheckFileType, &(currCommand));
				}
				else if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(mContextData.objectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;
		
		case kActiveFolder:
		{
			doActivate = CheckAllObjects(mContextData.objectList, CheckIfFolder, NULL);
		
			if(doActivate)
			{
				Boolean needsExtensionCheck = (currCommand.activationExtensions != NULL);
				if(needsExtensionCheck)
				{
					needsExtensionCheck = (::CFArrayGetCount(currCommand.activationExtensions) > 0);
				}
				if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(mContextData.objectList, CheckExtension, &(currCommand));
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
				doActivate = CheckAllObjects(mContextData.objectList, CheckIfFolder, NULL);
		
			if(doActivate)
			{
				Boolean needsExtensionCheck = (currCommand.activationExtensions != NULL);
				if(needsExtensionCheck)
				{
					needsExtensionCheck = (::CFArrayGetCount(currCommand.activationExtensions) > 0);
				}
				if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(mContextData.objectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;
		
		case kActiveFileOrFolder:
		{
			doActivate = CheckAllObjects(mContextData.objectList, CheckIfFileOrFolder, NULL);
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
					doActivate = CheckAllObjects(mContextData.objectList, CheckFileTypeOrExtension, &(currCommand));
				}
				else if(needsFileTypeCheck)
				{
					doActivate = CheckAllObjects(mContextData.objectList, CheckFileType, &(currCommand));
				}
				else if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(mContextData.objectList, CheckExtension, &(currCommand));
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
				doActivate = CheckAllObjects(mContextData.objectList, CheckIfFileOrFolder, NULL);

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
					doActivate = CheckAllObjects(mContextData.objectList, CheckFileTypeOrExtension, &(currCommand));
				}
				else if(needsFileTypeCheck)
				{
					doActivate = CheckAllObjects(mContextData.objectList, CheckFileType, &(currCommand));
				}
				else if(needsExtensionCheck)
				{
					doActivate = CheckAllObjects(mContextData.objectList, CheckExtension, &(currCommand));
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
					doActivate = CheckAllObjects(mContextData.objectList, CheckExtension, &(currCommand));
				}
			}
		}
		break;
		
		case kActiveSelectedText:
			doActivate = mContextData.isTextContext;
		break;

		case kActiveClipboardText:
			doActivate = mIsTextInClipboard;
		break;
		
		case kActiveSelectedOrClipboardText:
			doActivate = (mContextData.isTextContext || mIsTextInClipboard);
		break;
	}
		
	if(doActivate && (currCommand.contextMatchString != NULL) )
	{
		if(mContextData.objectList.size() > 0)
		{//path or name matching requested
			switch(currCommand.matchFileOptions)
			{
				case kMatchFileName:
					doActivate = CheckAllObjects(mContextData.objectList, CheckFileNameMatch, &(currCommand));
				break;
				
				case kMatchFilePath:
					doActivate = CheckAllObjects(mContextData.objectList, CheckFilePathMatch, &(currCommand));
				break;
			}
		}
		else if( (mContextData.isTextContext || mIsTextInClipboard) )
		{//text matching requested
			CreateTextContext(currCommand, inAEContext);//load context text now
			doActivate = DoStringsMatch(currCommand.contextMatchString, mContextData.contextText, currCommand.matchMethod, (CFStringCompareFlags)currCommand.matchCompareOptions );
		}
	}
	return doActivate;
}

bool
OnMyCommandCM::IsCommandEnabled(SInt32 inCmdIndex, const AEDesc *inAEContext, bool runningInSpecialApp, CFStringRef inFrontAppName)
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
	return IsCommandEnabled(currCommand, inAEContext, currAppName, skipFinderWindowCheck);
}

//all objects must meet the condition checked by procedure: logical AND

Boolean
CheckAllObjects(std::vector<OneObjProperties> &objList, ObjCheckingProc inProcPtr, void *inProcData)
{
	if(inProcPtr == nullptr)
    {
        return false;
    }
    
    size_t elemCount = objList.size();
    if(elemCount == 0)
    {
        return false;
    }

	for(size_t i = 0; i < elemCount; i++)
	{
		if(false == (*inProcPtr)( &objList[i], inProcData ) )
			return false;
	}

	return true;
}

inline Boolean
CheckIfFile(OneObjProperties *inObj, void *)
{
	return inObj->isRegularFile;
}

inline Boolean
CheckIfFolder(OneObjProperties *inObj, void *)
{
	return inObj->isDirectory;
}

inline Boolean
CheckIfFileOrFolder(OneObjProperties *inObj, void *)
{
	return (inObj->isRegularFile || inObj->isDirectory);
}

inline Boolean
CheckIfPackage(OneObjProperties *inObj, void *)
{
	return inObj->isPackage;
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
	
	/* we don't support file type match anymore
	for(UInt32 i = 0; i < commDesc->activationTypeCount; i++)
	{
		if( commDesc->activationTypes[i] == inObj->mType )
		{
			return true;//a match was found
		}
	}
	*/

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

	if(inObj->extension == NULL)
		return false;//no extension - it cannot be matched
	
	CFIndex	theLen = ::CFStringGetLength(inObj->extension);
	if(theLen == 0)
		return false;//no extension - it cannot be matched
	
	CFStringRef theExt;
	
	for(CFIndex i = 0; i < theCount; i++)
	{
		if( extensions.GetValueAtIndex(i, theExt) &&
			(kCFCompareEqualTo == ::CFStringCompare( inObj->extension, theExt, kCFCompareCaseInsensitive)) )
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

extern "C" SpecialWordID
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
	else if( ::CFStringHasPrefix(inStr, CFSTR("__NIB_WEBVIEW_")) &&
			::CFStringHasSuffix(inStr, CFSTR("_VALUE__")) )
	{
		return NIB_WEB_VIEW_VALUE;
	}
	
	return NO_SPECIAL_WORD;
}

extern "C" SpecialWordID
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
	else if( ::CFStringHasPrefix(inStr, CFSTR("OMC_NIB_WEBVIEW_")) &&
			::CFStringHasSuffix(inStr, CFSTR("_VALUE")) )
	{
		return NIB_WEB_VIEW_VALUE;
	}

	return NO_SPECIAL_WORD;
}


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

	if(outDesc.command == nullptr)
	{ //no inline command found - change the default execution mode to script file
		outDesc.executionMode = kExecPopenScriptFile;
	}

//execution
	if( oneCmd.GetValue(CFSTR("EXECUTION_MODE"), theStr) )
	{
//		TRACE_CSTR("\tGetOneCommandParams. EXECUTION_MODE string:\n" );
//		TRACE_CFSTR(theStr);

		if( (kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_silent_popen"), 0)) ||
			(kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_popen"), 0)) ||
			(kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_silent"), 0)) ||
			(kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_shell_script"), 0 ) ) )
		{
			outDesc.executionMode = kExecSilentPOpen;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare(theStr, CFSTR("exe_script_file"), 0) )
		{
			outDesc.executionMode = kExecPopenScriptFile;
		}
		else if( (kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_silent_system"), 0 )) ||
			 (kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_system"), 0)) )
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
		else if( ( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_popen_with_output_window"), 0 ) ) ||
				( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_shell_script_with_output_window"), 0 ) ) )
		{
			outDesc.executionMode = kExecPOpenWithOutputWindow;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare(theStr, CFSTR("exe_script_file_with_output_window"), 0) )
		{
			outDesc.executionMode = kExecPopenScriptFileWithOutputWindow;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_applescript"), 0 ) )
		{
			outDesc.executionMode = kExecAppleScript;
		}
		else if( kCFCompareEqualTo == ::CFStringCompare( theStr, CFSTR("exe_applescript_with_output_window"), 0 ) )
		{
			outDesc.executionMode = kExecAppleScriptWithOutputWindow;
		}
		else
		{
			//not an error, using default execution mode
			TRACE_CSTR( "OMC->GetOneCommandParams. EXECUTION_MODE is not specified. Defaulting to exe_popen or exe_script_file\n" );
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
        assert(theCount <= UINT_MAX);
		if(theCount > 0)
		{
			outDesc.activationTypes = new OSType[theCount];
			memset( outDesc.activationTypes, 0, theCount*sizeof(OSType) );
			outDesc.activationTypeCount = (UInt32)theCount;
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
	if( mExternBundleOverrideURL != nullptr)//extern bundle path override is used when OMC is passed a .omc package for execution instead of plist file
		outDesc.externalBundlePath = ::CFURLCopyFileSystemPath( mExternBundleOverrideURL, kCFURLPOSIXPathStyle );
	else if( oneCmd.GetValue(CFSTR("EXTERNAL_BUNDLE_PATH"), theStr) )
		outDesc.externalBundlePath = CreatePathByExpandingTilde( theStr );//keep the string, we are responsible for releasing it

//popenShell
	oneCmd.CopyValue(CFSTR("POPEN_SHELL"), outDesc.popenShell);

//customEnvironVariables
	outDesc.customEnvironVariables = CreateAllCoreEnvironmentVariablePlaceholders(); //the list of always exported variables

	CFDictionaryRef commandMustExportEnvironVariables = nullptr;
	oneCmd.GetValue(CFSTR("ENVIRONMENT_VARIABLES"), commandMustExportEnvironVariables);
	if(commandMustExportEnvironVariables != nullptr)
	{
		CFDictionaryApplyFunction(commandMustExportEnvironVariables, SetKeyValueInMutableDict, (void *)outDesc.customEnvironVariables);

		outDesc.specialRequestedNibControls = CFSetCreateMutable(kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);
		CFDictionaryApplyFunction(commandMustExportEnvironVariables, AddRequestedSpecialNibDialogValuesToMutableSet, (void *)outDesc.specialRequestedNibControls);
		if(CFSetGetCount(outDesc.specialRequestedNibControls) == 0)
		{
			CFRelease(outDesc.specialRequestedNibControls);
			outDesc.specialRequestedNibControls = nullptr;
		}
	}

// using deputy for background execution?
// no longer supported
//	oneCmd.GetValue(CFSTR("SEND_TASK_TO_BACKGROUND_APP"), outDesc.unused);

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

CFMutableStringRef
OnMyCommandCM::CreateCommandStringWithObjects(CFArrayRef inFragments, UInt16 escSpecialCharsMode)
{
	if( (inFragments == nullptr) || (mCommandList == nullptr) || (mCommandCount == 0) || (mContextData.objectList.size() == 0) || (mCurrCommandIndex >= mCommandCount) )
		return nullptr;

	CFMutableStringRef theCommand = CFStringCreateMutable(kCFAllocatorDefault, 0);
	if(theCommand == nullptr)
		return nullptr;

	CommandDescription &currCommand = GetCurrentCommand();

	ARefCountedObj<OMCDialog> activeDialog;
    activeDialog = OMCDialog::FindDialogByUUID(currCommand.runtimeUUIDs.dialogUUID);

//	TRACE_CSTR("OnMyCommandCM. CreateCommandStringWithObjects\n" );

	if(currCommand.sortMethod == kSortMethodByName)
	{
		SortObjectListByName((CFOptionFlags)currCommand.sortOptions, (bool)currCommand.sortAscending);
	}

	if( ((currCommand.prescannedCommandInfo & kOmcCommandContainsTextObject) != 0) && (mContextData.clipboardText == nullptr) )
	{
        mContextData.clipboardText.Adopt( CMUtils::CreateCFStringFromClipboardText(currCommand.textReplaceOptions), kCFObjDontRetain );
	}

	ACFArr fragments(inFragments);
	CFIndex theCount = fragments.GetCount();
	for(CFIndex i = 0; i < theCount; i++ )
	{
		CFStringRef fragmentRef = nullptr;
		if(fragments.GetValueAtIndex(i, fragmentRef))
		{
			AppendTextToCommand(theCommand, fragmentRef,
								mContextData.objectList.data(), mContextData.objectList.size(), mContextData.currObjectIndex,
                                mContextData.clipboardText, currCommand, activeDialog,
								currCommand.mulObjSeparator, currCommand.mulObjPrefix, currCommand.mulObjSuffix,
								escSpecialCharsMode );
		}
	}
	
	return theCommand;
}

//normally command is not localized but this API is used to create dynamic comamnd name, which might be localized
CFMutableStringRef
OnMyCommandCM::CreateCommandStringWithText(CFArrayRef inFragments, CFStringRef inObjTextRef, UInt16 escSpecialCharsMode,
											CFStringRef inLocTableName /*= NULL*/, CFBundleRef inLocBundleRef /*= NULL*/)
{
	if( (inFragments == nullptr) || (mCommandList == nullptr) || (mCommandCount == 0) || (mCurrCommandIndex >= mCommandCount) )
		return NULL;

	CFMutableStringRef theCommand = ::CFStringCreateMutable( kCFAllocatorDefault, 0 );
	if(theCommand == nullptr)
		return nullptr;

	CommandDescription &currCommand = GetCurrentCommand();
	ARefCountedObj<OMCDialog> activeDialog;
    activeDialog = OMCDialog::FindDialogByUUID(currCommand.runtimeUUIDs.dialogUUID);

	ACFArr fragments(inFragments);
	CFIndex theCount = fragments.GetCount();

	for(CFIndex i = 0; i < theCount; i++ )
	{
		CFStringRef fragmentRef = nullptr;
		if( fragments.GetValueAtIndex(i, fragmentRef) )
		{
			AppendTextToCommand(theCommand, fragmentRef,
								nullptr, 0, -1,
								inObjTextRef, currCommand, activeDialog,
								nullptr, nullptr, nullptr,
								escSpecialCharsMode,
								inLocTableName, inLocBundleRef );
		}
	}
	
	return theCommand;
}

CFDictionaryRef
OnMyCommandCM::CreateEnvironmentVariablesDict(CFStringRef inObjTextRef)
{
	CommandDescription &currCommand = GetCurrentCommand();

	if( currCommand.customEnvironVariables == nullptr )
		return nullptr;

	//mutable copy
	CFObj<CFMutableDictionaryRef> outEnviron( ::CFDictionaryCreateMutableCopy( kCFAllocatorDefault,
													::CFDictionaryGetCount(currCommand.customEnvironVariables),
													currCommand.customEnvironVariables) );

	if(mContextData.objectList.size() > 0)
	{
		if(currCommand.sortMethod == kSortMethodByName)
		{
			SortObjectListByName((CFOptionFlags)currCommand.sortOptions, (bool)currCommand.sortAscending);
		}

		if( ((currCommand.prescannedCommandInfo & kOmcCommandContainsTextObject) != 0) && (mContextData.clipboardText == NULL) )
		{
            mContextData.clipboardText.Adopt( CMUtils::CreateCFStringFromClipboardText(currCommand.textReplaceOptions), kCFObjDontRetain );
		}

		PopulateEnvironList( outEnviron,
							mContextData.objectList.data(), mContextData.objectList.size(), mContextData.currObjectIndex,
                            mContextData.clipboardText, currCommand,
							currCommand.mulObjSeparator, currCommand.mulObjPrefix, currCommand.mulObjSuffix);
	
	}
	else //if(inObjTextRef != NULL)
	{
		PopulateEnvironList( outEnviron,
					nullptr, 0, -1,
					inObjTextRef, currCommand,
					nullptr, nullptr, nullptr);
	}

	return outEnviron.Detach();
}

CFMutableStringRef
OnMyCommandCM::CreateCombinedStringWithObjects(CFArrayRef inArray, CFStringRef inLocTableName, CFBundleRef inLocBundleRef)
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

	ARefCountedObj<OMCDialog> activeDialog;
    activeDialog = OMCDialog::FindDialogByUUID(currCommand.runtimeUUIDs.dialogUUID);

	CFMutableStringRef thePath = CFStringCreateMutable(kCFAllocatorDefault, 0);
	if(thePath == nullptr)
		return nullptr;

	for(CFIndex i = 0; i < theCount; i++ )
	{
		CFStringRef fragmentRef = nullptr;
		if( objects.GetValueAtIndex(i, fragmentRef) )
		{
			AppendTextToCommand(thePath, fragmentRef,
								mContextData.objectList.data(), mContextData.objectList.size(), mContextData.currObjectIndex,
								nullptr, currCommand, activeDialog,
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
					CFStringRef inObjTextRef, CommandDescription &currCommand, OMCDialog *activeDialog,
					CFStringRef inMultiSeparator, CFStringRef inMultiPrefix, CFStringRef inMultiSuffix,
					UInt16 escSpecialCharsMode, CFStringRef inLocTableName /*=nullptr*/, CFBundleRef inLocBundleRef/*=nullptr*/)
{
	CFStringRef inInputStr = mInputText;

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
			if(mContextData.cachedCommonParentPath == NULL)
				mContextData.cachedCommonParentPath.Adopt( CreateCommonParentPath(inObjList, inObjCount), kCFObjDontRetain );
	
			newStrRef = CreateEscapedStringCopy(mContextData.cachedCommonParentPath, escSpecialCharsMode);
		break;
		
		case OBJ_PATH_RELATIVE_TO_COMMON_PARENT:
			if(mContextData.cachedCommonParentPath == NULL)
				mContextData.cachedCommonParentPath.Adopt( CreateCommonParentPath(inObjList, inObjCount), kCFObjDontRetain );
		
		
			newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
											CreateObjPathRelativeToBase, (void *)(CFStringRef)mContextData.cachedCommonParentPath,
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
				newStrRef = activeDialog->CreateNibControlValue(specialWordID, inStrRef, escSpecialCharsMode, false);
		}
		break;
		
//no need to escape guid
		case NIB_DLG_GUID:
		{
			if(mCommandList != NULL)
			{
                newStrRef = currCommand.runtimeUUIDs.dialogUUID;
                releaseNewString = false;
			}
		}
		break;
		
		case CURRENT_COMMAND_GUID:
		{
			if(mCommandList != NULL)
			{
				newStrRef = GetCommandUniqueID(currCommand);
				releaseNewString = false;
			}
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
OnMyCommandCM::PopulateEnvironList(CFMutableDictionaryRef ioEnvironList,
					OneObjProperties *inObjList, CFIndex inObjCount, CFIndex inCurrIndex,
					CFStringRef inObjTextRef, CommandDescription &currCommand,
					CFStringRef inMultiSeparator, CFStringRef inMultiPrefix, CFStringRef inMultiSuffix)
{
	CFStringRef inInputStr = mInputText;

	CFIndex itemCount = ::CFDictionaryGetCount(ioEnvironList);
	std::vector<void *> keyList(itemCount);//OK to create empty container if itemCount == 0
	if(itemCount > 0)
	{
		CFDictionaryGetKeysAndValues(ioEnvironList, (const void **)keyList.data(), NULL);
	}
	
	ARefCountedObj<OMCDialog> activeDialog;
    activeDialog = OMCDialog::FindDialogByUUID(currCommand.runtimeUUIDs.dialogUUID);

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
				if(mContextData.cachedCommonParentPath == NULL)
					mContextData.cachedCommonParentPath.Adopt( CreateCommonParentPath(inObjList, inObjCount), kCFObjDontRetain );
		
				newStrRef = mContextData.cachedCommonParentPath;
				releaseNewString = false;
			break;
			
			case OBJ_PATH_RELATIVE_TO_COMMON_PARENT:
				if(mContextData.cachedCommonParentPath == NULL)
					mContextData.cachedCommonParentPath.Adopt( CreateCommonParentPath(inObjList, inObjCount), kCFObjDontRetain );
			
			
				newStrRef = CreateStringFromListOrSingleObject( inObjList, inObjCount, inCurrIndex,
												CreateObjPathRelativeToBase, (void *)(CFStringRef)mContextData.cachedCommonParentPath,
												inMultiSeparator, inMultiPrefix, inMultiSuffix,
												kEscapeNone );
			break;
			
			case DLG_INPUT_TEXT:
				newStrRef = inInputStr;
				releaseNewString = false;
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
				if(mCommandList != NULL)
				{
                    newStrRef = currCommand.runtimeUUIDs.dialogUUID;
                    releaseNewString = false;
				}
			}
			break;
			
			case CURRENT_COMMAND_GUID: //always exported. the side effect is that we now always check for next command in /tmp/OMC/current-command.id file
			{
				if(mCommandList != NULL)
				{
					newStrRef = GetCommandUniqueID(currCommand);
					releaseNewString = false;
				}
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
OnMyCommandCM::CreateDynamicCommandName(const CommandDescription &currCommand, CFStringRef inLocTableName, CFBundleRef inLocBundleRef)
{
	CFStringRef commandName = NULL;
	if( (mContextData.objectList.size() > 1) && (currCommand.namePlural != NULL) )
	{
		commandName = currCommand.namePlural;
		if(inLocTableName != NULL)
			commandName = ::CFCopyLocalizedStringFromTableInBundle( commandName, inLocTableName, inLocBundleRef, "");
		else
			::CFRetain(commandName);
	}
	else if( currCommand.nameIsDynamic && currCommand.nameContainsDynamicText && (mContextData.contextText != NULL) )
	{
		//clip the text here to reasonable size,
		const CFIndex kMaxCharCount = 60;
		CFIndex totalLen = ::CFStringGetLength( mContextData.contextText );
		CFIndex theLen = totalLen;
		CFObj<CFMutableStringRef> newString;
		bool textIsClipped = false;
		if(theLen > kMaxCharCount)
		{
			CFObj<CFStringRef> shortString( ::CFStringCreateWithSubstring(kCFAllocatorDefault, mContextData.contextText, CFRangeMake(0, kMaxCharCount)) );
			newString.Adopt( ::CFStringCreateMutableCopy(kCFAllocatorDefault, kMaxCharCount + 4, shortString) );
			textIsClipped = true;
		}
		else
		{
			newString.Adopt( ::CFStringCreateMutableCopy(kCFAllocatorDefault, kMaxCharCount + 4, mContextData.contextText) );
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
OnMyCommandCM::CreateTextContext(const CommandDescription &currCommand, const AEDesc *inAEContext)
{
	if(mContextData.contextText != NULL)
		return;//already created

	if( mContextData.isTextContext && (currCommand.activationMode != kActiveClipboardText) )
	{
		if( (inAEContext != NULL) && (mContextData.contextText == NULL) && (mContextData.isNullContext == false) )
        {
            mContextData.contextText.Adopt( CMUtils::CreateCFStringFromAEDesc( *inAEContext, currCommand.textReplaceOptions ), kCFObjDontRetain);
        }
	}
	else if(mIsTextInClipboard)
	{
        mContextData.contextText.Adopt( CMUtils::CreateCFStringFromClipboardText(currCommand.textReplaceOptions), kCFObjDontRetain );
        mContextData.clipboardText.Adopt( mContextData.contextText, kCFObjRetain );
	}
}

#pragma mark -

CFStringRef
CreateObjPath(OneObjProperties *inObj, void *) noexcept
{
	if((inObj != nullptr) && (inObj->url != nullptr))
 		return ::CFURLCopyFileSystemPath(inObj->url, kCFURLPOSIXPathStyle);

 	return nullptr;
}

CFStringRef
CreateObjPathNoExtension(OneObjProperties *inObj, void *) noexcept
{
	if((inObj != nullptr) && (inObj->url != nullptr))
  	{
		CFObj<CFURLRef> newURL( ::CFURLCreateCopyDeletingPathExtension( kCFAllocatorDefault, inObj->url ) );
		if(newURL != nullptr)
 			return ::CFURLCopyFileSystemPath(newURL, kCFURLPOSIXPathStyle);
	}
	return nullptr;
}


CFStringRef
CreateParentPath(OneObjProperties *inObj, void *) noexcept
{
	if((inObj != nullptr) && (inObj->url != nullptr))
  	{
 		CFObj<CFURLRef> newURL( ::CFURLCreateCopyDeletingLastPathComponent( kCFAllocatorDefault, inObj->url ) );
		if(newURL != nullptr)
 			return ::CFURLCopyFileSystemPath(newURL, kCFURLPOSIXPathStyle);
	}
	return nullptr;
}


CFStringRef
CreateObjName(OneObjProperties *inObj, void *) noexcept
{
	if((inObj != nullptr) && (inObj->url != nullptr))
		return ::CFURLCopyLastPathComponent(inObj->url);

	return nullptr;
}

CFStringRef
CreateObjNameNoExtension(OneObjProperties *inObj, void *) noexcept
{
	if((inObj != nullptr) && (inObj->url != nullptr))
  	{
		CFObj<CFURLRef> newURL( ::CFURLCreateCopyDeletingPathExtension( kCFAllocatorDefault, inObj->url ) );
		if(newURL != nullptr)
			return ::CFURLCopyLastPathComponent(newURL);
	}
	return nullptr;
}


CFStringRef
CreateObjExtensionOnly(OneObjProperties *inObj, void *) noexcept
{//we already have the extension in our data
	if((inObj != nullptr) && (inObj->extension != nullptr))
		return ::CFStringCreateCopy(kCFAllocatorDefault, inObj->extension);

	return nullptr;
}


CFStringRef
CreateObjDisplayName(OneObjProperties *inObj, void *) noexcept
{
	if((inObj != nullptr) && (inObj->url != nullptr))
	{
		CFStringRef displayName = nullptr;
		Boolean isOK = CFURLCopyResourcePropertyForKey(inObj->url, kCFURLLocalizedNameKey, &displayName, nullptr);
		if(isOK)
			return displayName;
	}
	return nullptr;
}

CFStringRef
CreateObjPathRelativeToBase(OneObjProperties *inObj, void *ioParam) noexcept
{
	if(ioParam == nullptr)
	{//no base is provided, fall back to full path
		return CreateObjPath(inObj, nullptr);
	}

	CFStringRef commonParentPath = (CFStringRef)ioParam;

	if((inObj != nullptr) && (inObj->url != nullptr))
  	{
 		CFObj<CFStringRef> fullPath( ::CFURLCopyFileSystemPath(inObj->url, kCFURLPOSIXPathStyle) );
 		if(fullPath != nullptr)
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
 	return nullptr;
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
	if( (inObjList == nullptr) || (inObjCount == 0) )
		return nullptr;

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
		if(pathsArray != nullptr)
		{
			CFURLRef newURL = (oneObj->url != nullptr) ? CFURLCopyAbsoluteURL(oneObj->url) : nullptr;

			//we dispose of all these URLs, we leave only strings derived from them
 			while(newURL != nullptr)
 			{
 				CFObj<CFURLRef> urlDel(newURL);//delete previous when we are done
				newURL = ::CFURLCreateCopyDeletingLastPathComponent( kCFAllocatorDefault, newURL );
				if(newURL != nullptr)
				{
					CFObj<CFStringRef> aPath( ::CFURLCopyFileSystemPath(newURL, kCFURLPOSIXPathStyle) );
					::CFArrayInsertValueAtIndex( pathsArray, 0, aPath.Get());//grand parent is inserted in front

					if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("/"), aPath.Get(), 0) ) //we reached the top
					{	
						::CFRelease(newURL);//delete current URL and end the loop
						newURL = nullptr;
					}
				}
			}
		}
	}

//get minimum count of parent folders in all our paths
	CFIndex minCount = 0x7FFFFFFF;
	for(CFIndex i = 0; i < inObjCount; i++)
	{
		if(arrayList[i] != nullptr)
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

	CFStringRef commonParentPath = nullptr;

//find common parent
	if( (minCount > 0) && (minCount < 0x7FFFFFFF) )
	{//if minimum count is valid
	//at this point, all items in arrayList are non-NULL
        CFIndex commonPathLevel = 0;
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
		
		if(commonParentPath != nullptr)
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
				if(modifStr != nullptr)
				{
					::CFStringAppend( modifStr, CFSTR("/") );
					commonParentPath = modifStr;
				}
				else
					commonParentPath = nullptr;//failed
			}

			DEBUG_CFSTR( commonParentPath );
		}
	}

//dispose of path arrays
	for(CFIndex i = 0; i < inObjCount; i++)
	{
		if(arrayList[i] != nullptr)
		{
			::CFRelease( arrayList[i] );
			arrayList[i] = nullptr;
		}
	}
	
	return commonParentPath;
}

#pragma mark -

extern "C"
{

CFStringRef
CreatePathFromCFURL(CFURLRef inPathURL, UInt16 escSpecialCharsMode)
{
	if(inPathURL == nullptr)
		return nullptr;

	CFObj<CFURLRef> absURL = CFURLCopyAbsoluteURL(inPathURL);
	CFObj<CFStringRef> pathStr = CFURLCopyFileSystemPath(absURL, kCFURLPOSIXPathStyle);
	CFObj<CFStringRef> escapedPathStr = CreateEscapedStringCopy(pathStr, escSpecialCharsMode);
	return escapedPathStr.Detach();
}

CFStringRef
CreateParentPathFromCFURL(CFURLRef inPathURL, UInt16 escSpecialCharsMode)
{
	if(inPathURL == nullptr)
		return nullptr;

	CFObj<CFURLRef> absURL = CFURLCopyAbsoluteURL(inPathURL);
	CFObj<CFURLRef> newURL = CFURLCreateCopyDeletingLastPathComponent(kCFAllocatorDefault, absURL);
	CFObj<CFStringRef> pathStr = CFURLCopyFileSystemPath(newURL, kCFURLPOSIXPathStyle);
	CFObj<CFStringRef> escapedPathStr = CreateEscapedStringCopy(pathStr, escSpecialCharsMode);
	return escapedPathStr.Detach();
}

CFStringRef
CreateNameFromCFURL(CFURLRef inPathURL, UInt16 escSpecialCharsMode)
{
	if(inPathURL == nullptr)
		return nullptr;

	CFObj<CFStringRef> pathStr = CFURLCopyLastPathComponent(inPathURL);
	CFObj<CFStringRef> escapedPathStr = CreateEscapedStringCopy(pathStr, escSpecialCharsMode);
	return escapedPathStr.Detach();
}

CFStringRef
CreateNameNoExtensionFromCFURL(CFURLRef inPathURL, UInt16 escSpecialCharsMode)
{
	if(inPathURL == nullptr)
		return nullptr;

	CFObj<CFURLRef> newURL = CFURLCreateCopyDeletingPathExtension(kCFAllocatorDefault, inPathURL);
	if(newURL == nullptr)
		return nullptr;

	CFObj<CFStringRef> pathStr = CFURLCopyLastPathComponent(newURL);
	CFObj<CFStringRef> escapedPathStr = CreateEscapedStringCopy(pathStr, escSpecialCharsMode);
	return escapedPathStr.Detach();
}

CFStringRef
CreateExtensionOnlyFromCFURL(CFURLRef inPathURL, UInt16 escSpecialCharsMode)
{
	if(inPathURL == nullptr)
		return nullptr;

	CFObj<CFStringRef> pathStr = CFURLCopyPathExtension(inPathURL);
	CFObj<CFStringRef> escapedPathStr = CreateEscapedStringCopy(pathStr, escSpecialCharsMode);
	return escapedPathStr.Detach();
}

#pragma mark -


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

	if( (mCommandList == nullptr) || (mCommandCount == 0) )
		return eventNotHandledErr;

	SInt32 mainCommandIndex = mCurrCommandIndex;
	OSStatus err = noErr;

	CommandDescription &subCommand = mCommandList[commandIndex];

	// preserve existing UUIDs for subcommand
	OMCRuntimeUUIDs prevUUIDs = subCommand.runtimeUUIDs;
    
	OMCRuntimeUUIDs newRuntimeUUIDs;
	if(inDialog != nullptr)
	{
	    newRuntimeUUIDs.dialogUUID.Adopt(inDialog->GetDialogUniqueID(), kCFObjRetain);
	}
	
	subCommand.runtimeUUIDs = newRuntimeUUIDs;

    OMCContextData contextData;
    
	try
	{
		//we don't want errors from previous subcommands to persist
		//we start clean
		mError = noErr;

		if(inContext != nullptr)
		{
            // temporarily put new context for subcommand execution
            contextData.Swap( mContextData ); //this puts existing context in contextData and empties the containers in mContextData
			err = ExamineContext(inContext, kCMCommandStart+commandIndex);
		}

		if(err == noErr)
			err = HandleSelection(nullptr, kCMCommandStart+commandIndex);
	}
	catch(...)
	{
		err = -1;
	}

	if(err != noErr)
		mError = err;

    if(inContext != nullptr)
    {
        // swap back the original context data
        mContextData.Swap( contextData );
    }
    
	// restore previous runtime UUIDs
	subCommand.runtimeUUIDs = prevUUIDs;

	mCurrCommandIndex = mainCommandIndex;
	
	return err;
}


CFStringRef
GetCommandUniqueID(CommandDescription &currCommand)
{
	if(currCommand.runtimeUUIDs.commandUUID != nullptr)
    {
        return currCommand.runtimeUUIDs.commandUUID;
    }

	CFObj<CFUUIDRef> myUUID(CFUUIDCreate(kCFAllocatorDefault));
	if(myUUID != nullptr)
	{
		currCommand.runtimeUUIDs.commandUUID.Adopt(CFUUIDCreateString(kCFAllocatorDefault, myUUID), kCFObjDontRetain);
	}

	return currCommand.runtimeUUIDs.commandUUID;
}

//next commmand scheduling may happen after currCommand has exited the main execution function
//currCommand.runtimeUUIDs may already be invalid
//however, the current command state is copied and preserved by the task manager
//so it can pass inCommandState here
CFStringRef
CopyNextCommandID(const CommandDescription &currCommand, const OMCRuntimeUUIDs &runtimeUUIDs)
{
	static char sFilePath[1024];
	static char sCommandUUID[512];
	CFStringRef theNextID = currCommand.nextCommandID;//statically assigned id or NULL is default
	if(theNextID != NULL)
		::CFRetain(theNextID);

	// next command id may be saved only if GetCommandUniqueID() was called at least once
	// when it is called, the commandUUID is cached. otherwise don't bother checking for the file
	if( (CFStringRef)runtimeUUIDs.commandUUID == NULL )
    {
        return theNextID;
    }

    sCommandUUID[0] = 0;
	Boolean isOK = ::CFStringGetCString(runtimeUUIDs.commandUUID, sCommandUUID, sizeof(sCommandUUID), kCFStringEncodingUTF8);
	if(isOK)
	{
		snprintf(sFilePath, sizeof(sFilePath), "/tmp/OMC/%s.id", sCommandUUID);
		if( access(sFilePath, F_OK) == 0 )//check if file with next command id exists
		{
			FILE *fp = fopen(sFilePath, "r");
			if(fp != NULL)
			{
				fgets(sCommandUUID, sizeof(sCommandUUID), fp);//now store the next command ID in sCommandGUID
				fclose(fp);
				
				size_t idLen = strlen(sCommandUUID);
				if(idLen > 0)
				{
					if(theNextID != NULL)
						::CFRelease(theNextID);//release the static one
					theNextID = ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)sCommandUUID, idLen, kCFStringEncodingUTF8, false);
				}
			}
			unlink(sFilePath);
		}
	}
	return theNextID;
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
	if( mContextData.objectList.size() <= 1 )
		return noErr;//no need to sort
	
	AUniquePtr<SortSettings> newSort(new SortSettings(kSortMethodByName, compareOptions, sortAscending));
	if( (mSortSettings != nullptr) && (*newSort == *mSortSettings) )
		return noErr;//already sorted by the same criteria

	CFObj<CFMutableArrayRef> sortArray( ::CFArrayCreateMutable(kCFAllocatorDefault, mContextData.objectList.size(), NULL /*const CFArrayCallBacks *callBacks*/ ) );
	if(sortArray == NULL)
		return memFullErr;

	for (CFIndex i = 0; i < mContextData.objectList.size(); i++)
	{
		CFStringRef objName = CreateObjName( &(mContextData.objectList[i]), NULL);
		FileNameAndIndex *oneFileItem = new FileNameAndIndex(objName, i);//take ownership of filename
		::CFArrayAppendValue(sortArray, oneFileItem);
	}

	CFRange theRange = { 0, static_cast<CFIndex>(mContextData.objectList.size()) };
	::CFArraySortValues(sortArray, theRange, FileNameComparator, &compareOptions);

	//now put the sorted values back into our list of OneObjProperties
	std::vector<OneObjProperties> newList( mContextData.objectList.size() );
	
	for(CFIndex i = 0; i < mContextData.objectList.size(); i++)
	{
		FileNameAndIndex *oneFileItem = (FileNameAndIndex *)::CFArrayGetValueAtIndex(sortArray,i);
		newList[sortAscending ? i : (mContextData.objectList.size() -1 -i)] = mContextData.objectList[oneFileItem->index]; //it used to be at oneFileItem->index, now it is at "i" index
		delete oneFileItem;
	}

	//delete the old list itself but not its content because it has been copied to new list and ownership of objects has been transfered
	mContextData.objectList.swap(newList);
	
	mSortSettings.reset( newSort.detach() );

	return noErr;
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

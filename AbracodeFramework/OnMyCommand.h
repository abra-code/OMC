//#include "OnMyCommand.h"

#pragma once

#include "OutputWindowHandler.h"
#include "ACMPlugin.h"
#include "OMCConstants.h"
#include "OMCStrings.h"
#include "OMC.h"
#include "AUniquePtr.h"
#include <vector>

class SelectionIterator;
class AObserverBase;
class OMCDialog;

#define CM_IMPL_PLUGIN_PREFS_INDENTIFIER	"com.abracode.OnMyCommandCMPrefs"

extern CFStringRef kOMCTopCommandID;

class CommandState
{
public:
	CommandState()
	 : commandGUIDUsedByCommand(false)
	{
	}
	
	~CommandState()
	{
	}

public:
	CFObj<CFStringRef> commandGUID;
	CFObj<CFStringRef>	dialogGUID;//dialog GUID used instead of dialog ptr to look up the instance
	Boolean			commandGUIDUsedByCommand;//if requested, it's likely for next command
};

typedef struct CommandDescription
{
	CFArrayRef		name;
	CFStringRef		namePlural;
	CFArrayRef		command;//array of CFStrings
	CFArrayRef		inputPipe;//array of CFStrings
    OSType *		activationTypes;
	UInt32			activationTypeCount;
	CFArrayRef		activationExtensions;//array of CFStrings
	UInt8			executionMode;
	UInt8			executionOptions;
	UInt8			activationMode;
	UInt8			escapeSpecialCharsMode;
	UInt8			multipleObjectProcessing;
	UInt8			sortMethod;
	UInt8			sortAscending;
	UInt8			sortOptions;
	CFStringRef		mulObjPrefix;
	CFStringRef		mulObjSuffix;
	CFStringRef		mulObjSeparator;
	CFStringRef		warningStr;
	CFStringRef		warningExecuteStr;
	CFStringRef		warningCancelStr;
	CFStringRef		submenuName;
	UInt32			prescannedCommandInfo;
	Boolean			isPrescanned;
	Boolean			bringTerminalToFront;
	Boolean			openNewTerminalSession;
	Boolean			simulatePaste;
	Boolean			nameIsDynamic;
	Boolean			nameContainsText;
	UInt16			inputDialogType;
	CFStringRef		inputDialogOK;
	CFStringRef		inputDialogCancel;
	CFStringRef		inputDialogMessage;
	CFArrayRef		inputDialogDefault;
	CFArrayRef		inputDialogMenuItems;//array of name & value pairs
	CFArrayRef		refresh;//a list of strings forming a path for Finder refresh
	CFDictionaryRef	saveAsParams;
	CFDictionaryRef	chooseFileParams;
	CFDictionaryRef	chooseFolderParams;
	CFDictionaryRef	chooseObjectParams;

	CFURLRef		saveAsPath;
	CFURLRef		chooseFilePath;
	CFURLRef		chooseFolderPath;
	CFURLRef		chooseObjectPath;

	CFDictionaryRef	outputWindowOptions;
	CFDictionaryRef nibDialog;
	CFArrayRef		appNames;
	long			textReplaceOptions;
	CFStringRef		commandID;//"top!" = main command, other value = command handler/subcommand - should not appear in contextual menu
	CFStringRef		nextCommandID; //if not NULL, next command
	CFStringRef		externalBundlePath;
	CFBundleRef		externBundle;//populated on first request and cached
	CFArrayRef		popenShell;
	CFMutableDictionaryRef	customEnvironVariables;
	CFMutableSetRef specialRequestedNibControls; //set of special words to export
	Boolean			actOnlyInListedApps;//if true - activate only in those listed, if false - exclude those listed
	Boolean			debugging; //set to true when control keyboard modifier is held
	Boolean			disabled;
	Boolean			isSubcommand;
	SInt32			requiredOMCVersion;
	SInt32			requiredMacOSMinVersion;
	SInt32			requiredMacOSMaxVersion;
	CFStringRef		iTermShellPath;
	CFDictionaryRef	endNotification;
	CFDictionaryRef progress;
	CFIndex			maxTaskCount;
	CFStringRef		contextMatchString;
	UInt8			matchCompareOptions;//currently only kCFCompareCaseInsensitive
	UInt8			matchMethod; //kMatchExact, kMatchContains, kMatchRegularExpression
	UInt8			matchFileOptions;//kMatchFileName, kMatchFilePath
	Boolean			externBundleResolved;//costly call to find the extern bundle - do it once and flag it here
	CFDictionaryRef multipleSelectionIteratorParams; //control id and forward/reverse flag
	CFStringRef		localizationTableName;
	CommandState	*currState; //dynamic state at runtime, must be managed before and after execution
} CommandDescription;


typedef struct OneObjProperties
{
	CFObj<CFURLRef> url;
	CFObj<CFStringRef> extension;
    CFObj<CFStringRef> refreshPath;//refresh path is associated with object. this is one-to-one relationship
//	OSType		mType;
    Boolean isRegularFile { false };
    Boolean isDirectory { false };
    Boolean isPackage { false };
    Boolean reserved { false };
} OneObjProperties;

typedef enum SpecialWordID
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
	APP_BUNDLE_PATH, //as of OMC 4.0 the preferred way to access applet bundle path - exported byy default
	MY_HOST_BUNDLE_PATH, //deprecated but supported as of OMC 4.0 - not exported by default though
	MY_EXTERNAL_BUNDLE_PATH, //points to EXTERNAL_BUNDLE_PATH defined in description. redundant but needed for portability
	NIB_DLG_GUID,
	NIB_DLG_CONTROL_VALUE,
	NIB_TABLE_VALUE,
	NIB_TABLE_ALL_ROWS,
	NIB_WEB_VIEW_VALUE,
	CURRENT_COMMAND_GUID,
	FRONT_PROCESS_ID,
	FRONT_APPLICATION_NAME
} SpecialWordID;

typedef struct SpecialWordAndID
{
	CFIndex		wordLen;
	CFStringRef	specialWord;
	CFStringRef environName;
	SpecialWordID id;
	bool		alwaysExport { false };
} SpecialWordAndID;

class SortSettings
{
public:
	SortSettings(UInt32 inSortMethod = kSortMethodNone, CFOptionFlags inCompareOptions = 0, Boolean inSortAscending = true)
		: sortMethod(inSortMethod),
		compareOptions(inCompareOptions),
		sortAscending(inSortAscending)
	{
	}

	UInt32			sortMethod;
	CFOptionFlags	compareOptions;
	Boolean			sortAscending;
};

inline bool operator==( const SortSettings &inS1, const SortSettings &inS2 )
{
	return ((inS1.sortMethod == inS2.sortMethod) && (inS1.compareOptions == inS2.compareOptions) && (inS1.sortAscending == inS2.sortAscending));
}

class OMCContextData
{
public:
	OMCContextData()
		: mCurrObjectIndex(0), mIsNullContext(false), mIsTextContext(false)
	{
	}

	CFObj<CFStringRef>			mContextText;
	std::vector<OneObjProperties> mObjectList;
	CFIndex						mCurrObjectIndex;
	CFObj<CFStringRef>			mCommonParentPath;
	Boolean						mIsNullContext;
	Boolean						mIsTextContext;
};


enum
{
	kCMCommandStart				= 0x10000000			//command IDs start here
};

class OnMyCommandCM : public ACMPlugin
{
public:

						OnMyCommandCM(CFTypeRef inPlistRef = NULL);
	virtual				~OnMyCommandCM();
	
	virtual OSStatus	Init();

	virtual OSStatus	ExamineContext( const AEDesc *inContext, AEDescList *outCommandPairs );
	virtual OSStatus	ExamineContext( const AEDesc *inContext, SInt32 inCommandRef, AEDescList *outCommandPairs );
	virtual OSStatus	ExamineContext( CFTypeRef inContext, SInt32 inCommandRef );

	virtual Boolean		ExamineDropletFileContext(AEDescList *fileList);
	virtual OSStatus	HandleSelection( AEDesc *inContext, SInt32 inCommandID );//pass NULL for inContext when executing with CF Context
	virtual void		PostMenuCleanup();

	OSStatus			CommonContextCheck( const AEDesc *inContext, CFTypeRef inCFContext, AEDescList *outCommandPairs, SInt32 inCmdIndex );

//	void				Finalize();
	//real CM plug-ins try hard to get current context
	//when the context info is prepared by host app (non-CM situation), we don't want the agressive search and other behavior
	void				SetCMPluginMode(Boolean inCMPluginMode) { mCMPluginMode = inCMPluginMode; }

	void				AddObserver(AObserverBase *inObserver)
						{
							mObserver.Adopt(inObserver, kARefCountRetain);
						}

	void				RemoveObserver(AObserverBase *inObserver)
						{
							if(mObserver == inObserver)
								mObserver.Adopt(NULL);
						}
	
	void				SwapContext(OMCContextData &ioContextData);

	void				DeleteCommandList();
	void				DeleteObjectList();

	OSStatus			ProcessObjects();
	OSStatus			ProcessCommandWithText(CommandDescription &currCommand, CFStringRef inStrRef);
	Boolean				DisplayWarning( CommandDescription &currCommand );
	Boolean				PopulateItemsMenu( const AEDesc *inContext, AEDescList* ioRootMenu, Boolean runningInSpecialApp, CFStringRef inFrontAppName );
	bool				IsCommandEnabled(CommandDescription &currCommand, const AEDesc *inContext, CFStringRef currAppName, bool skipFinderWindowCheck);
	bool				IsCommandEnabled(SInt32 inCmdIndex, const AEDesc *inContext, bool runningInSpecialApp, CFStringRef inFrontAppName);

	Boolean				ShowInputDialog( CommandDescription &currCommand, CFStringRef &outStr );

	void				ReadPreferences();
	void				ParseCommandList(CFArrayRef commandArrayRef);
	void				LoadCommandsFromPlistFile(CFURLRef inPlistFileURL);
	void				LoadCommandsFromPlistRef(CFPropertyListRef inPlistRef);
	void				GetOneCommandParams(CommandDescription &outDesc, CFDictionaryRef inOneCommand);

	OSStatus			ExecuteSubcommand( CFArrayRef inCommandName, CFStringRef inCommandID, OMCDialog *inDialog, CFTypeRef inContext );
	OSStatus			ExecuteSubcommand( SInt32 commandIndex, OMCDialog *inDialog, CFTypeRef inContext );

	static OSStatus		CFURLCheckFileOrFolder(CFURLRef inURLRef, void *ioData);

	Boolean				IsSubcommand(CFArrayRef inName, CFIndex inCommandIndex);
	SInt32				FindCommandIndex( CFStringRef inNameOrId );
	void				PrescanCommandDescription(CommandDescription &currCommand );
	OSStatus			GetCommandInfo(SInt32 inCommandRef, OMCInfoType infoType, void *outInfo);
	void				PrescanArrayOfObjects( CommandDescription &currCommand, CFArrayRef inObjects );
	void				ProcessOnePrescannedWord(CommandDescription &currCommand, SInt32 specialWordID, CFStringRef inSpecialWord, bool isEnvironVariable);
	void				FindEnvironmentVariables(CommandDescription &currCommand, CFStringRef inString);
	void				ScanDynamicName( CommandDescription &currCommand );

	void				RefreshObjectsInFinder();

	CFMutableStringRef	CreateCommandStringWithObjects(CFArrayRef inFragments, UInt16 escSpecialCharsMode);
	CFMutableStringRef	CreateCommandStringWithText(CFArrayRef inFragments, CFStringRef inObjTextRef, UInt16 escSpecialCharsMode, CFStringRef inLocTableName = NULL, CFBundleRef inLocBundleRef = NULL);
	CFDictionaryRef		CreateEnvironmentVariablesDict(CFStringRef inObjTextRef);

	void				AppendTextToCommand(CFMutableStringRef inCommandRef, CFStringRef inStrRef,
											OneObjProperties *inObjList, CFIndex inObjCount, CFIndex inCurrIndex,
											CFStringRef inObjTextRef, CommandDescription &currCommand, OMCDialog *activeDialog,
											CFStringRef inMultiSeparator, CFStringRef inMultiPrefix, CFStringRef inMultiSuffix,
											UInt16 escSpecialCharsMode, CFStringRef inLocTableName = nullptr, CFBundleRef inLocBundleRef = nullptr);

	void				PopulateEnvironList(CFMutableDictionaryRef ioEnvironList,
											OneObjProperties *inObjList, CFIndex inObjCount, CFIndex inCurrIndex,
											CFStringRef inObjTextRef, CommandDescription &currCommand,
											CFStringRef inMultiSeparator, CFStringRef inMultiPrefix, CFStringRef inMultiSuffix);

	CFStringRef			CreateDynamicCommandName(const CommandDescription &currCommand, CFStringRef inLocTableName, CFBundleRef inLocBundleRef);
	void				CreateTextContext(const CommandDescription &currCommand, const AEDesc *inContext);

	SInt32				FindSubcommandIndex(CFArrayRef inName, CFStringRef inCommandID);
	SInt32				FindCommandIndex(CFArrayRef inName, CFStringRef inCommandID);
	OSStatus			SortObjectListByName(CFOptionFlags compareOptions, bool sortAscending);

	CFMutableStringRef	CreateCombinedStringWithObjects(CFArrayRef inArray, CFStringRef inLocTableName, CFBundleRef inLocBundleRef);

	CommandDescription & GetCurrentCommand()
						{
							if( (mCommandList == nullptr) || (mCurrCommandIndex >= mCommandCount) )
								throw OSStatus(paramErr);
							return mCommandList[mCurrCommandIndex];
						}

	UInt32				GetCurrentCommandIndex() const { return mCurrCommandIndex; }
	void				SetCurrentCommandIndex(UInt32 inIndex)
						{
							if( (mCommandList != NULL) && (inIndex >= mCommandCount) )
								mCurrCommandIndex = inIndex;
						}
	OSStatus			GetError() { return mError; }
	void				SetError(OSStatus inErr) { mError = inErr; }

	CommandDescription * GetCommandList() { return mCommandList; }
	UInt32				GetCommandCount() const { return mCommandCount; }

	CFBundleRef			GetCurrentCommandExternBundle();
	static SInt32		GetCurrentMacOSVersion() { return sMacOSVersion; }

private:

	void				InitOmcBundlePaths();

protected:
    static SInt32				sMacOSVersion;

	CFObj<CFURLRef>				mPlistURL;
	CFObj<CFURLRef>				mExternBundleOverrideURL;
    CommandDescription			*mCommandList {nullptr};
    UInt32						mCommandCount {0};
    UInt32						mCurrCommandIndex {0};
    std::vector<OneObjProperties> mObjectList;
    CFIndex						mCurrObjectIndex {0};
	AUniquePtr<SortSettings>	mSortSettings;
	CFObj<CFStringRef>			mContextText;//selected or clipboard text
	CFObj<CFStringRef>			mClipboardText;//may be the same as mContextText, just retained
	CFObj<CFStringRef>			mCommonParentPath;//cached here for better performance
	CFObj<CFStringRef>			mInputText;
	CFObj<CFURLRef>				mCachedSaveAsPath;
	CFObj<CFURLRef>				mCachedChooseFilePath;
	CFObj<CFURLRef>				mCachedChooseFolderPath;
	CFObj<CFURLRef>				mCachedChooseObjectPath;
	CFObj<CFStringRef>			mMyHostBundlePath;
	CFObj<CFStringRef>			mMyHostAppName;
	CFObj<CFStringRef>			mOmcSupportPath;
	CFObj<CFStringRef>			mOmcResourcesPath;
	ARefCountedObj<AObserverBase> mObserver;
    OSStatus					mError {noErr};
    Boolean						mIsTextInClipboard {false};
    Boolean						mIsOpenFolder {false};
    Boolean						mIsNullContext {false};
    Boolean						mIsTextContext {false};
    Boolean						mCMPluginMode {true};
    Boolean						mRunningInShortcutsObserver {false};
    pid_t			            mFrontProcessPID {0};//if running in observer we don't want to return observer as front process if it happens to come up
};

void		GetMultiCommandParams(CommandDescription &outDesc, CFDictionaryRef inOneCommand);
void		GetInputDialogParams(CommandDescription &outDesc, CFDictionaryRef inOneCommand);
void		GetNavDialogParams(CFDictionaryRef inFileDialogDict, CFStringRef &outMessage, CFArrayRef &outDefaultName, CFArrayRef &outDefaultLocation, UInt32 &outAdditionalNavServiesFlags);
void		GetContextMatchingParams(CommandDescription &outDesc, CFDictionaryRef inParams);

//void		GetNibDialogSettings(CommandDescription &outDesc, CFDictionaryRef inOneCommand);


//FourCharCode	CFStringToFourCharCode(CFStringRef inStrRef);
#define CFStringToFourCharCode UTGetOSTypeFromString

//removed const from OneObjProperties becuase it allows lazy population of some fields
typedef Boolean (*ObjCheckingProc)( OneObjProperties *inObj, void *inProcData );

Boolean		CheckAllObjects(std::vector<OneObjProperties>& objList, ObjCheckingProc inProcPtr, void *inProcData);
Boolean		CheckIfFile(OneObjProperties *inObj, void *);
Boolean		CheckIfFolder(OneObjProperties *inObj, void *);
Boolean		CheckIfFileOrFolder(OneObjProperties *inObj, void *);
Boolean		CheckIfPackage(OneObjProperties *inObj, void *);
Boolean		CheckFileType(OneObjProperties *inObj, void *);
Boolean		CheckExtension(OneObjProperties *inObj, void *);
Boolean		CheckFileTypeOrExtension(OneObjProperties *inObj, void *inData);
Boolean		CheckFileNameMatch(OneObjProperties *inObj, void *inData);
Boolean		CheckFilePathMatch(OneObjProperties *inObj, void *inData);
Boolean		DoStringsMatch(CFStringRef inMatchString, CFStringRef inSearchedString, UInt8 matchMethod, CFStringCompareFlags compareOptions );

//removed const from OneObjProperties becuase it allows lazy population of some fields
typedef CFStringRef (*CreateObjProc)(OneObjProperties *inObj, void *ioParam) noexcept;

CFStringRef			CreateObjPath(OneObjProperties *inObj, void *ioParam) noexcept;
CFStringRef			CreateObjPathNoExtension(OneObjProperties *inObj, void *ioParam) noexcept;
CFStringRef			CreateParentPath(OneObjProperties *inObj, void *ioParam) noexcept;
CFStringRef			CreateObjName(OneObjProperties *inObj, void *ioParam) noexcept;
CFStringRef			CreateObjNameNoExtension(OneObjProperties *inObj, void *ioParam) noexcept;
CFStringRef			CreateObjExtensionOnly(OneObjProperties *inObj, void *ioParam) noexcept;
CFStringRef			CreateObjDisplayName(OneObjProperties *inObj, void *ioParam) noexcept;
CFStringRef			CreateObjPathRelativeToBase(OneObjProperties *inObj, void *ioParam)noexcept ;

CFStringRef			CreateCommonParentPath(OneObjProperties *inObjList, CFIndex inObjCount );


CFStringRef			CreateStringFromListOrSingleObject( OneObjProperties *inObjList, CFIndex inObjCount, CFIndex inCurrIndex,
														CreateObjProc inObjProc, void *ioParam,
														CFStringRef inMultiSeparator, CFStringRef inPrefix, CFStringRef inSuffix,
														UInt16 escSpecialCharsMode );

Boolean		IsPredefinedDialogCommandID(CFStringRef inCommandID);

extern "C"
{
CFStringRef			CreatePathFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode);
CFStringRef			CreateParentPathFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode);
CFStringRef			CreateNameFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode);
CFStringRef			CreateNameNoExtensionFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode);
CFStringRef			CreateExtensionOnlyFromCFURL(CFURLRef inPath, UInt16 escSpecialCharsMode);

CFStringRef			CreateCombinedString( CFArrayRef inStringsArray, CFStringRef inSeparator, CFStringRef inPrefix, CFStringRef inSuffix, UInt16 escSpecialCharsMode );

SpecialWordID       GetSpecialWordID(CFStringRef inStr);
SpecialWordID       GetSpecialEnvironWordID(CFStringRef inStr);

UInt8               GetEscapingMode(CFStringRef theStr);
CFStringRef         GetEscapingModeString(UInt8 inEscapeMode);
};

CFDictionaryRef		ReadControlValuesFromPlist(CFStringRef inDialogUniqueID);
CFStringRef			GetCommandUniqueID(CommandDescription &currCommand);
CFStringRef			CopyNextCommandID(const CommandDescription &currCommand, const CommandState *inCommandState);
Boolean				DisplayVersionWarning(CFBundleRef inBundleRef, CFStringRef dynamicCommandName, CFStringRef inString, SInt32 requiredVersion, SInt32 currVersion);
Boolean				DisplayAlert(CFBundleRef inBundleRef, CFStringRef dynamicCommandName, CFStringRef inAlertString, CFOptionFlags inAlertLevel = kCFUserNotificationStopAlertLevel );


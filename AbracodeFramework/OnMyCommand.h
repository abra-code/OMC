//#include "OnMyCommand.h"

#pragma once

#include "OutputWindowHandler.h"
#include "ACMPlugin.h"
#include "OMCConstants.h"
#include "OMCUtils.h"
#include "OMC.h"
#include "AUniquePtr.h"
#include <vector>

class SelectionIterator;
class AObserverBase;
class OMCDialog;

#define CM_IMPL_PLUGIN_PREFS_INDENTIFIER	"com.abracode.OnMyCommandCMPrefs"
//2 digits per version point : 3.2.0 = 03 02 00
#define CURRENT_OMC_VERSION 30200
#define MIN_OMC_VERSION 10301
#define MIN_MAC_OS_VERSION 100309
#define MAX_MAC_OS_VERSION 999999

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
	FileType *		activationTypes;
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
	Boolean			actOnlyInListedApps;//if true - activate only in those listed, if false - exclude those listed
	Boolean			useDeputy;
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
	FSRef			mRef;
	CFURLRef		mURLRef;
	CFStringRef		mExtension;
	FileType		mType;
	LSItemInfoFlags	mFlags;//we will request all flags except for application type flags which are not thread-safe.
	CFStringRef		mRefreshPath;//refresh path is associated with object. this is one-to-one relationship
} OneObjProperties;

typedef struct SpecialWordAndID
{
	CFIndex		wordLen;
	CFStringRef	specialWord;
	CFStringRef environName;
	SInt32		id;
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

	CFObj<CFMutableArrayRef>	mContextFiles;
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
	
	virtual OSStatus	Init(CFBundleRef inBundle);

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
	OSStatus			ProcessCommandWithText(const CommandDescription &currCommand, CFStringRef inStrRef);
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

	void				GetDialogControlValues( CommandDescription &currCommand, OMCDialog &inDialog );

	OSStatus			ExecuteSubcommand( CFArrayRef inCommandName, CFStringRef inCommandID, OMCDialog *inDialog, CFTypeRef inContext );
	OSStatus			ExecuteSubcommand( SInt32 commandIndex, OMCDialog *inDialog, CFTypeRef inContext );

	static OSStatus		FSRefCheckFileOrFolder(const FSRef *inRef, void *ioData);
	static OSStatus		CFURLCheckFileOrFolder(CFURLRef inURLRef, void *ioData);

	Boolean				IsSubcommand(CFArrayRef inName, SInt32 inCommandIndex);
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
											CFStringRef inObjTextRef, CommandDescription &currCommand,
											CFStringRef inMultiSeparator, CFStringRef inMultiPrefix, CFStringRef inMultiSuffix,
											UInt16 escSpecialCharsMode, SelectionIterator *inSelIterator,
											CFStringRef inLocTableName = NULL, CFBundleRef inLocBundleRef = NULL);

	void				PopulateEnvironList(CFMutableDictionaryRef ioEnvironList,
											OneObjProperties *inObjList, CFIndex inObjCount, CFIndex inCurrIndex,
											CFStringRef inObjTextRef, CommandDescription &currCommand,
											CFStringRef inMultiSeparator, CFStringRef inMultiPrefix, CFStringRef inMultiSuffix,
											SelectionIterator *inSelIterator);

	CFStringRef			CreateDynamicCommandName(const CommandDescription &currCommand, CFStringRef inLocTableName, CFBundleRef inLocBundleRef);
	void				CreateTextContext(const CommandDescription &currCommand, const AEDesc *inContext);

	SInt32				FindSubcommandIndex(CFArrayRef inName, CFStringRef inCommandID);
	SInt32				FindCommandIndex(CFArrayRef inName, CFStringRef inCommandID);
	OSStatus			SortObjectListByName(CFOptionFlags compareOptions, bool sortAscending);
	CFStringRef			CreateNibControlValue(SInt32 inSpecialWordID, const CommandDescription &currCommand, CFStringRef inNibControlString, UInt16 escSpecialCharsMode, SelectionIterator *inSelIterator, bool isEnvStyle);
//	CFStringRef			CreateNibTableValue(const CommandDescription &currCommand, CFStringRef inNibControlString, UInt16 escSpecialCharsMode);
	CFMutableStringRef	CreateCombinedStringWithObjects(CFArrayRef inArray, CFStringRef inLocTableName, CFBundleRef inLocBundleRef);

	CommandDescription & GetCurrentCommand()
						{
							if( (mCommandList == NULL) || (mCurrCommandIndex >= mCommandCount) )
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

	CFTypeRef			GetCFContext();
	CFBundleRef			GetCurrentCommandExternBundle();

protected:
	
	void				InitNibControlValueEntry(CFStringRef controlID, CFIndex columnIndex);

protected:

	CFObj<CFURLRef>				mPlistURL;
	CFObj<CFURLRef>				mExternBundleOverrideURL;
	SInt32						mSysVersion; //OS version we are running in (10.2 == 0x1020)
	CommandDescription			*mCommandList;
	UInt32						mCommandCount;
	UInt32						mCurrCommandIndex;
    std::vector<OneObjProperties> mObjectList;
	CFIndex						mCurrObjectIndex;
	CFObj<CFMutableArrayRef>	mContextFiles;
	AUniquePtr<SortSettings>	mSortSettings;
	CFObj<CFStringRef>			mContextText;//selected or clipboard text
	CFObj<CFStringRef>			mClipboardText;//may be the same as mContextText, just retained
	CFObj<CFStringRef>			mCommonParentPath;//cached here for better performance
	CFObj<CFStringRef>			mInputText;
	CFObj<CFURLRef>				mCachedSaveAsPath;
	CFObj<CFURLRef>				mCachedChooseFilePath;
	CFObj<CFURLRef>				mCachedChooseFolderPath;
	CFObj<CFURLRef>				mCachedChooseObjectPath;
//	CFObj<CFURLRef>				mMyBundlePath;
	CFObj<CFURLRef>				mMyHostBundlePath;
	CFObj<CFStringRef>			mMyHostName;
	CFObj<CFMutableDictionaryRef> mNibControlValues;
	CFObj<CFMutableDictionaryRef> mNibControlCustomProperties;
	ARefCountedObj<AObserverBase> mObserver;
	OSStatus					mError;
	Boolean						mIsTextInClipboard;
	Boolean						mIsOpenFolder;
	Boolean						mIsNullContext;
	Boolean						mIsTextContext;
	Boolean						mCMPluginMode;
	Boolean						mRunningInShortcutsObserver;
	ProcessSerialNumber			mFrontProcess;//if running in observer we don't want to return observer as front process if it happens to come up
};

void		ExecuteInTerminal(CFStringRef inCommand, bool openInNewWindow, bool bringToFront);
OSErr		SendEventToTerminal(const AEDesc &inCommandDesc, SInt32 sysVersion, bool openInNewWindow, bool bringToFront);
void		ExecuteInITerm(CFStringRef inCommand, CFStringRef inShellPath, bool openInNewWindow, bool bringToFront);
OSErr		SendEventToITerm(const AEDesc &inCommandDesc, CFStringRef inShellPath, SInt32 sysVersion, bool openInNewWindow, bool bringToFront, bool justLaunching);


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

void	ReplaceSpecialCharsWithBackslashEscapes(CFMutableStringRef inStrRef);
void	ReplaceSpecialCharsWithEscapesForAppleScript(CFMutableStringRef inStrRef);
void	WrapWithSingleQuotesForShell(CFMutableStringRef inStrRef);

//removed const from OneObjProperties becuase it allows lazy population of some fields
typedef CFStringRef (*CreateObjProc)(OneObjProperties *inObj, void *ioParam);

CFStringRef			CreateObjPath(OneObjProperties *inObj, void *ioParam);
CFStringRef			CreateObjPathNoExtension(OneObjProperties *inObj, void *ioParam);
CFStringRef			CreateParentPath(OneObjProperties *inObj, void *ioParam);
CFStringRef			CreateObjName(OneObjProperties *inObj, void *ioParam);
CFStringRef			CreateObjNameNoExtension(OneObjProperties *inObj, void *ioParam);
CFStringRef			CreateObjExtensionOnly(OneObjProperties *inObj, void *ioParam);
CFStringRef			CreateObjDisplayName(OneObjProperties *inObj, void *ioParam);
CFStringRef			CreateObjPathRelativeToBase(OneObjProperties *inObj, void *ioParam);

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


CFStringRef			CreateEscapedStringCopy(CFStringRef inStrRef, UInt16 escSpecialCharsMode);
CFStringRef			CreateCombinedString( CFArrayRef inStringsArray, CFStringRef inSeparator, CFStringRef inPrefix, CFStringRef inSuffix, UInt16 escSpecialCharsMode );
};

CFDictionaryRef		ReadControlValuesFromPlist(CFStringRef inDialogUniqueID);
CFStringRef			GetCommandUniqueID(CommandDescription &currCommand);
CFStringRef			CopyNextCommandID(const CommandDescription &currCommand, const CommandState *inCommandState);
Boolean				DisplayVersionWarning(CFBundleRef inBundleRef, CFStringRef dynamicCommandName, CFStringRef inString, SInt32 requiredVersion, SInt32 currVersion);
Boolean				DisplayAlert(CFBundleRef inBundleRef, CFStringRef dynamicCommandName, CFStringRef inAlertString, CFOptionFlags inAlertLevel = kCFUserNotificationStopAlertLevel );


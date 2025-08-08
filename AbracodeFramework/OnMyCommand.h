#pragma once

#include "OutputWindowHandler.h"
#include "ACMPlugin.h"
#include "OMCStrings.h"
#include "CommandDescription.h"
#include "AUniquePtr.h"
#include <vector>

class SelectionIterator;
class AObserverBase;
class OMCDialog;
class CommandRuntimeData;
class OMCContextData;
struct OneObjProperties;

#define CM_IMPL_PLUGIN_PREFS_INDENTIFIER	"com.abracode.OnMyCommandCMPrefs"

enum
{
	kCMCommandStart				= 0x10000000			//command IDs start here
};

typedef enum
{
    kOMCHostApp_Unknown = 0,
    kOMCHostApp_OMCService,
    kOMCHostApp_Shortcuts,
    kOMCHostApp_ShortcutsObserver,
    kOMCHostApp_OMCEdit
} OMCHostApp;

class OnMyCommandCM : public ACMPlugin
{
public:

						OnMyCommandCM(CFTypeRef inPlistRef = NULL);
	virtual				~OnMyCommandCM();
	
	virtual OSStatus	Init();

	virtual OSStatus	ExamineContext( const AEDesc *inAEContext, AEDescList *outCommandPairs );
	virtual OSStatus	ExamineContext( const AEDesc *inAEContext, SInt32 inCommandRef, AEDescList *outCommandPairs );
	virtual OSStatus	ExamineContext( CFTypeRef inContext, SInt32 inCommandRef );

    // the contextual menu API to execute a command
	virtual OSStatus	HandleSelection( AEDesc *inAEContext, SInt32 inCommandRef ); // pass NULL for inAEContext when executing with CF Context
    virtual void		PostMenuCleanup();

	OSStatus			CommonContextCheck( const AEDesc *inAEContext, CFTypeRef inContext, AEDescList *outCommandPairs, SInt32 inCmdIndex );
    // internal API to execute a command
    OSStatus            ExecuteCommand( AEDesc *inAEContext, SInt32 inCommandIndex, const CommandRuntimeData *parentCommandRuntimeData ); // pass NULL for inAEContext when executing with CF Context

	void				AddObserver(AObserverBase *inObserver)
						{
							mObserver.Adopt(inObserver, kARefCountRetain);
						}

	void				RemoveObserver(AObserverBase *inObserver)
						{
							if(mObserver == inObserver)
                            {
                                mObserver.Adopt(NULL);
                            }
						}

	void				DeleteCommandList();

	OSStatus			ExecuteCommandWithObjects(CommandRuntimeData *commandRuntimeData);
	OSStatus			ExecuteCommandWithText(CommandDescription &currCommand, CFStringRef inStrRef, CommandRuntimeData *commandRuntimeData);
	Boolean				DisplayWarning(CommandDescription &currCommand, CommandRuntimeData &commandRuntimeData);
	Boolean				PopulateItemsMenu( const AEDesc *inAEContext,
                                          CommandRuntimeData &commandRuntimeData,
                                          AEDescList* ioRootMenu,
                                          Boolean runningInSpecialApp,
                                          CFStringRef inFrontAppName );
	bool				IsCommandEnabled(CommandDescription &currCommand,
                                         OMCContextData &contextData,
                                         const AEDesc *inAEContext,
                                         CFStringRef currAppName,
                                         bool skipFinderWindowCheck);
	bool				IsCommandEnabled(SInt32 inCmdIndex,
                                         const AEDesc *inAEContext,
                                         OMCContextData &contextData,
                                         bool runningInSpecialApp,
                                         CFStringRef inFrontAppName);

	Boolean				ShowInputDialog( CommandDescription &currCommand, CFStringRef &outStr );

	void				ReadPreferences();
	void				ParseCommandList(CFArrayRef commandArrayRef);
	void				LoadCommandsFromPlistFile(CFURLRef inPlistFileURL);
	void				LoadCommandsFromPlistRef(CFPropertyListRef inPlistRef);

	OSStatus			ExecuteSubcommand(CFArrayRef inCommandName,
                                          CFStringRef inCommandID,
                                          CommandRuntimeData *parentCommandRuntimeData,
                                          CFTypeRef inContext);
	OSStatus			ExecuteSubcommand(SInt32 commandIndex, CommandRuntimeData *parentCommandRuntimeData, CFTypeRef inContext);

	Boolean				IsSubcommand(CFArrayRef inName, CFIndex inCommandIndex);
	SInt32				FindCommandIndex( CFStringRef inNameOrId );
	OSStatus			GetCommandInfo(SInt32 inCommandRef, OMCInfoType infoType, void *outInfo);

	CFMutableStringRef	CreateCommandStringWithObjects(CFArrayRef inFragments,
                                                       CommandRuntimeData &commandRuntimeData,
                                                       UInt16 escSpecialCharsMode);
	CFMutableStringRef	CreateCommandStringWithText(CFArrayRef inFragments,
                                                    CFStringRef inObjTextRef,
                                                    CommandRuntimeData &commandRuntimeData,
                                                    UInt16 escSpecialCharsMode,
                                                    CFStringRef inLocTableName = NULL,
                                                    CFBundleRef inLocBundleRef = NULL);
    
	CFDictionaryRef		CreateEnvironmentVariablesDict(CFStringRef inObjTextRef, CommandRuntimeData &commandRuntimeData);

	void				AppendTextToCommand(CFMutableStringRef inCommandRef, CFStringRef inStrRef,
											OneObjProperties *inObjList, CFIndex inObjCount, CFIndex inCurrIndex,
											CFStringRef inObjTextRef, CommandDescription &currCommand,
                                            CommandRuntimeData &commandRuntimeData, OMCDialog *activeDialog,
											CFStringRef inMultiSeparator, CFStringRef inMultiPrefix, CFStringRef inMultiSuffix,
											UInt16 escSpecialCharsMode, CFStringRef inLocTableName = nullptr, CFBundleRef inLocBundleRef = nullptr);

	void				PopulateEnvironList(CFMutableDictionaryRef ioEnvironList, CommandRuntimeData &commandRuntimeData,
											OneObjProperties *inObjList, CFIndex inObjCount, CFIndex inCurrIndex,
											CFStringRef inObjTextRef, CommandDescription &currCommand,
											CFStringRef inMultiSeparator, CFStringRef inMultiPrefix, CFStringRef inMultiSuffix);

	CFStringRef			CreateDynamicCommandName(const CommandDescription &currCommand,
                                                 CommandRuntimeData &commandRuntimeData,
                                                 CFStringRef inLocTableName,
                                                 CFBundleRef inLocBundleRef);

	SInt32				FindSubcommandIndex(CFArrayRef inName, CFStringRef inCommandID);
	SInt32				FindCommandIndex(CFArrayRef inName, CFStringRef inCommandID);

	CFMutableStringRef	CreateCombinedStringWithObjects(CFArrayRef inArray,
                                                        CommandRuntimeData &commandRuntimeData,
                                                        CFStringRef inLocTableName,
                                                        CFBundleRef inLocBundleRef);

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
    
    // Command execution runtime data should be separate from the OnMyCommandCM engine instance.
    // However, the constraints of original contextual menu APIs contract prevent us from creating
    // a new CommandRuntimeData and passing to ExamineContext() and then HandleSelection().
    // A workaround is to create a new CommandRuntimeData in ExamineContext(), place it in mInitialRuntimeData and
    // then immediately consume in HandleSelection() and empty the temporary mInitialRuntimeData storage
    // this way ExamineContext() always starts with empty runtime data
    // This is not multithreading safe of course: we cannot run ExamineContext()/HandleSelection() concurrently
    // using the same OnMyCommandCM object (the engine was never designed for multithreading anyway)
    
    ARefCountedObj<CommandRuntimeData> mInitialRuntimeData;

	CFObj<CFStringRef>			mMyHostBundlePath;
	CFObj<CFStringRef>			mMyHostAppName;
	CFObj<CFStringRef>			mOmcSupportPath;
	CFObj<CFStringRef>			mOmcResourcesPath;
	ARefCountedObj<AObserverBase> mObserver;
    OSStatus					mError {noErr};
    OMCHostApp					mHostApp {kOMCHostApp_Unknown};
    pid_t			            mFrontProcessPID {0};//if running in observer we don't want to return observer as front process if it happens to come up
};

Boolean DisplayVersionWarning(CFBundleRef inBundleRef, CFStringRef dynamicCommandName, CFStringRef inString, SInt32 requiredVersion, SInt32 currVersion);
Boolean DisplayAlert(CFBundleRef inBundleRef, CFStringRef dynamicCommandName, CFStringRef inAlertString, CFOptionFlags inAlertLevel = kCFUserNotificationStopAlertLevel);


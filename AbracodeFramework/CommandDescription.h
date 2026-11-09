#pragma once

#include "OMC.h"
#include "OMCConstants.h"
#include "CFObj.h"

extern CFStringRef kOMCTopCommandID;

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
    APP_PROCESS_ID, //pid of the applet/host application itself, not the front process - always exported
                    //unlike FRONT_PROCESS_ID / FRONT_APPLICATION_NAME it deliberately does not consult mHostApp: getpid() is the right answer in every host
    MY_HOST_BUNDLE_PATH, //deprecated but supported as of OMC 4.0 - not exported by default though
    MY_EXTERNAL_BUNDLE_PATH, //points to EXTERNAL_BUNDLE_PATH defined in description. redundant but needed for portability
    NIB_DLG_GUID,
    NIB_DLG_CONTROL_VALUE,
    NIB_TABLE_VALUE,
    NIB_TABLE_ALL_ROWS,
    NIB_WEB_VIEW_VALUE,
    ACTIONUI_WINDOW_UUID,
    ACTIONUI_VIEW_VALUE,
    ACTIONUI_TABLE_VALUE,
    ACTIONUI_TABLE_ALL_ROWS,
    ACTIONUI_TRIGGER_VIEW_ID,
    ACTIONUI_TRIGGER_VIEW_PART_ID,
    ACTIONUI_TRIGGER_CONTEXT,
    ACTIONUI_REMOTE_ENDPOINT, //socket path of this process's ActionUI remote bridge - always exported when a bridge is running
    CURRENT_COMMAND_GUID,
    PARENT_COMMAND_GUID,
    PARENT_DIALOG_GUID,
    FRONT_PROCESS_ID,
    FRONT_APPLICATION_NAME,
    TRIGGER_URL //the URL that started this command chain - exported only for runs started by a URL
} SpecialWordID;


typedef struct CommandDescription
{
    CFObj<CFArrayRef>		name;
    CFObj<CFStringRef>		namePlural;
    CFObj<CFArrayRef>		command;//array of CFStrings
    CFObj<CFArrayRef>		inputPipe;//array of CFStrings
    CFObj<CFArrayRef>      activationExtensions;//array of CFStrings
    UInt32			activationTypeCount {0}; // ACTIVATION_FILE_TYPES given: file types are no longer matched, so no file passes
    UInt32          prescannedCommandInfo {kOmcCommandNoSpecialObjects};
    UInt8			executionMode {kExecSilentPOpen};
    UInt8			executionOptions {kExecutionOption_None};
    UInt8			activationMode {kActiveAlways};
    UInt8			escapeSpecialCharsMode {kEscapeWithBackslash};
    UInt8			multipleObjectProcessing {kMulObjProcessUnspecified};
    UInt8			sortMethod {kSortMethodNone};
    UInt8			sortAscending {true};
    UInt8			sortOptions {0};
    CFObj<CFStringRef>		mulObjPrefix;
    CFObj<CFStringRef>		mulObjSuffix;
    CFObj<CFStringRef>		mulObjSeparator;
    CFObj<CFStringRef>		warningStr;
    CFObj<CFStringRef>		warningExecuteStr;
    CFObj<CFStringRef>		warningCancelStr;
    CFObj<CFStringRef>		submenuName;
    Boolean			isPrescanned {false};
    Boolean			bringTerminalToFront {true};
    Boolean			openNewTerminalSession {true};
    Boolean			simulatePaste {false};
    Boolean			nameIsDynamic {false};
    Boolean			nameContainsDynamicText {false};
    UInt16			inputDialogType {kInputNone};
    CFObj<CFStringRef>		inputDialogOK;
    CFObj<CFStringRef>		inputDialogCancel;
    CFObj<CFStringRef>		inputDialogMessage;
    CFObj<CFArrayRef>		inputDialogDefault;
    CFObj<CFArrayRef>		inputDialogMenuItems;//array of name & value pairs
    CFObj<CFArrayRef>		refresh;//a list of strings forming a path for Finder refresh
    CFObj<CFDictionaryRef>	saveAsParams;
    CFObj<CFDictionaryRef>	chooseFileParams;
    CFObj<CFDictionaryRef>	chooseFolderParams;
    CFObj<CFDictionaryRef>	chooseObjectParams;
    CFObj<CFDictionaryRef>	openObjectParams; // OPEN_OBJECT_DIALOG: customizes the open dialog shown when main command requires file context
    CFObj<CFDictionaryRef>	outputWindowOptions;
    CFObj<CFDictionaryRef> nibDialog;
    CFObj<CFDictionaryRef> actionUIWindow;
    CFObj<CFArrayRef>		appNames;
    CFObj<CFStringRef>		commandID;//"top!" = main command, other value = command handler/subcommand - should not appear in contextual menu
    CFObj<CFStringRef>		nextCommandID; //if not NULL, next command
    CFObj<CFStringRef>		externalBundlePath;
    CFObj<CFBundleRef>		externBundle;//populated on first request and cached
    CFObj<CFArrayRef>		popenShell;
    CFObj<CFMutableDictionaryRef>	customEnvironVariables;
    CFObj<CFMutableSetRef> specialRequestedNibControls; //set of special words to export
    Boolean			actOnlyInListedApps {false};//if true - activate only in those listed, if false - exclude those listed
    Boolean			debugging {false}; //set to true when control keyboard modifier is held
    Boolean			disabled {false};
    Boolean			isSubcommand {false};
    Boolean			urlInvocable {false}; //URL_INVOCABLE: the applet's "exe" URL may run this command
    SInt32			requiredOMCVersion {MIN_OMC_VERSION};
    SInt32			requiredMacOSMinVersion {MIN_MAC_OS_VERSION};
    SInt32			requiredMacOSMaxVersion {MAX_MAC_OS_VERSION};
    CFObj<CFStringRef>		iTermShellPath;
    CFObj<CFDictionaryRef>	endNotification;
    CFObj<CFDictionaryRef> progress;
    CFIndex			maxTaskCount {0};
    CFObj<CFStringRef>		contextMatchString;
    UInt32          textReplaceOptions {0};
    UInt8			matchCompareOptions {0};//currently only kCFCompareCaseInsensitive
    UInt8			matchMethod {kMatchExact}; //kMatchExact, kMatchContains, kMatchRegularExpression
    UInt8			matchFileOptions {kMatchFileName};//kMatchFileName, kMatchFilePath
    Boolean			externBundleResolved {false};//costly call to find the extern bundle - do it once and flag it here
    CFObj<CFDictionaryRef> multipleSelectionIteratorParams; //control id and forward/reverse flag
    CFObj<CFStringRef>		localizationTableName;

    // The CF members are owned and released by their CFObj.
    // Commands are never copied: OnMyCommandCM keeps them in one array and hands out references.
    CommandDescription() = default;
    ~CommandDescription() = default;
    CommandDescription(const CommandDescription &) = delete;
    CommandDescription &operator=(const CommandDescription &) = delete;
} CommandDescription;


void PrescanCommandDescription(CommandDescription &currCommand );
void ScanDynamicName(CommandDescription &currCommand);
void GetOneCommandParams(CommandDescription &outDesc, CFDictionaryRef inOneCommand, CFURLRef externBundleOverrideURL);
void GetContextMatchingParams(CommandDescription &outDesc, CFDictionaryRef inParams);

UInt8 GetEscapingMode(CFStringRef theStr);
SpecialWordID GetSpecialWordID(CFStringRef inStr);
SpecialWordID GetSpecialEnvironWordID(CFStringRef inStr);

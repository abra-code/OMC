#pragma once

#include "OMC.h"
#include "OMCConstants.h"

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
    CURRENT_COMMAND_GUID,
    FRONT_PROCESS_ID,
    FRONT_APPLICATION_NAME
} SpecialWordID;


typedef struct CommandDescription
{
    CFArrayRef		name {NULL};
    CFStringRef		namePlural {NULL};
    CFArrayRef		command {NULL};//array of CFStrings
    CFArrayRef		inputPipe {NULL};//array of CFStrings
    CFArrayRef      activationExtensions {NULL};//array of CFStrings
    OSType *		activationTypes {NULL};
    UInt32			activationTypeCount {0};
    UInt32          prescannedCommandInfo {kOmcCommandNoSpecialObjects};
    UInt8			executionMode {kExecSilentPOpen};
    UInt8			executionOptions {kExecutionOption_None};
    UInt8			activationMode {kActiveAlways};
    UInt8			escapeSpecialCharsMode {kEscapeWithBackslash};
    UInt8			multipleObjectProcessing {kMulObjProcessUnspecified};
    UInt8			sortMethod {kSortMethodNone};
    UInt8			sortAscending {true};
    UInt8			sortOptions {0};
    CFStringRef		mulObjPrefix {NULL};
    CFStringRef		mulObjSuffix {NULL};
    CFStringRef		mulObjSeparator {NULL};
    CFStringRef		warningStr {NULL};
    CFStringRef		warningExecuteStr {NULL};
    CFStringRef		warningCancelStr {NULL};
    CFStringRef		submenuName {NULL};
    Boolean			isPrescanned {false};
    Boolean			bringTerminalToFront {true};
    Boolean			openNewTerminalSession {true};
    Boolean			simulatePaste {false};
    Boolean			nameIsDynamic {false};
    Boolean			nameContainsDynamicText {false};
    UInt16			inputDialogType {kInputNone};
    CFStringRef		inputDialogOK {NULL};
    CFStringRef		inputDialogCancel {NULL};
    CFStringRef		inputDialogMessage {NULL};
    CFArrayRef		inputDialogDefault {NULL};
    CFArrayRef		inputDialogMenuItems {NULL};//array of name & value pairs
    CFArrayRef		refresh {NULL};//a list of strings forming a path for Finder refresh
    CFDictionaryRef	saveAsParams {NULL};
    CFDictionaryRef	chooseFileParams {NULL};
    CFDictionaryRef	chooseFolderParams {NULL};
    CFDictionaryRef	chooseObjectParams {NULL};
    CFDictionaryRef	outputWindowOptions {NULL};
    CFDictionaryRef nibDialog {NULL};
    CFDictionaryRef actionUIWindow {NULL};
    CFArrayRef		appNames {NULL};
    CFStringRef		commandID {NULL};//"top!" = main command, other value = command handler/subcommand - should not appear in contextual menu
    CFStringRef		nextCommandID {NULL}; //if not NULL, next command
    CFStringRef		externalBundlePath {NULL};
    CFBundleRef		externBundle {NULL};//populated on first request and cached
    CFArrayRef		popenShell {NULL};
    CFMutableDictionaryRef	customEnvironVariables {NULL};
    CFMutableSetRef specialRequestedNibControls {NULL}; //set of special words to export
    Boolean			actOnlyInListedApps {false};//if true - activate only in those listed, if false - exclude those listed
    Boolean			debugging {false}; //set to true when control keyboard modifier is held
    Boolean			disabled {false};
    Boolean			isSubcommand {false};
    SInt32			requiredOMCVersion {MIN_OMC_VERSION};
    SInt32			requiredMacOSMinVersion {MIN_MAC_OS_VERSION};
    SInt32			requiredMacOSMaxVersion {MAX_MAC_OS_VERSION};
    CFStringRef		iTermShellPath {NULL};
    CFDictionaryRef	endNotification {NULL};
    CFDictionaryRef progress {NULL};
    CFIndex			maxTaskCount {0};
    CFStringRef		contextMatchString {NULL};
    UInt32          textReplaceOptions {0};
    UInt8			matchCompareOptions {0};//currently only kCFCompareCaseInsensitive
    UInt8			matchMethod {kMatchExact}; //kMatchExact, kMatchContains, kMatchRegularExpression
    UInt8			matchFileOptions {kMatchFileName};//kMatchFileName, kMatchFilePath
    Boolean			externBundleResolved {false};//costly call to find the extern bundle - do it once and flag it here
    CFDictionaryRef multipleSelectionIteratorParams {NULL}; //control id and forward/reverse flag
    CFStringRef		localizationTableName {NULL};
} CommandDescription;


void PrescanCommandDescription(CommandDescription &currCommand );
void ScanDynamicName(CommandDescription &currCommand);
void GetOneCommandParams(CommandDescription &outDesc, CFDictionaryRef inOneCommand, CFURLRef externBundleOverrideURL);
void GetContextMatchingParams(CommandDescription &outDesc, CFDictionaryRef inParams);

UInt8 GetEscapingMode(CFStringRef theStr);
SpecialWordID GetSpecialWordID(CFStringRef inStr);
SpecialWordID GetSpecialEnvironWordID(CFStringRef inStr);

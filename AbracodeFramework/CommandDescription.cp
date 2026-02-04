#include "CommandDescription.h"
#include "OMCStrings.h"
#include "CMUtils.h"
#include "ACFDict.h"
#include "ACFArr.h"
#include "DebugSettings.h"
#include <vector>

CFStringRef kOMCTopCommandID = CFSTR("top!");

typedef struct SpecialWordAndID
{
    CFIndex        wordLen;
    CFStringRef    specialWord;
    CFStringRef environName;
    SpecialWordID id;
    bool        alwaysExport { false };
} SpecialWordAndID;

//we take advantage of the fact that __XXX__ word has the same length as OMC_XXX

static const SpecialWordAndID sSpecialWordAndIDList[] =
{
    //wordLen                                                // specialWord         //environName           //id            //always_export
    { sizeof("__OBJ_TEXT__")-1,                                CFSTR("__OBJ_TEXT__"), CFSTR("OMC_OBJ_TEXT"),  OBJ_TEXT, true },
    { sizeof("__OBJ_PATH__")-1,                                CFSTR("__OBJ_PATH__"), CFSTR("OMC_OBJ_PATH"),  OBJ_PATH, true },
    { sizeof("__OBJ_PARENT_PATH__")-1,                        CFSTR("__OBJ_PARENT_PATH__"), CFSTR("OMC_OBJ_PARENT_PATH"),  OBJ_PARENT_PATH, false },
    { sizeof("__OBJ_NAME__")-1,                                CFSTR("__OBJ_NAME__"), CFSTR("OMC_OBJ_NAME"),  OBJ_NAME, false },
    { sizeof("__OBJ_NAME_NO_EXTENSION__")-1,                CFSTR("__OBJ_NAME_NO_EXTENSION__"), CFSTR("OMC_OBJ_NAME_NO_EXTENSION"),  OBJ_NAME_NO_EXTENSION, false },
    { sizeof("__OBJ_EXTENSION_ONLY__")-1,                    CFSTR("__OBJ_EXTENSION_ONLY__"), CFSTR("OMC_OBJ_EXTENSION_ONLY"),  OBJ_EXTENSION_ONLY, false },
    { sizeof("__OBJ_DISPLAY_NAME__")-1,                        CFSTR("__OBJ_DISPLAY_NAME__"), CFSTR("OMC_OBJ_DISPLAY_NAME"),  OBJ_DISPLAY_NAME, false },
    { sizeof("__OBJ_COMMON_PARENT_PATH__")-1,                CFSTR("__OBJ_COMMON_PARENT_PATH__"), CFSTR("OMC_OBJ_COMMON_PARENT_PATH"),  OBJ_COMMON_PARENT_PATH, false },
    { sizeof("__OBJ_PATH_RELATIVE_TO_COMMON_PARENT__")-1,    CFSTR("__OBJ_PATH_RELATIVE_TO_COMMON_PARENT__"), CFSTR("OMC_OBJ_PATH_RELATIVE_TO_COMMON_PARENT"),  OBJ_PATH_RELATIVE_TO_COMMON_PARENT, false },

    { sizeof("__DLG_INPUT_TEXT__")-1,                        CFSTR("__DLG_INPUT_TEXT__"), CFSTR("OMC_DLG_INPUT_TEXT"),  DLG_INPUT_TEXT, false },

    { sizeof("__DLG_SAVE_AS_PATH__")-1,                        CFSTR("__DLG_SAVE_AS_PATH__"), CFSTR("OMC_DLG_SAVE_AS_PATH"),  DLG_SAVE_AS_PATH, false },
    { sizeof("__DLG_SAVE_AS_PARENT_PATH__")-1,                CFSTR("__DLG_SAVE_AS_PARENT_PATH__"), CFSTR("OMC_DLG_SAVE_AS_PARENT_PATH"),  DLG_SAVE_AS_PARENT_PATH, false },
    { sizeof("__DLG_SAVE_AS_NAME__")-1,                        CFSTR("__DLG_SAVE_AS_NAME__"), CFSTR("OMC_DLG_SAVE_AS_NAME"),  DLG_SAVE_AS_NAME, false },
    { sizeof("__DLG_SAVE_AS_NAME_NO_EXTENSION__")-1,        CFSTR("__DLG_SAVE_AS_NAME_NO_EXTENSION__"), CFSTR("OMC_DLG_SAVE_AS_NAME_NO_EXTENSION"),  DLG_SAVE_AS_NAME_NO_EXTENSION, false },
    { sizeof("__DLG_SAVE_AS_EXTENSION_ONLY__")-1,            CFSTR("__DLG_SAVE_AS_EXTENSION_ONLY__"), CFSTR("OMC_DLG_SAVE_AS_EXTENSION_ONLY"),  DLG_SAVE_AS_EXTENSION_ONLY, false },

    { sizeof("__DLG_CHOOSE_FILE_PATH__")-1,                    CFSTR("__DLG_CHOOSE_FILE_PATH__"), CFSTR("OMC_DLG_CHOOSE_FILE_PATH"),  DLG_CHOOSE_FILE_PATH, false },
    { sizeof("__DLG_CHOOSE_FILE_PARENT_PATH__")-1,            CFSTR("__DLG_CHOOSE_FILE_PARENT_PATH__"), CFSTR("OMC_DLG_CHOOSE_FILE_PARENT_PATH"),  DLG_CHOOSE_FILE_PARENT_PATH, false },
    { sizeof("__DLG_CHOOSE_FILE_NAME__")-1,                    CFSTR("__DLG_CHOOSE_FILE_NAME__"), CFSTR("OMC_DLG_CHOOSE_FILE_NAME"),  DLG_CHOOSE_FILE_NAME, false },
    { sizeof("__DLG_CHOOSE_FILE_NAME_NO_EXTENSION__")-1,    CFSTR("__DLG_CHOOSE_FILE_NAME_NO_EXTENSION__"), CFSTR("OMC_DLG_CHOOSE_FILE_NAME_NO_EXTENSION"),  DLG_CHOOSE_FILE_NAME_NO_EXTENSION, false },
    { sizeof("__DLG_CHOOSE_FILE_EXTENSION_ONLY__")-1,        CFSTR("__DLG_CHOOSE_FILE_EXTENSION_ONLY__"), CFSTR("OMC_DLG_CHOOSE_FILE_EXTENSION_ONLY"),  DLG_CHOOSE_FILE_EXTENSION_ONLY, false },

    { sizeof("__DLG_CHOOSE_FOLDER_PATH__")-1,                CFSTR("__DLG_CHOOSE_FOLDER_PATH__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_PATH"),  DLG_CHOOSE_FOLDER_PATH, false },
    { sizeof("__DLG_CHOOSE_FOLDER_PARENT_PATH__")-1,        CFSTR("__DLG_CHOOSE_FOLDER_PARENT_PATH__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_PARENT_PATH"),  DLG_CHOOSE_FOLDER_PARENT_PATH, false },
    { sizeof("__DLG_CHOOSE_FOLDER_NAME__")-1,                CFSTR("__DLG_CHOOSE_FOLDER_NAME__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_NAME"),  DLG_CHOOSE_FOLDER_NAME, false },
    { sizeof("__DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION__")-1,    CFSTR("__DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION"),  DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION, false },
    { sizeof("__DLG_CHOOSE_FOLDER_EXTENSION_ONLY__")-1,        CFSTR("__DLG_CHOOSE_FOLDER_EXTENSION_ONLY__"), CFSTR("OMC_DLG_CHOOSE_FOLDER_EXTENSION_ONLY"),  DLG_CHOOSE_FOLDER_EXTENSION_ONLY, false },

    { sizeof("__DLG_CHOOSE_OBJECT_PATH__")-1,                CFSTR("__DLG_CHOOSE_OBJECT_PATH__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_PATH"),  DLG_CHOOSE_OBJECT_PATH, false },
    { sizeof("__DLG_CHOOSE_OBJECT_PARENT_PATH__")-1,        CFSTR("__DLG_CHOOSE_OBJECT_PARENT_PATH__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_PARENT_PATH"),  DLG_CHOOSE_OBJECT_PARENT_PATH, false },
    { sizeof("__DLG_CHOOSE_OBJECT_NAME__")-1,                CFSTR("__DLG_CHOOSE_OBJECT_NAME__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_NAME"),  DLG_CHOOSE_OBJECT_NAME, false },
    { sizeof("__DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION__")-1,    CFSTR("__DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION"),  DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION, false },
    { sizeof("__DLG_CHOOSE_OBJECT_EXTENSION_ONLY__")-1,        CFSTR("__DLG_CHOOSE_OBJECT_EXTENSION_ONLY__"), CFSTR("OMC_DLG_CHOOSE_OBJECT_EXTENSION_ONLY"),  DLG_CHOOSE_OBJECT_EXTENSION_ONLY, false },

    { sizeof("__OMC_RESOURCES_PATH__")-1,                    CFSTR("__OMC_RESOURCES_PATH__"), CFSTR("OMC_OMC_RESOURCES_PATH"),  OMC_RESOURCES_PATH, true },//framework path
    { sizeof("__OMC_SUPPORT_PATH__")-1,                        CFSTR("__OMC_SUPPORT_PATH__"), CFSTR("OMC_OMC_SUPPORT_PATH"),  OMC_SUPPORT_PATH, true },//framework path
    { sizeof("__APP_BUNDLE_PATH__")-1,                        CFSTR("__APP_BUNDLE_PATH__"), CFSTR("OMC_APP_BUNDLE_PATH"),  APP_BUNDLE_PATH, true },//preferred for applets
    { sizeof("__MY_EXTERNAL_BUNDLE_PATH__")-1,                CFSTR("__MY_EXTERNAL_BUNDLE_PATH__"), CFSTR("OMC_MY_EXTERNAL_BUNDLE_PATH"),  MY_EXTERNAL_BUNDLE_PATH, false },//external bundle location
    { sizeof("__NIB_DLG_GUID__")-1,                            CFSTR("__NIB_DLG_GUID__"), CFSTR("OMC_NIB_DLG_GUID"),  NIB_DLG_GUID, true },
    { sizeof("__CURRENT_COMMAND_GUID__")-1,                    CFSTR("__CURRENT_COMMAND_GUID__"), CFSTR("OMC_CURRENT_COMMAND_GUID"),  CURRENT_COMMAND_GUID, true },
    
    { sizeof("__FRONT_PROCESS_ID__")-1,                        CFSTR("__FRONT_PROCESS_ID__"), CFSTR("OMC_FRONT_PROCESS_ID"),  FRONT_PROCESS_ID, false },
    { sizeof("__FRONT_APPLICATION_NAME__")-1,                CFSTR("__FRONT_APPLICATION_NAME__"), CFSTR("OMC_FRONT_APPLICATION_NAME"),  FRONT_APPLICATION_NAME, false },
    
//deprecated synonyms, still supported but should not appear in OMCEdit choices
    { sizeof("__MY_HOST_BUNDLE_PATH__")-1,                    CFSTR("__MY_HOST_BUNDLE_PATH__"), CFSTR("OMC_MY_HOST_BUNDLE_PATH"),  MY_HOST_BUNDLE_PATH, false },//deprecated as of OMC 4.0
    { sizeof("__INPUT_TEXT__")-1,                            CFSTR("__INPUT_TEXT__"), CFSTR("OMC_INPUT_TEXT"),  DLG_INPUT_TEXT, false },
    { sizeof("__OBJ_PATH_NO_EXTENSION__")-1,                CFSTR("__OBJ_PATH_NO_EXTENSION__"), CFSTR("OMC_OBJ_PATH_NO_EXTENSION"),  OBJ_PATH_NO_EXTENSION, false },//not needed since = OBJ_PARENT_PATH + OBJ_NAME_NO_EXTENSION
    { sizeof("__PASSWORD__")-1,                                CFSTR("__PASSWORD__"), CFSTR("OMC_PASSWORD"),  DLG_PASSWORD, false },
    { sizeof("__SAVE_AS_PATH__")-1,                            CFSTR("__SAVE_AS_PATH__"), CFSTR("OMC_SAVE_AS_PATH"),  DLG_SAVE_AS_PATH, false },
    { sizeof("__SAVE_AS_PARENT_PATH__")-1,                    CFSTR("__SAVE_AS_PARENT_PATH__"), CFSTR("OMC_SAVE_AS_PARENT_PATH"),  DLG_SAVE_AS_PARENT_PATH, false },
    { sizeof("__SAVE_AS_FILE_NAME__")-1,                    CFSTR("__SAVE_AS_FILE_NAME__"), CFSTR("OMC_SAVE_AS_FILE_NAME"),  DLG_SAVE_AS_NAME, false },
    { sizeof("__MY_BUNDLE_PATH__")-1,                        CFSTR("__MY_BUNDLE_PATH__"), CFSTR("OMC_MY_BUNDLE_PATH"),  MY_BUNDLE_PATH, false }//added for droplets, not very useful for CM
};

//min and max len defined for slight optimization in resolving special words
//the shortest is __OBJ_TEXT__
const CFIndex kMinSpecialWordLen = sizeof("__OBJ_TEXT__") - 1;
//the longest is __DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION__
const CFIndex kMaxSpecialWordLen = sizeof("__DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION__") - 1;

//there are also dynamic names:
//                 __NIB_DIALOG_CONTROL_NNN_VALUE__            OMC_NIB_DIALOG_CONTROL_NNN_VALUE
//                 __NIB_TABLE_NNN_COLUMN_MMM_VALUE__          OMC_NIB_TABLE_NNN_COLUMN_MMM_VALUE
//                 __NIB_TABLE_NNN_COLUMN_MMM_ALL_ROWS_VALUE__ OMC_NIB_TABLE_NNN_COLUMN_MMM_ALL_ROWS_VALUE
//                 __NIB_WEBVIEW_NNN_ELEMENT_MMM_VALUE__       OMC_NIB_WEBVIEW_NNN_ELEMENT_MMM_VALUE

static void
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


SpecialWordID
GetSpecialWordID(CFStringRef inStr)
{
#if 0
    TRACE_CSTR( "OnMyCommandCM->GetSpecialWordID\n" );
#endif

    if(inStr == NULL)
        return NO_SPECIAL_WORD;

      CFIndex    strLen = ::CFStringGetLength(inStr);
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

SpecialWordID
GetSpecialEnvironWordID(CFStringRef inStr)
{
#if 0
    TRACE_CSTR( "OnMyCommandCM->GetSpecialEnvironWordID\n" );
#endif

    if(inStr == NULL)
        return NO_SPECIAL_WORD;

      CFIndex    strLen = ::CFStringGetLength(inStr);
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

static void
GetInputDialogParams(CommandDescription &outDesc, CFDictionaryRef inParams)
{
    CFStringRef theStr;

    ACFDict params(inParams);
    outDesc.inputDialogType = kInputClearText; // default if explicit setting is absent
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

static CFMutableDictionaryRef
CreateAllCoreEnvironmentVariablePlaceholders()
{
    CFMutableDictionaryRef outDict = ::CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    size_t theCount = sizeof(sSpecialWordAndIDList)/sizeof(SpecialWordAndID);
    for(size_t i = 0; i< theCount; i++)
    {
        if(sSpecialWordAndIDList[i].alwaysExport)
        {
            CFDictionaryAddValue(outDict, sSpecialWordAndIDList[i].environName, kCFBooleanFalse /*placeholder*/);
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


void
GetOneCommandParams(CommandDescription &outDesc, CFDictionaryRef inOneCommand, CFURLRef externBundleOverrideURL)
{
//    TRACE_CSTR("OnMyCommandCM. GetOneCommandParams\n" );

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
//    'top!' - for main/master command
//    'ini!' - for dialog initialization code
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
//        TRACE_CSTR("\tGetOneCommandParams. EXECUTION_MODE string:\n" );
//        TRACE_CFSTR(theStr);

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
            TRACE_CSTR( "OMC->GetOneCommandParams. EXECUTION_MODE is not specified. Defaulting to exe_shell_script or exe_script_file\n" );
        }
    }

//imput pipe array
    oneCmd.CopyValue(CFSTR("STANDARD_INPUT_PIPE"), outDesc.inputPipe);

//    if(false)
//    {
//        LOG_CSTR( "OMC->GetOneCommandParams. STANDARD_INPUT_PIPE param not of type CFArray\n" );
//    }

    if( outDesc.executionMode == kExecITerm )
        oneCmd.CopyValue(CFSTR("ITERM_SHELL_PATH"), outDesc.iTermShellPath);

//activation
    if( oneCmd.GetValue(CFSTR("ACTIVATION_MODE"), theStr) )
    {
//        TRACE_CSTR("\tGetOneCommandParams. ACTIVATION_MODE string:\n" );
//        TRACE_CFSTR(theStr);

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
//        TRACE_CSTR("\tGetOneCommandParams. ESCAPE_SPECIAL_CHARS string:\n" );
//        TRACE_CFSTR(theStr);
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
                {
                    outDesc.activationTypes[i] = UTGetOSTypeFromString(typeStrRef);
                }
            }
        }
    }

//extensions
    oneCmd.CopyValue(CFSTR("ACTIVATION_EXTENSIONS"), outDesc.activationExtensions);

//mutiple objects settings
    if( oneCmd.GetValue(CFSTR("MULTIPLE_OBJECT_SETTINGS"), theDict) )
    {
        GetMultiCommandParams( outDesc, theDict );
    }
    
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
    {
        GetInputDialogParams( outDesc, theDict );
    }

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
//        TRACE_CSTR("\tGetOneCommandParams. TEXT_REPLACE_OPTION string:\n" );
//        TRACE_CFSTR(theStr);

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
    if(externBundleOverrideURL != nullptr)//extern bundle path override is used when OMC is passed a .omc package for execution instead of plist file
    {
        outDesc.externalBundlePath = ::CFURLCopyFileSystemPath(externBundleOverrideURL, kCFURLPOSIXPathStyle);
    }
    else if(oneCmd.GetValue(CFSTR("EXTERNAL_BUNDLE_PATH"), theStr))
    {
        outDesc.externalBundlePath = CreatePathByExpandingTilde( theStr );//keep the string, we are responsible for releasing it
    }

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

// The presence of dialog settings is a trigger for showing given dialog and exporting its path variable
    if(outDesc.chooseObjectParams != nullptr) // CHOOSE_OBJECT_DIALOG settings present
    {
        CFDictionaryAddValue(outDesc.customEnvironVariables, CFSTR("OMC_DLG_CHOOSE_OBJECT_PATH"), CFSTR(""));
    }

    if(outDesc.chooseFileParams != nullptr) // CHOOSE_FILE_DIALOG settings present
    {
        CFDictionaryAddValue(outDesc.customEnvironVariables, CFSTR("OMC_DLG_CHOOSE_FILE_PATH"), CFSTR(""));
    }
    
    if(outDesc.chooseFolderParams != nullptr) // CHOOSE_FOLDER_DIALOG settigns present
    {
        CFDictionaryAddValue(outDesc.customEnvironVariables, CFSTR("OMC_DLG_CHOOSE_FOLDER_PATH"), CFSTR(""));
    }

    if(outDesc.saveAsParams != nullptr) // SAVE_AS_DIALOG settings present
    {
        CFDictionaryAddValue(outDesc.customEnvironVariables, CFSTR("OMC_DLG_SAVE_AS_PATH"), CFSTR(""));
    }

    if(outDesc.inputDialogType != kInputNone) // INPUT_DIALOG settings present
    {
        CFDictionaryAddValue(outDesc.customEnvironVariables, CFSTR("OMC_DLG_INPUT_TEXT"), CFSTR(""));
    }

// using deputy for background execution?
// no longer supported
//    oneCmd.GetValue(CFSTR("SEND_TASK_TO_BACKGROUND_APP"), outDesc.unused);

    oneCmd.CopyValue(CFSTR("END_NOTIFICATION"), outDesc.endNotification);

    oneCmd.CopyValue(CFSTR("PROGRESS"), outDesc.progress);

    oneCmd.GetValue(CFSTR("MAX_PARALLEL_TASK_COUNT"), outDesc.maxTaskCount);

    Boolean useNavDialogForMissingFileContext = true;
    oneCmd.GetValue(CFSTR("USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT"), useNavDialogForMissingFileContext);
    if(useNavDialogForMissingFileContext)
    {
        outDesc.executionOptions |= kExecutionOption_UseNavDialogForMissingFileContext;
    }
    
    Boolean waitForTaskCompletion = false;
    oneCmd.GetValue(CFSTR("WAIT_FOR_TASK_COMPLETION"), waitForTaskCompletion);
    if(waitForTaskCompletion)
    {
        outDesc.executionOptions |= kExecutionOption_WaitForTaskCompletion;
    }
    
//name/path/text matching settings
    if( oneCmd.GetValue(CFSTR("ACTIVATION_OBJECT_STRING_MATCH"), theDict) )
    {
        GetContextMatchingParams( outDesc, theDict );
    }
    
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

CFStringRef sEscapeModes[] =
{
    CFSTR("esc_none"), //kEscapeNone
    CFSTR("esc_with_backslash"), //kEscapeWithBackslash
    CFSTR("esc_with_percent"), //kEscapeWithPercent
    CFSTR("esc_with_percent_all"), //kEscapeWithPercentAll
    CFSTR("esc_for_applescript"), //kEscapeForAppleScript
    CFSTR("esc_wrap_with_single_quotes_for_shell") //kEscapeWrapWithSingleQuotesForShell
};

UInt8
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

static void
ProcessOnePrescannedWord(CommandDescription &currCommand, SInt32 specialWordID, CFStringRef inSpecialWord, bool isEnvironVariable)
{
    switch(specialWordID)
    {
        case NO_SPECIAL_WORD:
//                    TRACE_CSTR("NO_SPECIAL_WORD\n" );
            
        break;
        
        case OBJ_TEXT:
//                    TRACE_CSTR("OBJ_TEXT\n" );
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
//                    TRACE_CSTR("OBJ_PATH\n" );
            currCommand.prescannedCommandInfo |= kOmcCommandContainsFileObject;
        break;
        
        case DLG_INPUT_TEXT:
//                    TRACE_CSTR("DLG_INPUT_TEXT\n" );
            currCommand.prescannedCommandInfo |= kOmcCommandContainsInputText;
        break;
        
        case DLG_SAVE_AS_PATH:
        case DLG_SAVE_AS_PARENT_PATH:
        case DLG_SAVE_AS_NAME:
        case DLG_SAVE_AS_NAME_NO_EXTENSION:
        case DLG_SAVE_AS_EXTENSION_ONLY:
//                    TRACE_CSTR("DLG_SAVE_AS_PATH\n" );
            currCommand.prescannedCommandInfo |= kOmcCommandContainsSaveAsDialog;
        break;

        case DLG_CHOOSE_FILE_PATH:
        case DLG_CHOOSE_FILE_PARENT_PATH:
        case DLG_CHOOSE_FILE_NAME:
        case DLG_CHOOSE_FILE_NAME_NO_EXTENSION:
        case DLG_CHOOSE_FILE_EXTENSION_ONLY:
//                    TRACE_CSTR("DLG_CHOOSE_FILE_PATH\n" );
            currCommand.prescannedCommandInfo |= kOmcCommandContainsChooseFileDialog;
        break;
        
        case DLG_CHOOSE_FOLDER_PATH:
        case DLG_CHOOSE_FOLDER_PARENT_PATH:
        case DLG_CHOOSE_FOLDER_NAME:
        case DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION:
        case DLG_CHOOSE_FOLDER_EXTENSION_ONLY:
//                    TRACE_CSTR("DLG_CHOOSE_FOLDER_PATH\n" );
            currCommand.prescannedCommandInfo |= kOmcCommandContainsChooseFolderDialog;
        break;
        
        case DLG_CHOOSE_OBJECT_PATH:
        case DLG_CHOOSE_OBJECT_PARENT_PATH:
        case DLG_CHOOSE_OBJECT_NAME:
        case DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION:
        case DLG_CHOOSE_OBJECT_EXTENSION_ONLY:
//                    TRACE_CSTR("DLG_CHOOSE_OBJECT_PATH\n" );
            currCommand.prescannedCommandInfo |= kOmcCommandContainsChooseObjectDialog;
        break;
        
        case DLG_PASSWORD:
//                    TRACE_CSTR("DLG_PASSWORD\n" );
            currCommand.inputDialogType = kInputPasswordText;
            currCommand.prescannedCommandInfo |= kOmcCommandContainsInputText;
        break;
        
        case NIB_DLG_CONTROL_VALUE:
        case NIB_TABLE_VALUE:
        case NIB_WEB_VIEW_VALUE:
        break;

        case NIB_TABLE_ALL_ROWS: //special expensive case not always exported, only on demand
        {
//            TRACE_CSTR("NIB_TABLE_VALUE\n" );
            if( currCommand.specialRequestedNibControls == nullptr)
                currCommand.specialRequestedNibControls = CFSetCreateMutable(kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);

            CFSetAddValue(currCommand.specialRequestedNibControls, inSpecialWord);
        }
        break;
    }
}

void
FindEnvironmentVariables(CommandDescription &currCommand, CFStringRef inString)
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
PrescanArrayOfObjects( CommandDescription &currCommand, CFArrayRef inObjects )
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
PrescanEnvironmentVariables(CommandDescription &currCommand, CFDictionaryRef inEnvironList)
{
    if(inEnvironList == nullptr)
        return;

    CFIndex itemCount = ::CFDictionaryGetCount(inEnvironList);
    std::vector<void *> keyList(itemCount); // OK to create empty container if itemCount == 0
    std::vector<void *> valueList(itemCount); // OK to create empty container if itemCount == 0
 
    if(itemCount > 0)
    {
        CFDictionaryGetKeysAndValues(inEnvironList, (const void **)keyList.data(), (const void **)valueList.data());
    }
        
    for(CFIndex i = 0; i < itemCount; i++)
    {        
        CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[(size_t)i] );
        SpecialWordID specialWordID = GetSpecialEnvironWordID(theKey);
        if(specialWordID != NO_SPECIAL_WORD)
        {
            // only prescan environment variable list keys if the value is string
            // custom env var keys defined in command plist have string values
            // default "always export" keys have kCFBooleanFalse values and should be filtered out at this point
            // because the goal of prescanning is to determine the intent of the command designer:
            // which objects are requested to be explicitly exported
            CFStringRef envVal = ACFType<CFStringRef>::DynamicCast( valueList[(size_t)i] );
            if(envVal != nullptr)
            {
                ProcessOnePrescannedWord(currCommand, specialWordID, theKey, true);
            }
        }
    }
}

void
PrescanCommandDescription( CommandDescription &currCommand )
{
    if( currCommand.isPrescanned )
        return;

//    TRACE_CSTR("OnMyCommandCM->PrescanCommandDescription\n" );
    if(currCommand.command != nullptr)
    {
        PrescanArrayOfObjects( currCommand, currCommand.command );
    }

    if(currCommand.inputPipe != nullptr)
    {
        PrescanArrayOfObjects( currCommand, currCommand.inputPipe );
    }
    
    if(currCommand.customEnvironVariables != nullptr)
    {
        PrescanEnvironmentVariables(currCommand, currCommand.customEnvironVariables);
    }
}

void
ScanDynamicName(CommandDescription &currCommand)
{
    if( currCommand.name == nullptr )
        return;

//    TRACE_CSTR("OnMyCommandCM->ScanDynamicName\n" );

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

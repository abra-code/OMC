//**************************************************************************************
// Filename:	OMCNavigationDialogs.cp
//
// Description:	
//
//**************************************************************************************


#include "OMCNavigationDialogs.h"
#include "OnMyCommand.h"
#include "CommandDescription.h"
#include "CommandRuntimeData.h"
#include "OMCContextData.h"
#include "OMCFilePanels.h"
#include "StSwitchToFront.h"
#include "ACFDict.h"
#include "CMUtils.h"

UInt32
GetNavDialogParams(CFDictionaryRef inParams, CFStringRef &outMessage, CFArrayRef &outDefaultName, CFArrayRef &outDefaultLocation, CFStringRef &outIdentifier, CFStringRef &outPrompt)
{
    ACFDict params(inParams);
    params.CopyValue( CFSTR("MESSAGE"), outMessage );
    params.CopyValue( CFSTR("DEFAULT_FILE_NAME"), outDefaultName );
    params.CopyValue( CFSTR("DEFAULT_LOCATION"), outDefaultLocation );
    params.CopyValue( CFSTR("DIALOG_IDENTIFIER"), outIdentifier );
    params.CopyValue( CFSTR("BUTTON_PROMPT"), outPrompt );
    
    UInt32 outAdditionalNavServiesFlags = 0;
    Boolean boolValue;
    if( params.GetValue(CFSTR("SHOW_INVISIBLE_ITEMS"), boolValue) && boolValue )
        outAdditionalNavServiesFlags |= kOMCFilePanelAllowInvisibleItems;

    if( params.GetValue(CFSTR("ALLOW_MULTIPLE_ITEMS"), boolValue) && boolValue )
        outAdditionalNavServiesFlags |= kOMCFilePanelAllowMultipleItems;

    boolValue = true; //default is true: reuse cached path from main command or other subcommand
    params.GetValue(CFSTR("USE_PATH_CACHING"), boolValue);

    if(boolValue)
    {
        outAdditionalNavServiesFlags |= kOMCFilePanelUseCachedPath;
    }
    
    return outAdditionalNavServiesFlags;
}

void
PresentSaveAsDialog(OnMyCommandCM *inPlugin,
                    CommandRuntimeData &commandRuntimeData,
                    CFStringRef commandName,
                    CFBundleRef localizationBundle)
{
    CommandDescription &currCommand = inPlugin->GetCurrentCommand();
    OMCContextData &contextData = commandRuntimeData.GetContextData();
    
    CFObj<CFStringRef> message;
    CFObj<CFArrayRef> defaultFileName;
    CFObj<CFArrayRef> defaultDirPath;
    CFObj<CFStringRef> identifier;
    CFObj<CFStringRef> prompt;
    UInt32 additionalFlags = GetNavDialogParams(currCommand.saveAsParams, message.GetReference(), defaultFileName.GetReference(), defaultDirPath.GetReference(), identifier.GetReference(), prompt.GetReference());
    if(identifier == nullptr)
        identifier.Adopt(currCommand.commandID, kCFObjRetain);
    
    if( ((additionalFlags & kOMCFilePanelUseCachedPath) == 0) || (commandRuntimeData.cachedSaveAsPath == nullptr) )
    {
        TRACE_CSTR("OnMyCommandCM About to display save as dialog\n" );
        CFObj<CFMutableStringRef> defaultName( inPlugin->CreateCombinedStringWithObjects(defaultFileName,
                                                                               commandRuntimeData,
                                                                               currCommand.localizationTableName,
                                                                               localizationBundle) );
        
        CFObj<CFStringRef> expandedDirStr;
        CFObj<CFMutableStringRef> defaultLocationStr( inPlugin->CreateCombinedStringWithObjects(defaultDirPath,
                                                                                      commandRuntimeData,
                                                                                      nullptr,
                                                                                      nullptr) );
        if(defaultLocationStr != NULL)
        {
            expandedDirStr.Adopt( CreatePathByExpandingTilde( defaultLocationStr ) );
        }
        
        if( (currCommand.localizationTableName != NULL) && (localizationBundle != NULL) && (message != NULL) )
            message.Adopt( ::CFCopyLocalizedStringFromTableInBundle( message, currCommand.localizationTableName, localizationBundle, "") );

        StSwitchToFront switcher;
        contextData.saveAsPath.Adopt(CreateCFURLFromSaveAsDialog( commandName, message, defaultName, expandedDirStr, identifier, prompt, additionalFlags));
        if(contextData.saveAsPath == nullptr)
        {
            throw OSStatus(userCanceledErr);
        }

        if( (additionalFlags & kOMCFilePanelUseCachedPath) != 0 )
        {
            commandRuntimeData.cachedSaveAsPath = contextData.saveAsPath;
        }
    }
    else
    {
        contextData.saveAsPath = commandRuntimeData.cachedSaveAsPath;
    }
}

void
PresentChooseFileDialog(OnMyCommandCM *inPlugin,
                         CommandRuntimeData &commandRuntimeData,
                         CFStringRef commandName,
                         CFBundleRef localizationBundle)
{
    CommandDescription &currCommand = inPlugin->GetCurrentCommand();
    OMCContextData &contextData = commandRuntimeData.GetContextData();

    CFObj<CFStringRef> message;
    CFObj<CFArrayRef> defaultFileName;
    CFObj<CFArrayRef> defaultDirPath;
    CFObj<CFStringRef> identifier;
    CFObj<CFStringRef> prompt;
    UInt32 additionalFlags = GetNavDialogParams(currCommand.chooseFileParams, message.GetReference(), defaultFileName.GetReference(), defaultDirPath.GetReference(), identifier.GetReference(), prompt.GetReference());
    if(identifier == nullptr)
        identifier.Adopt(currCommand.commandID, kCFObjRetain);

    if( ((additionalFlags & kOMCFilePanelUseCachedPath) == 0) || (commandRuntimeData.cachedChooseFilePaths == nullptr) )
    {
        TRACE_CSTR("OnMyCommandCM About to display choose file dialog\n" );
        CFObj<CFMutableStringRef> defaultName( inPlugin->CreateCombinedStringWithObjects(defaultFileName,
                                                                               commandRuntimeData,
                                                                               currCommand.localizationTableName,
                                                                               localizationBundle) );
        
        CFObj<CFStringRef> expandedDirStr;
        CFObj<CFMutableStringRef> defaultLocationStr( inPlugin->CreateCombinedStringWithObjects(defaultDirPath,
                                                                                      commandRuntimeData,
                                                                                      nullptr,
                                                                                      nullptr) );
        if(defaultLocationStr != NULL)
        {
            expandedDirStr.Adopt( CreatePathByExpandingTilde( defaultLocationStr ) );
        }

        if( (currCommand.localizationTableName != NULL) && (localizationBundle != NULL) && (message != NULL) )
        {
            message.Adopt( ::CFCopyLocalizedStringFromTableInBundle( message, currCommand.localizationTableName, localizationBundle, "") );
        }

        StSwitchToFront switcher;
        contextData.chooseFilePaths.Adopt(CreateCFURLsFromOpenDialog(commandName, message, defaultName, defaultLocationStr, identifier, prompt, additionalFlags | kOMCFilePanelCanChooseFiles));
        if(contextData.chooseFilePaths == NULL || CFArrayGetCount(contextData.chooseFilePaths) == 0)
        {
            throw OSStatus(userCanceledErr);
        }
        
        if(contextData.isNullContext)
        { // if command is executed without context, the chosen objects become the file/folder context
            contextData.objectList.resize(0);
            UInt32 theFlags = kListClear;
            size_t validObjectCount = CMUtils::ProcessObjectList(contextData.chooseFilePaths.Get(), theFlags, CFURLCheckFileOrFolder, &contextData.objectList);
            if(validObjectCount > 0)
            {
                contextData.isNullContext = false;
            }
        }

        if( (additionalFlags & kOMCFilePanelUseCachedPath) != 0 )
        {
            commandRuntimeData.cachedChooseFilePaths = contextData.chooseFilePaths;
        }
    }
    else
    {
        contextData.chooseFilePaths = commandRuntimeData.cachedChooseFilePaths;
    }
}

void
PresentChooseFolderDialog(OnMyCommandCM *inPlugin,
                          CommandRuntimeData &commandRuntimeData,
                          CFStringRef commandName,
                          CFBundleRef localizationBundle)
{
    CommandDescription &currCommand = inPlugin->GetCurrentCommand();
    OMCContextData &contextData = commandRuntimeData.GetContextData();

    CFObj<CFStringRef> message;
    CFObj<CFArrayRef> defaultFileName;
    CFObj<CFArrayRef> defaultDirPath;
    CFObj<CFStringRef> identifier;
    CFObj<CFStringRef> prompt;
    UInt32 additionalFlags = GetNavDialogParams(currCommand.chooseFolderParams, message.GetReference(), defaultFileName.GetReference(), defaultDirPath.GetReference(), identifier.GetReference(), prompt.GetReference());
    if(identifier == nullptr)
        identifier.Adopt(currCommand.commandID, kCFObjRetain);
    
    if( ((additionalFlags & kOMCFilePanelUseCachedPath) == 0) || (commandRuntimeData.cachedChooseFolderPaths == nullptr) )
    {
        TRACE_CSTR("OnMyCommandCM About to display choose folder dialog\n" );
        CFObj<CFMutableStringRef> defaultName( inPlugin->CreateCombinedStringWithObjects(defaultFileName,
                                                                               commandRuntimeData,
                                                                               currCommand.localizationTableName,
                                                                               localizationBundle) );
        
        CFObj<CFStringRef> expandedDirStr;
        CFObj<CFMutableStringRef> defaultLocationStr( inPlugin->CreateCombinedStringWithObjects(defaultDirPath,
                                                                                      commandRuntimeData,
                                                                                      NULL,
                                                                                      NULL) );
        if(defaultLocationStr != NULL)
        {
            expandedDirStr.Adopt( CreatePathByExpandingTilde( defaultLocationStr ) );
        }
        
        if( (currCommand.localizationTableName != NULL) && (localizationBundle != NULL) && (message != NULL) )
        {
            message.Adopt( ::CFCopyLocalizedStringFromTableInBundle( message, currCommand.localizationTableName, localizationBundle, "") );
        }

        StSwitchToFront switcher;
        contextData.chooseFolderPaths.Adopt(CreateCFURLsFromOpenDialog( commandName, message, defaultName, defaultLocationStr, identifier, prompt, additionalFlags | kOMCFilePanelCanChooseDirectories));
        if(contextData.chooseFolderPaths == NULL || CFArrayGetCount(contextData.chooseFolderPaths) == 0)
        {
            throw OSStatus(userCanceledErr);
        }

        if(contextData.isNullContext)
        { // if command is executed without context, the chosen objects become the file/folder context
            contextData.objectList.resize(0);
            UInt32 theFlags = kListClear;
            size_t validObjectCount = CMUtils::ProcessObjectList(contextData.chooseFolderPaths.Get(), theFlags, CFURLCheckFileOrFolder, &contextData.objectList);
            if(validObjectCount > 0)
            {
                contextData.isNullContext = false;
            }
        }

        if( (additionalFlags & kOMCFilePanelUseCachedPath) != 0 )
        {
            commandRuntimeData.cachedChooseFolderPaths = contextData.chooseFolderPaths;
        }
    }
    else
    {
        contextData.chooseFolderPaths = commandRuntimeData.cachedChooseFolderPaths;
    }
}

void
PresentChooseObjectDialog(OnMyCommandCM *inPlugin,
                          CommandRuntimeData &commandRuntimeData,
                          CFStringRef commandName,
                          CFBundleRef localizationBundle)
{
    CommandDescription &currCommand = inPlugin->GetCurrentCommand();
    OMCContextData &contextData = commandRuntimeData.GetContextData();

    CFObj<CFStringRef> message;
    CFObj<CFArrayRef> defaultFileName;
    CFObj<CFArrayRef> defaultDirPath;
    CFObj<CFStringRef> identifier;
    CFObj<CFStringRef> prompt;
    UInt32 additionalFlags = GetNavDialogParams(currCommand.chooseObjectParams, message.GetReference(), defaultFileName.GetReference(), defaultDirPath.GetReference(), identifier.GetReference(), prompt.GetReference());
    if(identifier == nullptr)
        identifier.Adopt(currCommand.commandID, kCFObjRetain);
    
    if( ((additionalFlags & kOMCFilePanelUseCachedPath) == 0) || (commandRuntimeData.cachedChooseObjectPaths == nullptr) )
    {
        TRACE_CSTR("OnMyCommandCM About to display choose object dialog\n" );
        CFObj<CFMutableStringRef> defaultName( inPlugin->CreateCombinedStringWithObjects(defaultFileName,
                                                                               commandRuntimeData,
                                                                               currCommand.localizationTableName,
                                                                               localizationBundle) );
        
        CFObj<CFStringRef> expandedDirStr;
        CFObj<CFMutableStringRef> defaultLocationStr( inPlugin->CreateCombinedStringWithObjects(defaultDirPath,
                                                                                      commandRuntimeData,
                                                                                      nullptr,
                                                                                      nullptr) );
        if(defaultLocationStr != NULL)
        {
            expandedDirStr.Adopt( CreatePathByExpandingTilde( defaultLocationStr ) );
        }
        
        if( (currCommand.localizationTableName != NULL) && (localizationBundle != NULL) && (message != NULL) )
            message.Adopt( ::CFCopyLocalizedStringFromTableInBundle( message, currCommand.localizationTableName, localizationBundle, "") );

        StSwitchToFront switcher;
        contextData.chooseObjectPaths.Adopt(CreateCFURLsFromOpenDialog( commandName, message, defaultName, defaultLocationStr, identifier, prompt, additionalFlags | kOMCFilePanelCanChooseFiles | kOMCFilePanelCanChooseDirectories));
        if(contextData.chooseObjectPaths == NULL || CFArrayGetCount(contextData.chooseObjectPaths) == 0)
        {
            throw OSStatus(userCanceledErr);
        }
        
        if(contextData.isNullContext)
        { // if command is executed without context, the chosen objects become the file/folder context
            contextData.objectList.resize(0);
            UInt32 theFlags = kListClear;
            size_t validObjectCount = CMUtils::ProcessObjectList(contextData.chooseObjectPaths.Get(), theFlags, CFURLCheckFileOrFolder, &contextData.objectList);
            if(validObjectCount > 0)
            {
                contextData.isNullContext = false;
            }
        }
        
        if((additionalFlags & kOMCFilePanelUseCachedPath) != 0)
        {
            commandRuntimeData.cachedChooseObjectPaths = contextData.chooseObjectPaths;
        }
    }
    else
    {
        contextData.chooseObjectPaths = commandRuntimeData.cachedChooseObjectPaths;
    }
}

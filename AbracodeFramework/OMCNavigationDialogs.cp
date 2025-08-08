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
GetNavDialogParams(CFDictionaryRef inParams, CFStringRef &outMessage, CFArrayRef &outDefaultName, CFArrayRef &outDefaultLocation)
{
    ACFDict params(inParams);
    params.CopyValue( CFSTR("MESSAGE"), outMessage );
    params.CopyValue( CFSTR("DEFAULT_FILE_NAME"), outDefaultName );
    params.CopyValue( CFSTR("DEFAULT_LOCATION"), outDefaultLocation );
    
    UInt32 outAdditionalNavServiesFlags = 0;
    Boolean boolValue;
    if( params.GetValue(CFSTR("SHOW_INVISIBLE_ITEMS"), boolValue) && boolValue )
        outAdditionalNavServiesFlags |= kOMCFilePanelAllowInvisibleItems;

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
    UInt32 additionalFlags = GetNavDialogParams(currCommand.saveAsParams, message.GetReference(), defaultFileName.GetReference(), defaultDirPath.GetReference());
    
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
        contextData.saveAsPath.Adopt(CreateCFURLFromSaveAsDialog( commandName, message, defaultName, expandedDirStr, additionalFlags));
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
    UInt32 additionalFlags = GetNavDialogParams(currCommand.chooseFileParams, message.GetReference(), defaultFileName.GetReference(), defaultDirPath.GetReference());

    if( ((additionalFlags & kOMCFilePanelUseCachedPath) == 0) || (commandRuntimeData.cachedChooseFilePath == nullptr) )
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
        contextData.chooseFilePath = CreateCFURLFromOpenDialog(commandName, message, defaultName, defaultLocationStr, additionalFlags | kOMCFilePanelCanChooseFiles);
        if(contextData.chooseFilePath == NULL)
        {
            throw OSStatus(userCanceledErr);
        }
        
        if(contextData.isNullContext)
        { // if command is executed without context, the chosen object becomes the file/folder context
            const void* urls[] = { contextData.chooseFilePath.Get() };
            CFObj<CFArrayRef> urlContextArray(CFArrayCreate(kCFAllocatorDefault, urls, sizeof(urls)/sizeof(const void*), &kCFTypeArrayCallBacks));

            contextData.objectList.resize(1);
            UInt32 theFlags = kListClear;
            size_t validObjectCount = CMUtils::ProcessObjectList(urlContextArray.Get(), theFlags, CFURLCheckFileOrFolder, &contextData.objectList);
            if(validObjectCount == 0)
            {
                contextData.objectList.resize(0);
            }
            else
            {
                contextData.isNullContext = false;
            }
        }

        if( (additionalFlags & kOMCFilePanelUseCachedPath) != 0 )
        {
            commandRuntimeData.cachedChooseFilePath = contextData.chooseFilePath;
        }
    }
    else
    {
        contextData.chooseFilePath = commandRuntimeData.cachedChooseFilePath;
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
    UInt32 additionalFlags = GetNavDialogParams(currCommand.chooseFolderParams, message.GetReference(), defaultFileName.GetReference(), defaultDirPath.GetReference());
    
    if( ((additionalFlags & kOMCFilePanelUseCachedPath) == 0) || (commandRuntimeData.cachedChooseFolderPath == nullptr) )
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
        contextData.chooseFolderPath = CreateCFURLFromOpenDialog( commandName, message, defaultName, defaultLocationStr, additionalFlags | kOMCFilePanelCanChooseDirectories);
        if(contextData.chooseFolderPath == NULL)
        {
            throw OSStatus(userCanceledErr);
        }

        if(contextData.isNullContext)
        { // if command is executed without context, the chosen object becomes the file/folder context
            const void* urls[] = { contextData.chooseFolderPath.Get() };
            CFObj<CFArrayRef> urlContextArray(CFArrayCreate(kCFAllocatorDefault, urls, sizeof(urls)/sizeof(const void*), &kCFTypeArrayCallBacks));

            contextData.objectList.resize(1);
            UInt32 theFlags = kListClear;
            size_t validObjectCount = CMUtils::ProcessObjectList(urlContextArray.Get(), theFlags, CFURLCheckFileOrFolder, &contextData.objectList);
            if(validObjectCount == 0)
            {
                contextData.objectList.resize(0);
            }
            else
            {
                contextData.isNullContext = false;
            }
        }

        if( (additionalFlags & kOMCFilePanelUseCachedPath) != 0 )
        {
            commandRuntimeData.cachedChooseFolderPath = contextData.chooseFolderPath;
        }
    }
    else
    {
        contextData.chooseFolderPath = commandRuntimeData.cachedChooseFolderPath;
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
    UInt32 additionalFlags = GetNavDialogParams(currCommand.chooseObjectParams, message.GetReference(), defaultFileName.GetReference(), defaultDirPath.GetReference());
    
    if( ((additionalFlags & kOMCFilePanelUseCachedPath) == 0) || (commandRuntimeData.cachedChooseObjectPath == nullptr) )
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
        contextData.chooseObjectPath = CreateCFURLFromOpenDialog( commandName, message, defaultName, defaultLocationStr, additionalFlags | kOMCFilePanelCanChooseFiles | kOMCFilePanelCanChooseDirectories);
        if(contextData.chooseObjectPath == NULL)
        {
            throw OSStatus(userCanceledErr);
        }
        
        if(contextData.isNullContext)
        { // if command is executed without context, the chosen object becomes the file/folder context
            const void* urls[] = { contextData.chooseObjectPath.Get() };
            CFObj<CFArrayRef> urlContextArray(CFArrayCreate(kCFAllocatorDefault, urls, sizeof(urls)/sizeof(const void*), &kCFTypeArrayCallBacks));

            contextData.objectList.resize(1);
            UInt32 theFlags = kListClear;
            size_t validObjectCount = CMUtils::ProcessObjectList(urlContextArray.Get(), theFlags, CFURLCheckFileOrFolder, &contextData.objectList);
            if(validObjectCount == 0)
            {
                contextData.objectList.resize(0);
            }
            else
            {
                contextData.isNullContext = false;
            }
        }
        
        if((additionalFlags & kOMCFilePanelUseCachedPath) != 0)
        {
            commandRuntimeData.cachedChooseObjectPath = contextData.chooseObjectPath;
        }
    }
    else
    {
        contextData.chooseObjectPath = commandRuntimeData.cachedChooseObjectPath;
    }
}

#pragma once

#include "CFObj.h"
#include "ARefCounted.h"
#include "OMCContextData.h"

class CommandRuntimeData : public ARefCounted
{
public:
    
    CommandRuntimeData()
        : commandUUID(CommandRuntimeData::GenerateUUID())
    {
    }

    // single object constructor
    // it reduces context data to a list with a single OneObjProperties element if original context has more than one element
    // New commandUUID is generated but dialogUUID, if any, is preserved
    CommandRuntimeData(const CommandRuntimeData &commandRuntimeData, CFIndex inObjectIndex)
        : contextData(commandRuntimeData.contextData), objectIndex(inObjectIndex),
          cachedSaveAsPath(commandRuntimeData.cachedSaveAsPath), cachedChooseFilePath(commandRuntimeData.cachedChooseFilePath),
          cachedChooseFolderPath(commandRuntimeData.cachedChooseFolderPath), cachedChooseObjectPath(commandRuntimeData.cachedChooseObjectPath),
          commandUUID(CommandRuntimeData::GenerateUUID()), dialogUUID(commandRuntimeData.dialogUUID)
    {
        auto element_count = contextData.objectList.size();
        if((objectIndex < 0) || (objectIndex >= element_count))
        { // invalid index: remove all items from the list
            contextData.objectList.resize(0);
            objectIndex = -1;
        }
        else if(element_count > 1)
        {
            OneObjProperties oneObj = contextData.objectList[objectIndex];
            contextData.objectList.resize(0); //this removes all items from the list
            contextData.objectList.push_back(oneObj);
            contextData.currObjectIndex = 0;
            objectIndex = 0;
        }
        else
        {
            assert(objectIndex == 0); // sanity check for single item
        }
    }
    
    virtual ~CommandRuntimeData() noexcept
    {
        
    }
    
    OMCContextData &
    GetContextData()
    {
        return contextData;
    }

    OneObjProperties *
    GetAssociatedObject()
    {
        if((objectIndex >= 0) && (objectIndex < contextData.objectList.size()))
        {
            return &(contextData.objectList[objectIndex]);
        }
        return nullptr;
    }
    
    std::vector<OneObjProperties> &
    GetObjectList()
    {
        return contextData.objectList;
    }
    
    CFStringRef
    GetContextText() const
    {
        return contextData.contextText;
    }
    
    CFStringRef
    GetClipboardText() const
    {
        return contextData.clipboardText;
    }

    void
    SetAssociatedDialogUUID(CFStringRef inDialogUUID)
    {
        dialogUUID.Adopt(inDialogUUID, kCFObjRetain);
    }
    
    CFStringRef
    GetAssociatedDialogUUID() const
    {
        return dialogUUID;
    }
    
    void
    SetCommandUUID(CFStringRef inCommandUUID)
    {
        commandUUID.Adopt(inCommandUUID, kCFObjRetain);
    }
    
    CFStringRef
    GetCommandUUID() const
    {
        return commandUUID;
    }

    static CFObj<CFStringRef>
    GenerateUUID()
    {
        CFObj<CFUUIDRef> cfUUID(CFUUIDCreate(kCFAllocatorDefault));
        CFObj<CFStringRef> newUUID(CFUUIDCreateString(kCFAllocatorDefault, cfUUID));
        return newUUID;
    }
    
private:
    OMCContextData     contextData;
    CFIndex            objectIndex {-1}; // negative if processing objects together or no objects
    CFObj<CFStringRef> commandUUID;
    CFObj<CFStringRef> dialogUUID;// dialog UUID used instead of dialog ptr to look up the instance

public:
    CFObj<CFStringRef> inputText;
    CFObj<CFStringRef> cachedCommonParentPath;

    // if caching is requested the following objects are meant to remain valid and passed from command to subcommand
    CFObj<CFURLRef>    cachedSaveAsPath;
    CFObj<CFURLRef>    cachedChooseFilePath;
    CFObj<CFURLRef>    cachedChooseFolderPath;
    CFObj<CFURLRef>    cachedChooseObjectPath;

};

#pragma once

#include "OneObjProperties.h"
#include "OMCConstants.h"

class CommandDescription;
struct AEDesc;

struct OMCSortSettings
{
    OMCSortSettings(UInt32 inSortMethod = kSortMethodNone, CFOptionFlags inCompareOptions = 0, bool inSortAscending = true)
        : sortMethod(inSortMethod),
        compareOptions(inCompareOptions),
        sortAscending(inSortAscending)
    {
    }

    UInt32        sortMethod;
    CFOptionFlags compareOptions;
    bool          sortAscending;
};

inline bool operator==( const OMCSortSettings &inS1, const OMCSortSettings &inS2 )
{
    return ((inS1.sortMethod == inS2.sortMethod) && (inS1.compareOptions == inS2.compareOptions) && (inS1.sortAscending == inS2.sortAscending));
}


class OMCContextData
{
public:
	OMCContextData() {}
    OMCContextData(const OMCContextData &otherContextData)
      : contextText(otherContextData.contextText),
        clipboardText(otherContextData.clipboardText),
        objectList(otherContextData.objectList),
        objectListSorting(otherContextData.objectListSorting),
        currObjectIndex(0),
        saveAsPath(otherContextData.saveAsPath),
        chooseFilePath(otherContextData.chooseFilePath),
        chooseFolderPath(otherContextData.chooseFolderPath),
        chooseObjectPath(otherContextData.chooseObjectPath),
        isNullContext(otherContextData.isNullContext),
        isTextContext(otherContextData.isTextContext),
        isTextInClipboard(otherContextData.isTextInClipboard),
        isOpenFolder(otherContextData.isOpenFolder),
        isCopyFromParent(otherContextData.isCopyFromParent)
    {
    }

	CFObj<CFStringRef>			contextText;
    CFObj<CFStringRef>          clipboardText; // may be the same as contextText, just retained
	std::vector<OneObjProperties> objectList;
    OMCSortSettings             objectListSorting; // keeps the current object sorting settings. updated after sorting changes
    CFIndex						currObjectIndex {0};
    CFObj<CFURLRef>             saveAsPath;
    CFObj<CFURLRef>             chooseFilePath;
    CFObj<CFURLRef>             chooseFolderPath;
    CFObj<CFURLRef>             chooseObjectPath;
    Boolean						isNullContext {false};
    Boolean						isTextContext {false};
    Boolean                     isTextInClipboard {false};
    Boolean                     isOpenFolder {false};
    Boolean                     isCopyFromParent {false};
};

OSStatus SortObjectListByName(OMCContextData &contextData,
                              CFOptionFlags compareOptions,
                              bool sortAscending);

void CreateTextContext(const CommandDescription &currCommand,
                       OMCContextData &contextData,
                       const AEDesc *inAEContext);

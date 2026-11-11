#include "OMCClipboard.h"
#include "OMCContextData.h"
#include "CommandDescription.h"
#include "OMC.h"

class FileNameAndIndex
{
public:
    //take ownership of the string
    FileNameAndIndex(CFStringRef inName, CFIndex inIndex)
        : name(inName, kCFObjDontRetain), index(inIndex)
    {
    }

    CFObj<CFStringRef> name;
    CFIndex            index;
};

CFComparisonResult
FileNameComparator( const void *val1, const void *val2, void *context)
{
    const FileNameAndIndex *file1 = (const FileNameAndIndex *) val1;
    const FileNameAndIndex *file2 = (const FileNameAndIndex *) val2;
    
    if( (val1 == NULL) || (val2 == NULL) || ((CFStringRef)file1->name == NULL) || ( (CFStringRef)file2->name == NULL) )
        return kCFCompareLessThan;//not equal, order not important

    CFOptionFlags compareOptions = 0;
    if(context != NULL)
        compareOptions = *(CFOptionFlags *)context;

    return ::CFStringCompare(file1->name, file2->name, compareOptions);
}


OSStatus
SortObjectListByName(OMCContextData &contextData,
                    CFOptionFlags compareOptions,
                    bool sortAscending)
{
    if( contextData.objectList.size() <= 1 )
    {
        return noErr; // no need to sort
    }

    OMCSortSettings newSort(kSortMethodByName, compareOptions, sortAscending);
    if( newSort == contextData.objectListSorting )
    {
        return noErr; // already sorted by the same criteria
    }
    
    CFObj<CFMutableArrayRef> sortArray( ::CFArrayCreateMutable(kCFAllocatorDefault, contextData.objectList.size(), NULL /*const CFArrayCallBacks *callBacks*/ ) );
    if(sortArray == NULL)
    {
        return -108; // memFullErr from Carbon
    }

    for (CFIndex i = 0; i < contextData.objectList.size(); i++)
    {
        CFStringRef objName = CreateObjName( &(contextData.objectList[i]), NULL);
        FileNameAndIndex *oneFileItem = new FileNameAndIndex(objName, i);//take ownership of filename
        ::CFArrayAppendValue(sortArray, oneFileItem);
    }

    CFRange theRange = { 0, static_cast<CFIndex>(contextData.objectList.size()) };
    ::CFArraySortValues(sortArray, theRange, FileNameComparator, &compareOptions);

    //now put the sorted values back into our list of OneObjProperties
    std::vector<OneObjProperties> newList( contextData.objectList.size() );
    
    for(CFIndex i = 0; i < contextData.objectList.size(); i++)
    {
        FileNameAndIndex *oneFileItem = (FileNameAndIndex *)::CFArrayGetValueAtIndex(sortArray,i);
        newList[sortAscending ? i : (contextData.objectList.size() -1 -i)] = contextData.objectList[oneFileItem->index]; // it used to be at oneFileItem->index, now it is at "i" index
        delete oneFileItem;
    }

    // delete the old list itself but not its content because it has been copied to new list and ownership of objects has been transfered
    contextData.objectList.swap(newList);
    
    contextData.objectListSorting = newSort;

    return noErr;
}

// The text with its line endings changed as a TEXT_REPLACE_OPTION says (kTextReplace* in OMCConstants.h)
static CFStringRef
CreateTextWithReplacedLineEndings(CFStringRef inText, long inReplaceOption)
{
	if(inText == NULL)
		return NULL;
	if( (inReplaceOption != kTextReplaceLFsWithCRs) && (inReplaceOption != kTextReplaceCRsWithLFs) )
		return (CFStringRef)CFRetain(inText);

	CFObj<CFMutableStringRef> outText( CFStringCreateMutableCopy(kCFAllocatorDefault, 0, inText) );
	if(outText == NULL)
		return NULL;
	CFStringRef from = (inReplaceOption == kTextReplaceLFsWithCRs) ? CFSTR("\n") : CFSTR("\r");
	CFStringRef to = (inReplaceOption == kTextReplaceLFsWithCRs) ? CFSTR("\r") : CFSTR("\n");
	CFStringFindAndReplace(outText, from, to, CFRangeMake(0, CFStringGetLength(outText)), 0);
	return outText.Detach();
}

void
CreateTextContext(const CommandDescription &currCommand,
                  OMCContextData &contextData)
{
    if(contextData.contextText != NULL)
        return; // already created

    if( contextData.isTextContext && (currCommand.activationMode != kActiveClipboardText) )
    {
        if( (contextData.hostSelectedText != NULL) && (contextData.isNullContext == false) )
        {
            contextData.contextText.Adopt( CreateTextWithReplacedLineEndings(contextData.hostSelectedText, currCommand.textReplaceOptions), kCFObjDontRetain);
        }
    }
    else if(contextData.isTextInClipboard)
    {
        contextData.contextText.Adopt( OMCCopyClipboardText(currCommand.textReplaceOptions), kCFObjDontRetain );
        contextData.clipboardText.Adopt( contextData.contextText, kCFObjRetain );
    }
}


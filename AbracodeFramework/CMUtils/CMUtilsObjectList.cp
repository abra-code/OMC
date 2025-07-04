//**************************************************************************************
// Filename:	CMUtilsObjectList.cp
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
//
// Copyright � 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	static utilities for Contextual Menu Plugins
//
//
//**************************************************************************************

#include "CMUtils.h"
#include "StAEDesc.h"
#include "CFObj.h"
#include "ACFType.h"


// ---------------------------------------------------------------------------
// ProcessObjectList
// ---------------------------------------------------------------------------
/*
	generic file list processing loop
	returns true if at least one item was processed sucessfully

	caller must supply non-nil processing procedure of the prototype:
    OSStatus (*CFURLHandlerProc)( CFURLRef inURLRef, void *ioData );

in flags pass:	
	kProcBreakOnFirst is a directive to break on first item processed successfully

on output you may receive flags:
	kListOutMultipleObjects when more than one object is present in list
	kListOutErrorsOccurred when processing procedure returned error for one or more items in the list

*/

size_t
CMUtils::ProcessObjectList( const AEDescList *fileList, UInt32 &ioFlags, CFURLHandlerProc inProcPtr, void *inProcData /*=NULL*/)
{
	ioFlags &= ~kListOutFlagsMask;
    size_t counter = 0; // the count of objects which passed the test
    
	if( (fileList == NULL) || (inProcPtr == NULL) )
		return counter;

	OSStatus err = noErr;
	long listItemsCount = 0;

	if( ::AECountItems(fileList, &listItemsCount) == noErr )
	{
		if(listItemsCount > 1)
			ioFlags |= kListOutMultipleObjects;

		for (int i = 1; i <= listItemsCount; i++)
		{
			// Get ith item in the object list
			StAEDesc file;
			AEKeyword theKeyword;
			err = ::AEGetNthDesc(fileList, i, typeWildCard, &theKeyword, file);
			if (err == noErr)
			{
                CFObj<CFURLRef> oneURL = CopyURL(file);
				if( oneURL != nullptr )
				{
					err = (*inProcPtr)(oneURL, counter, inProcData);
				
					if(err == noErr)
					{
                        counter++;
						if( (ioFlags & kProcBreakOnFirst) != 0)
							break;
					}
					else if(err == userCanceledErr)
					{
						break;
					}
					else
					{
						ioFlags |= kListOutErrorsOccurred;
					}
				}
			}
		}
	}
	
	return counter;
}

size_t
CMUtils::ProcessObjectList( CFArrayRef fileList, UInt32 &ioFlags, CFURLHandlerProc inProcPtr, void *inProcData /*=NULL*/)
{
	ioFlags &= ~kListOutFlagsMask;
    size_t counter = 0; // the count of objects which passed the test
    
	if((fileList == NULL) || (inProcPtr == NULL))
		return counter;

	OSStatus err = noErr;

	CFIndex listItemsCount = ::CFArrayGetCount( fileList );
	if(listItemsCount > 1)
		ioFlags |= kListOutMultipleObjects;

	for( CFIndex i = 0; i < listItemsCount; i++ )
	{
		// Get ith item in the object list
		CFTypeRef oneItem = ::CFArrayGetValueAtIndex(fileList, i);
		if(oneItem != NULL)
		{
			CFTypeID itemType = ::CFGetTypeID( oneItem );
			if( itemType == ACFType<CFURLRef>::GetTypeID() )
			{
				err = (*inProcPtr)((CFURLRef)oneItem, counter, inProcData);
			
				if(err == noErr)
				{
                    counter++;
					if( (ioFlags & kProcBreakOnFirst) != 0)
						break;
				}
				else if(err == userCanceledErr)
				{
					break;
				}
				else
				{
					ioFlags |= kListOutErrorsOccurred;
				}
			}
		}
	}
	
	return counter;
}


class FileNameAndAEDesc
{
public:
	//takes ownership of name and AEDesc
	FileNameAndAEDesc(CFObj<CFStringRef> &inName, StAEDesc &inFileDesc)
		: name(inName.Detach(), kCFObjDontRetain), fileDesc(inFileDesc.Detach())
	{
	}

	CFObj<CFStringRef>	name;
	StAEDesc			fileDesc;
};

//returns an array of FileNameAndAEDesc objects which must be deleted manually by looping the array
CFMutableArrayRef
CMUtils::CollectObjectNames( const AEDescList *fileList)
{
	if( fileList == NULL )
		return NULL;

	long listItemsCount = 0;
	OSStatus err = ::AECountItems(fileList, &listItemsCount);
	if( (listItemsCount == 0) || (err != noErr) )
		return NULL;

	CFMutableArrayRef outArray = ::CFArrayCreateMutable(kCFAllocatorDefault, listItemsCount, NULL /*const CFArrayCallBacks *callBacks*/ );
	if(outArray == NULL)
		return NULL;

	for (int i = 1; i <= listItemsCount; i++)
	{
		// Get ith item in the object list
		StAEDesc fileDesc;
		AEKeyword theKeyword;
		err = ::AEGetNthDesc(fileList, i, typeWildCard, &theKeyword, &fileDesc);
		if (err == noErr)
		{
            CFObj<CFURLRef> fileURL = CopyURL(fileDesc);
			if(fileURL != nullptr)
			{
                CFObj<CFStringRef> fileName = ::CFURLCopyLastPathComponent(fileURL);
                FileNameAndAEDesc *oneFileItem = new FileNameAndAEDesc(fileName, fileDesc);//take ownership of filename and fileDesc
                ::CFArrayAppendValue(outArray, oneFileItem);
			}
		}
	}
	
	return outArray;
}


CFComparisonResult
FileNameCompareCallback( const void *val1, const void *val2, void *context)
{
	const FileNameAndAEDesc *file1 = (const FileNameAndAEDesc *) val1;
	const FileNameAndAEDesc *file2 = (const FileNameAndAEDesc *) val2;
	
	if( (val1 == NULL) || (val2 == NULL) || ((CFStringRef)file1->name == NULL) || ( (CFStringRef)file2->name == NULL) )
		return kCFCompareLessThan;//not equal, order not important

	CFOptionFlags compareOptions = 0;
	if(context != NULL)
		compareOptions = *(CFOptionFlags *)context;

	return ::CFStringCompare(file1->name, file2->name, compareOptions);
}

//AEDescList sortedList = {typeNull, NULL};
//caller responsible for releasing the result outSortedList with AEDisposeDesc()
OSStatus
CMUtils::AESortFileList(const AEDescList *inFileList, AEDescList *outSortedList, CFOptionFlags compareOptions)
{	
	long listItemsCount = 0;
	OSStatus err = ::AECountItems(inFileList, &listItemsCount);
	if( (listItemsCount == 0) || (err != noErr) )
		return err;

	if(listItemsCount == 1)
	{//no need to sort one item. return duplicate
		::AEDuplicateDesc( inFileList, outSortedList );
		return noErr;
	}
	
	CFObj<CFMutableArrayRef> objectsArray( CollectObjectNames( inFileList ) );//smart ptr will delete the array but indivdual items must be released in a loop before that
	if(objectsArray == NULL)
		return -1;
	
	CFIndex objectCount = ::CFArrayGetCount(objectsArray);
	if(objectCount > 0)
	{
		err = ::AECreateList( NULL, 0, false, outSortedList );
		if(err == noErr)
		{
			CFRange theRange = { 0, objectCount };
			::CFArraySortValues(objectsArray, theRange, FileNameCompareCallback, &compareOptions);
		
			for(CFIndex i = 0; i < objectCount; i++)
			{
				FileNameAndAEDesc *oneFileItem = (FileNameAndAEDesc *)::CFArrayGetValueAtIndex(objectsArray,i);
				::AEPutDesc(outSortedList, 0, &(oneFileItem->fileDesc));
				delete oneFileItem;
			}
			
		}
	}
	
	return err;


}

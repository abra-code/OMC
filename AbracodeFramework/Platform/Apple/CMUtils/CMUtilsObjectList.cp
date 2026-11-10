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

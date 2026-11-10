//
//  OMCObjectList.cpp
//  Abracode
//
//  Walking a list of file URLs with a handler per URL (OMCObjectList.h). Moved from
//  CMUtils::ProcessObjectList's CFArray form, unchanged.
//

#include "OMCObjectList.h"
#include "ACFType.h"
#include "OMCPlatformTypes.h" // noErr

static const OSStatus kUserCanceled = -128; // userCanceledErr, which the handlers return to stop the walk

size_t
OMCProcessObjectList(CFArrayRef fileList, UInt32 &ioFlags, CFURLHandlerProc inProcPtr, void *inProcData /*= nullptr*/)
{
	ioFlags &= ~kListOutFlagsMask;
	size_t counter = 0; // the count of objects which passed the test

	if((fileList == nullptr) || (inProcPtr == nullptr))
		return counter;

	OSStatus err = noErr;

	CFIndex listItemsCount = ::CFArrayGetCount( fileList );
	if(listItemsCount > 1)
		ioFlags |= kListOutMultipleObjects;

	for( CFIndex i = 0; i < listItemsCount; i++ )
	{
		// Get ith item in the object list
		CFTypeRef oneItem = ::CFArrayGetValueAtIndex(fileList, i);
		if(oneItem != nullptr)
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
				else if(err == kUserCanceled)
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

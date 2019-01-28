/*
 *  OMCObserver.cpp
 *  Abracode
 *
 *  Created by Tomasz Kukielka on 1/3/08.
 *  Copyright 2008 Abracode. All rights reserved.
 *
 */

#include "OMCObserver.h"
#include "OmcTaskNotification.h"
#include <CFObj.h>
#include "OnMyCommandCM.h"

void
OMCObserver::ReceiveNotification(void *ioData)
{
	if( (ioData == NULL) || (mCallback == NULL) )
		return;

	OmcObserverMessage message = kOmcObserverMessageNone;
	CFObj<CFTypeRef> resultText;

	OmcTaskData *taskData = (OmcTaskData *)ioData;

	switch(taskData->messageID)
	{
		case kOmcTaskFinished:
		{
			if( (mMessageTypes & kOmcObserverTaskFinished) != 0)
				message = kOmcObserverTaskFinished;
		}
		break;
		
		case kOmcAllTasksFinished:
		{
			if( (mMessageTypes & kOmcObserverAllTasksFinished) != 0)
				message = kOmcObserverAllTasksFinished;
		}
		break;

		case kOmcTaskProgress:
		{
			if( (mMessageTypes & kOmcObserverTaskProgress) != 0)
			{
				message = kOmcObserverTaskProgress;
		
				switch(taskData->dataType)
				{
					case kOmcDataTypePointer:
					{
						if(taskData->data.ptr != NULL) //do not clear last status if we don't have anything explicilty new
							resultText.Adopt( ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)taskData->data.ptr, taskData->dataSize, kCFStringEncodingUTF8, true), kCFObjDontRetain );
					}
					break;

					case kOmcDataTypeCFData:
					{
						if(taskData->data.cfObj != NULL) //do not clear last status if we don't have anything explicilty new
						{
							const UInt8 *rawData = ::CFDataGetBytePtr( (CFDataRef)taskData->data.cfObj );
							CFIndex theLen = ::CFDataGetLength( (CFDataRef)taskData->data.cfObj );
							resultText.Adopt( ::CFStringCreateWithBytes(kCFAllocatorDefault, rawData, theLen, kCFStringEncodingUTF8, true), kCFObjDontRetain );
						}
					}
					break;

					case kOmcDataTypeCFString:
					{
						if(taskData->data.cfObj != NULL) //do not clear last status if we don't have anything explicilty new
						{
							resultText.Adopt( (CFStringRef)taskData->data.cfObj, kCFObjRetain );						
						}
					}
					break;
					
					default:
					break;
				}
			}
		}
		break;

		case kOmcTaskCancel:
		{
			if( (mMessageTypes & kOmcObserverAllTasksFinished) != 0)
				message = kOmcObserverTaskCanceled;
		}
		break;
		
		default:
		{
			message = kOmcObserverMessageNone;
		}
	}

	if( message != kOmcObserverMessageNone )
	{
		(*mCallback)( message, taskData->taskID, resultText, mUserData );
	}
}



extern "C" OMCObserverRef OMCCreateObserver( UInt32 messageTypes, OMCObserverCallback inCallback, void *userData )
{
	OMCObserverRef observerRef = NULL;
	try
	{
		observerRef = new OMCObserver(messageTypes, inCallback, userData);
	}
	catch(...)
	{
	
	}
	return observerRef;
}

extern "C" void OMCReleaseObserver( OMCObserverRef inObserver )
{
	try
	{
		if(inObserver != NULL)
			inObserver->Release();
	}
	catch(...)
	{
	}
}

extern "C" void OMCRetainObserver( OMCObserverRef inObserver )
{
	try
	{
		if(inObserver != NULL)
			inObserver->Retain();
	}
	catch(...)
	{
	}
}

extern "C" void OMCAddObserver( OMCExecutorRef inOMCExecutor, OMCObserverRef inObserverOwner )
{
	try
	{
		if( (inOMCExecutor != NULL) && (inObserverOwner != NULL) )
			inOMCExecutor->AddObserver( inObserverOwner->GetObserver() );
	}
	catch(...)
	{
	
	}
}

extern "C" void OMCUnregisterObserver( OMCObserverRef inObserverOwner )
{
	try
	{
		if( inObserverOwner != NULL )
		{
			inObserverOwner->Unregister();
		}
	}
	catch(...)
	{
	
	}
}



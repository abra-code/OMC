//**************************************************************************************
// Filename:	ANotifier.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
//
// Copyright � 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	ANotifier may have many observers
//	
//
//
//**************************************************************************************

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include "AObserverBase.h"
#include "DebugSettings.h"
#include "ARefCounted.h"

class ANotifier : public ARefCounted
{
public:

	ANotifier()
		: mObservers(NULL), mIterationArray(NULL), mIterationArrayElementCount(0)
	{
	}

	~ANotifier()
	{
		if(mObservers != NULL)
		{
			CallAllObservers(TellObserverThisNotiferDies, this);
			::CFRelease(mObservers);
			mObservers = NULL;
		}
	}

	//add observers to notifiers, not the other way around
	void AddObserver(const AObserverBase *inObserver)
	{
		if(inObserver == NULL)
			return;

		//PREVIOUSLY THERE WAS A CIRCULAR RETAIN LEAK HERE
		//Now the design here is that the observer keeps a strong reference to notifiers
		//but the notifier keeps a weak reference to all observers
		//Before observer dies it calls RemoveObserver() on all its notifiers

		if(mObservers == NULL)
			mObservers = ::CFSetCreateMutable( kCFAllocatorDefault, 0, NULL/*ARefCounted::GetCFSetCallbacks()*/ );

		//if we are currently iterating, the new element added will not be processed
		//unlikely sitaution but we should log it
		if(mIterationArray != NULL)
		{
			LOG_CSTR("OMC->ANotifier::AddObserver: Warning: adding itme to the set while iterating!\n");
		}

		::CFSetAddValue( mObservers, (const void *)inObserver );
		
		inObserver->AddNotifier(this);	// this is preferable and more natural
										// interconnection is made by just adding the new observer
										// but not the other way around (not by adding notifier to observer)
	}

	//safe to remove items during iteration
	void RemoveObserver(const AObserverBase *inObserver) const
	{
		if(inObserver == NULL)
			return;

		if(mIterationArray != NULL)
		{
			//intersting case, item is removed during iteration
			//we are safe here but we need to set it to NULL in iteration array
			//in case it has not been processed yet
			for(CFIndex i = 0; i < mIterationArrayElementCount; i++)
			{
				if(mIterationArray[i] == (void *)inObserver)
				{
					mIterationArray[i] = NULL;
					break;
				}
			}
		}

		if(mObservers != NULL)
			::CFSetRemoveValue( mObservers, (const void *)inObserver );
	}

	//concrete observers and notifiers agree on what the ioData is
	void NotifyObservers(void *ioData)
	{
		if(mObservers != NULL)
		{
			Retain();//prevent anyone from deleting us during this operation
			CallAllObservers(NotifyOneObserver, ioData);
			Release();
		}
	}

	static void NotifyOneObserver( const void *inOneValue,  void *ioData)
	{
		try
		{
			const AObserverBase *oneObserver = (const AObserverBase *)inOneValue;
			if(oneObserver != NULL)
				oneObserver->ReceiveNotification(ioData);
		}
		catch(...)
		{
			LOG_CSTR( "OMC->ANotifier::NotifyOneObserver. Unknown error ocurred\n" );
		}
	}

	static void TellObserverThisNotiferDies( const void *inOneValue,  void *ioData)
	{
		try
		{
			ANotifier *thisNotifier = (ANotifier *)ioData;
			const AObserverBase *oneObserver = (const AObserverBase *)inOneValue;
			if(oneObserver != NULL)
				oneObserver->RemoveNotifier(thisNotifier);
		}
		catch(...)
		{
			LOG_CSTR( "OMC->ANotifier::TellObserverThisNotiferDies. Unknown error ocurred\n" );
		}		
	}

protected:

	//helper function to safely iterate the set even if the applied function modifies the set itself (adds/removes items)
	void CallAllObservers(CFSetApplierFunction inFunc, void *ioData)
	{
		if(mIterationArray != NULL)
		{
			LOG_CSTR("OMC->ANotifier::CallAllObservers: mIterationArray != NULL. Nested iterations not allowed!\n");
			return;
		}

		mIterationArrayElementCount = ::CFSetGetCount(mObservers);
		if(mIterationArrayElementCount == 0)
			return;
		mIterationArray = (const void **)calloc(mIterationArrayElementCount, sizeof(void *));
		::CFSetGetValues(mObservers, mIterationArray);
		for(CFIndex i = 0; i < mIterationArrayElementCount; i++)
		{
			const void *oneObserver = mIterationArray[i];
			//elements not allowed to be NULL in CFSet
			//but it might have changed during the iteration and removal of items
			if(oneObserver != NULL)
			{
				inFunc(oneObserver, ioData);
			}
		}
		free(mIterationArray);
		mIterationArray = NULL;
		mIterationArrayElementCount = 0;
	}

private:
	mutable CFMutableSetRef mObservers;
	mutable const void **mIterationArray;
	mutable CFIndex mIterationArrayElementCount;
};

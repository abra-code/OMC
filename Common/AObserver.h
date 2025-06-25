//**************************************************************************************
// Filename:	AObserver.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
//
// Copyright � 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	AObserver can listen to several notifiers but they better agree on one protocol
//	
//
//
//**************************************************************************************

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include "AObserverBase.h"
#include "ANotifier.h"

template <typename T> class AObserver : public AObserverBase
{
public:
	AObserver(T *inOwner)
		: mOwner(inOwner), mNotifiers(NULL), mIterationArray(NULL), mIterationArrayElementCount(0)
	{
	}

	~AObserver()
	{
		DetachFromAllNotifiers();
	}

	void SetOwner(T *inOwner)
	{
		mOwner = inOwner;
	}

	//generic API. sender and receiver agree on details of message data exchanged
	virtual void ReceiveNotification(void *ioData) const
	{
		if(mOwner != NULL)
			mOwner->ReceiveNotification(ioData);
	}

	void DetachFromAllNotifiers()
	{
		if(mNotifiers != NULL)
		{
			CallAllNotifiers(TellNotifierToRemoveObserver, this);
			::CFRelease(mNotifiers);
			mNotifiers = NULL;
		}
	}


	static void TellNotifierToRemoveObserver( const void *inOneValue,  void *ioData)
	{
		try
		{
			AObserver *thisObserver = (AObserver *)ioData;
			const ANotifier *oneNotifier = (const ANotifier *)inOneValue;
			if(oneNotifier != NULL)
				oneNotifier->RemoveObserver(thisObserver);
		}
		catch(...)
		{
			LOG_CSTR( "OMC->AObserver::TellNotifierThisObserverDies. Unknown error ocurred\n" );
		}		
	}

protected:
	
	//helper function to safely iterate the set even if the applied function modifies the set itself (adds/removes items)
	void CallAllNotifiers(CFSetApplierFunction inFunc, void *ioData)
	{
		if(mIterationArray != NULL)
		{
			LOG_CSTR("OMC->ANotifier::CallAllObservers: mIterationArray != NULL. Nested iterations not allowed!\n");
			return;
		}

		mIterationArrayElementCount = ::CFSetGetCount(mNotifiers);
		if(mIterationArrayElementCount == 0)
			return;

		mIterationArray = (const void **)calloc(mIterationArrayElementCount, sizeof(void *));
		::CFSetGetValues(mNotifiers, mIterationArray);
		for(CFIndex i = 0; i < mIterationArrayElementCount; i++)
		{
			const void *oneNotifier = mIterationArray[i];
			//elements not allowed to be NULL in CFSet
			//but it might have changed during the iteration and removal of items
			if(oneNotifier != NULL)
			{
				inFunc(oneNotifier, ioData);
			}
		}
		free(mIterationArray);
		mIterationArray = NULL;
		mIterationArrayElementCount = 0;
	}

	//no need to make this public
	//caller should add observer to notifier, not the other way around
	virtual void AddNotifier(const ANotifier *inNotifier) const
	{
		//if we are currently iterating, the new element added will not be processed
		//unlikely sitaution but we should log it
		if(mIterationArray != NULL)
		{
			LOG_CSTR("OMC->AObserver::AddNotifier: Warning: adding itme to the set while iterating!\n");
		}

		//Observers keep strong reference to all notifiers
		if(mNotifiers == NULL)
			mNotifiers = ::CFSetCreateMutable( kCFAllocatorDefault, 0, ARefCounted::GetCFSetCallbacks() );
		
		::CFSetAddValue( mNotifiers, (const void *)inNotifier );
	}
	
	virtual void RemoveNotifier(const ANotifier *inNotifier) const
	{
		if(mIterationArray != NULL)
		{
			//intersting case, item is removed during iteration
			//we are safe here but we need to set it to NULL in iteration array
			//in case it has not been processed yet
			for(CFIndex i = 0; i < mIterationArrayElementCount; i++)
			{
				if(mIterationArray[i] == (void *)inNotifier)
				{
					mIterationArray[i] = NULL;
					break;
				}
			}
		}

		if(mNotifiers != NULL)
			::CFSetRemoveValue( mNotifiers, (const void *)inNotifier );
	}

private:
	mutable T *mOwner;//owner owns us and is almost always valid. in some cases we may outlive host for a while though
	mutable CFMutableSetRef mNotifiers;//we need to keep a list of notifiers so we can tell them when we die
	mutable const void **mIterationArray;
	mutable CFIndex mIterationArrayElementCount;
};

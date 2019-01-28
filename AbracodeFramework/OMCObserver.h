/*
 *  OMCObserver.h
 *  Abracode
 *
 *  Created by Tomasz Kukielka on 1/3/08.
 *  Copyright 2008 Abracode. All rights reserved.
 *
 */
#include "AObserver.h"
#include "OMC.h"

class OMCObserver : public ARefCounted
{
public:

	OMCObserver(UInt32 messageTypes, OMCObserverCallback inCallback, void *userData)
		: mMessageTypes( messageTypes ),
		mTaskObserver( new AObserver<OMCObserver>(this) ),
		mCallback( inCallback ),
		mUserData( userData )
	 {
	 }

	virtual ~OMCObserver(void)
	{
		if(mTaskObserver!= NULL)
			mTaskObserver->SetOwner(NULL);//observer may outlive us so it is very important to tell that we died
	}

	void ReceiveNotification(void *ioData);

	AObserverBase *	GetObserver()
					{
						return (AObserver<OMCObserver> *)mTaskObserver;
					}

	void DetachFromAllNotifiers()
	{
		if(mTaskObserver!= NULL)
			mTaskObserver->DetachFromAllNotifiers();
	}
	
	void Unregister()
	{
		mMessageTypes = kOmcObserverMessageNone;
		mCallback = NULL;
		mUserData = NULL;
	}

private:
	UInt32										mMessageTypes;
	ARefCountedObj< AObserver<OMCObserver> >	mTaskObserver;
	OMCObserverCallback							mCallback;
	void *										mUserData;
};


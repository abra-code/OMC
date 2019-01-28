//**************************************************************************************
// Filename:	ARefCounted.h
//				Part of Abracode Workshop.
//				http://free.abracode.com/cmworkshop/
// Copyright � 2006 Abracode, Inc.  All rights reserved.
//
// Description:	ARefCounted and its smart pointer
//
//**************************************************************************************
// Revision History:
// Friday, Oct 16, 2005 - Original
//**************************************************************************************

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include "DebugSettings.h"

//inherit from ARefCounted and always alocate with operator new
//don't put on stack
//dispose of by using Release() method

class ARefCounted
{
public:
	ARefCounted()
		: mRefCount(1) //newly created objects starts with a ref count 1
	{
//		TRACE_CSTR1( "ARefCounted::ARefCounted" );
	}

	virtual ~ARefCounted()
	{
//		TRACE_CSTR1( "ARefCounted::~ARefCounted" );
	}

	int Retain() const
	{
//		TRACE_CSTR1( "ARefCounted::Retain" );
		return ++mRefCount;
	}

	int Release() const
	{
//		TRACE_CSTR1( "ARefCounted::Release" );
		int outRefCount = --mRefCount;
		if(mRefCount == 0)
		{
			delete this;
		}
		else if(mRefCount < 0 )
		{//overreleased, "this" most likely invalid
			LOG_CSTR("ARefCounted::Release: ref count < 0. Object overreleased, bad things will happen\n");
		}
		return outRefCount;
	}

	static const void * RetainCallback(CFAllocatorRef allocator, const void *inValue)
	{
		try
		{
			const ARefCounted *myObj = reinterpret_cast< const ARefCounted * >( inValue );
			if(myObj != NULL)
				myObj->Retain();
			return inValue;
		}
		catch(...)
		{
			LOG_CSTR("Unexpected exception caught in TRefCount::CFArrayRetainCallBack\n");
		}
		return NULL;
	}

	static void ReleaseCallback(CFAllocatorRef allocator, const void *inValue)
	{
		try
		{
			const ARefCounted *myObj = reinterpret_cast< const ARefCounted * >( inValue );
			if(myObj != NULL)
				myObj->Release();
		}
		catch(...)
		{
			LOG_CSTR("Unexpected exception caught in TRefCount::CFArrayReleaseCallBack\n");
		}
	}

	static const CFArrayCallBacks * GetCFArrayCallbacks() { return &sCFArrayCallbacks; }
	static const CFSetCallBacks * GetCFSetCallbacks() { return &sCFSetCallbacks; }
	static const CFDictionaryValueCallBacks * GetCFDictionaryValueCallbacks() { return &sCFDictionaryCallbacks; }

	static const CFArrayCallBacks sCFArrayCallbacks;
	static const CFSetCallBacks sCFSetCallbacks;
	static const CFDictionaryValueCallBacks sCFDictionaryCallbacks;

private:
	mutable int mRefCount;
};

typedef enum ARefCountRetainType
{
	kARefCountRetain,
	kARefCountDontRetain
} ARefCountRetainType;

template <typename T> class ARefCountedObj
{
public:
						ARefCountedObj()
							: mRef(NULL)
						{
						}

						ARefCountedObj(T* inRef, ARefCountRetainType inRetainType = kARefCountDontRetain)
							: mRef(inRef)
						{
							if( (mRef != NULL) && (inRetainType == kARefCountRetain) )
								mRef->Retain();
						}

	virtual				~ARefCountedObj()
						{
							ReleaseRef();
						}
						
	T*					Detach()
						{
							T* outRef = mRef;
							mRef = NULL;
							return outRef;
						}

	void				Adopt(T* inRef, ARefCountRetainType inRetainType = kARefCountDontRetain)
						{
							if(mRef == inRef)
								return;
							ReleaseRef();
							mRef = inRef;
							if( (mRef != NULL) && (inRetainType == kARefCountRetain) )
								mRef->Retain();
						}

//the following does not work with gcc because of gcc bug/unimplemented feature
	ARefCountedObj&		operator=(T* &inRef)
						{
							Adopt(inRef, kARefCountDontRetain);
							return *this;
						}

	T*					operator -> () const
						{
							if(mRef == NULL)
							{
								LOG_CSTR("ARefCountedObj: operator -> trying to access NULL pointer\n");
								throw OSStatus(-50);//paramErr
							}
							return mRef;
						}

						operator T* () const
						{
							return mRef;
						}
						
	T**					operator & ()
						{
							return &mRef;
						}

	T*					Get() const
						{
							return mRef;
						}

protected:

	void				ReleaseRef()
						{
							if(mRef != NULL)
							{
								mRef->Release();
								mRef = NULL;
							}
						}

	T*					mRef;

private:
						ARefCountedObj(const ARefCountedObj&);
	ARefCountedObj&				operator=(const ARefCountedObj&);
};

template< class T > bool operator==( ARefCountedObj<T>& inObj, int *inNULL )
{
   return ( (T*)inObj == (T*)inNULL );
}
template< class T > bool operator!=( ARefCountedObj<T>& inObj, int *inNULL )
{
   return ( (T*)inObj != (T*)inNULL );
}

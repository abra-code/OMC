//**************************************************************************************
//
// Filename:	ARefCounted.h
// Description:	ARefCounted and its smart pointer
//
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
	ARefCounted() noexcept
		: mRefCount(1) //newly created objects starts with a ref count 1
	{
//		TRACE_CSTR( "ARefCounted::ARefCounted\n" );
	}

	virtual ~ARefCounted() noexcept
	{
//		TRACE_CSTR( "ARefCounted::~ARefCounted\n" );
	}

	int Retain() noexcept
	{
//		TRACE_CSTR( "ARefCounted::Retain\n" );
		return ++mRefCount;
	}

	int Release() noexcept
	{
//		TRACE_CSTRs( "ARefCounted::Release" );
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
			ARefCounted *myObj = reinterpret_cast<ARefCounted *>( const_cast<void *>(inValue) );
			if(myObj != nullptr)
				myObj->Retain();
			return inValue;
		}
		catch(...)
		{
			LOG_CSTR("Unexpected exception caught in TRefCount::CFArrayRetainCallBack\n");
		}
		return nullptr;
	}

	static void ReleaseCallback(CFAllocatorRef allocator, const void *inValue)
	{
		try
		{
			ARefCounted *myObj = reinterpret_cast<ARefCounted *>( const_cast<void *>(inValue) );
			if(myObj != nullptr)
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
	int mRefCount;
};

typedef enum ARefCountRetainType
{
	kARefCountRetain,
	kARefCountDontRetain
} ARefCountRetainType;

template <typename T> class ARefCountedObj
{
public:
						ARefCountedObj() noexcept
							: mRef(nullptr)
						{
						}

						ARefCountedObj(T* inRef, ARefCountRetainType inRetainType = kARefCountDontRetain) noexcept
							: mRef(inRef)
						{
							if( (mRef != nullptr) && (inRetainType == kARefCountRetain) )
								mRef->Retain();
						}
						
						ARefCountedObj(const ARefCountedObj& inObj) noexcept
							: mRef(inObj.mRef)
						{
							if(mRef != nullptr)
								mRef->Retain();
						}

	virtual				~ARefCountedObj() noexcept
						{
							if(mRef != nullptr)
							{
								mRef->Release();
								mRef = nullptr;
							}
						}
						
	T*					Detach() noexcept
						{
							T* outRef = mRef;
							mRef = nullptr;
							return outRef;
						}

	void				Adopt(T* inRef, ARefCountRetainType inRetainType = kARefCountDontRetain) noexcept
						{
							if((inRef != nullptr) && (inRetainType == kARefCountRetain))
								inRef->Retain();
							
							if(mRef != nullptr)
								mRef->Release();

							mRef = inRef;
						}

	ARefCountedObj&		operator=(const ARefCountedObj& inObj) noexcept
						{
							if(inObj.mRef != nullptr)
								inObj.mRef->Retain();
							if(mRef != nullptr)
								mRef->Release();
							mRef = inObj.mRef;
							
							return *this;
						}

	T*					operator -> () const
						{
							if(mRef == nullptr)
							{
								LOG_CSTR("ARefCountedObj: operator -> trying to access NULL pointer\n");
								throw OSStatus(-50);//paramErr
							}
							return mRef;
						}

						operator T* () const noexcept
						{
							return mRef;
						}
						
	T**					operator & () noexcept
						{
							return &mRef;
						}

	T*					Get() const  noexcept
						{
							return mRef;
						}

private:
	T*					mRef;
};

template< class T > bool operator==( ARefCountedObj<T>& inObj, nullptr_t ) noexcept
{
   return ( (T*)inObj == nullptr );
}
template< class T > bool operator!=( ARefCountedObj<T>& inObj, nullptr_t ) noexcept
{
   return ( (T*)inObj != nullptr );
}

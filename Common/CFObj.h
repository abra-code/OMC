//**************************************************************************************
// Filename:	CFObj.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright � 2005 Abracode, Inc.  All rights reserved.
//
// Description:	Template-based CFObjectRef smart pointer.
//
//**************************************************************************************
// Revision History:
// Friday, Oct 16, 2005 - Original
//**************************************************************************************

#pragma once

#include <CoreFoundation/CoreFoundation.h>

typedef enum CFObjRetainType
{
	kCFObjRetain,
	kCFObjDontRetain
} CFObjRetainType;

template <typename T> class CFObj
{
public:
    CFObj() noexcept
        : mRef(nullptr)
    {
    }

    CFObj(T inRef, CFObjRetainType inRetainType = kCFObjDontRetain) noexcept
        : mRef(inRef)
    {
        if( (mRef != nullptr) && (inRetainType == kCFObjRetain) )
            CFRetain(mRef);
    }

    explicit CFObj(const CFObj& inRef) noexcept
        : mRef(inRef)
    {
        if(mRef != nullptr)
            CFRetain(mRef);
    }
    
    virtual ~CFObj() noexcept
    {
        Release();
    }
						
	T Detach() noexcept
    {
        T outRef = mRef;
        mRef = nullptr;
        return outRef;
    }
							
	void Release() noexcept
    {
        if(mRef != nullptr)
        {
            CFRelease(mRef);
            mRef = nullptr;
        }
    }
                        
    void Swap(CFObj &inOther) noexcept
    {
        T tempRef = mRef;
        mRef = inOther.mRef;
        inOther.mRef = tempRef;
    }
							
	void Adopt(T inRef, CFObjRetainType inRetainType = kCFObjDontRetain) noexcept
    {
        if( (inRef != nullptr) && (inRetainType == kCFObjRetain) )
            CFRetain(inRef);
        Release();
        mRef = inRef;
    }

	CFObj& operator=(T &inRef) noexcept
    {
        Adopt(inRef, kCFObjDontRetain);
        return *this;
    }

    CFObj& operator=(const CFObj& inRef) noexcept
    {
        Adopt(inRef, kCFObjRetain);
        return *this;
    }
    
    operator T() const noexcept
    {
        return mRef;
    }
						
	T* operator &() noexcept
    {
        return &mRef;
    }

	T Get() const noexcept
    {
        return mRef;
    }

	T& GetReference() noexcept
    {
        return mRef;
    }

protected:
	T mRef;
};


template<class T> bool operator==(CFObj<T>& inObj, nullptr_t)
{
   return ((T)inObj == (T)nullptr);
}
template<class T> bool operator!=(CFObj<T>& inObj, nullptr_t)
{
   return ((T)inObj != (T)nullptr);
}

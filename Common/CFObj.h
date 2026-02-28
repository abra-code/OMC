//**************************************************************************************
// Filename:	CFObj.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright © 2005 Abracode, Inc.  All rights reserved.
//
// Description:	Template-based CFObjectRef smart pointer.
//
// Ownership Model:
// - CFObj takes OWNERSHIP of CoreFoundation objects by default (does NOT retain)
// - Use kCFObjDontRetain when you have a newly created or copied Core Foundation object and you want this CFObj instance to release it
// - Use kCFObjRetain when the object is already owned elsewhere and you need a second ownership in this CFObj<> instance
//
// Examples:
//   CFObj<CFStringRef> str = CFStringCreateWithCString(kCFAllocatorDefault, CFSTR("foo"), kCFStringEncodingUTF8); // takes ownership, does NOT retain
//   CFObj<CFStringRef> str = CopyStringFunc();         // takes ownership, does NOT retain, will release in destructor
//   CFObj<CFStringRef> str(someString, kCFObjRetain);  // adopts and retains, will release in destructor
//   myCFObj.Adopt(someRetainedPtr, kCFObjRetain);      // same as above
//
// Warning: Assignment from raw pointer (operator=) transfers ownership without retaining.
//          Use Adopt() with kCFObjRetain if you need to retain an existing reference.

//**************************************************************************************
// Revision History:
// Friday, Oct 16, 2005 - Original
//**************************************************************************************

#pragma once

#include <CoreFoundation/CoreFoundation.h>

typedef enum CFObjRetainType
{
	kCFObjRetain,			//< Retain the object (+1 ref count)
	kCFObjDontRetain		//< Don't retain, take ownership of +1 ref (default)
} CFObjRetainType;

template <typename T> class CFObj
{
public:
    CFObj() noexcept
        : mRef(nullptr)
    {
    }

    // Takes ownership of inRef WITHOUT retaining by default when you don't specify the second arg.
    // Use for objects with +1 ref (e.g., from "Create" or "Copy" functions).
    // Pass kCFObjRetain as second arg if you need to retain an object already owned somewhere else
    CFObj(T inRef, CFObjRetainType inRetainType = kCFObjDontRetain) noexcept
        : mRef(inRef)
    {
        if( (mRef != nullptr) && (inRetainType == kCFObjRetain) )
            CFRetain(mRef);
    }

    // Copy constructor from another CFObj<> amkes this instance a second owner of the same CF object
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
							
	// Takes ownership of inRef WITHOUT retaining by default. Use kCFObjRetain to retain an existing reference.
    // Releases any existing object stored in this CFObj<> instance
	void Adopt(T inRef, CFObjRetainType inRetainType = kCFObjDontRetain) noexcept
    {
        if( (inRef != nullptr) && (inRetainType == kCFObjRetain) )
            CFRetain(inRef);
        Release();
        mRef = inRef;
    }

	// Transfers ownership WITHOUT retaining. Use Adopt(ptr, kCFObjRetain) to retain an existing reference.
	CFObj& operator=(T &inRef) noexcept
    {
        Adopt(inRef, kCFObjDontRetain);
        return *this;
    }

    CFObj& operator=(const CFObj& inRef) noexcept
    {
        Adopt(inRef.mRef, kCFObjRetain);
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

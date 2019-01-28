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
						CFObj()
							: mRef(NULL)
						{
						}

						CFObj(T inRef, CFObjRetainType inRetainType = kCFObjDontRetain)
							: mRef(inRef)
						{
							if( (mRef != NULL) && (inRetainType == kCFObjRetain) )
								::CFRetain(mRef);
						}

	virtual				~CFObj()
						{
							Release();
						}
						
	T					Detach()
						{
							T outRef = mRef;
							mRef = NULL;
							return outRef;
						}
							
	void				Release()
						{
							if(mRef != NULL)
							{
								::CFRelease(mRef);
								mRef = NULL;
							}
						}
                        
    void                Swap(CFObj &inOther)
                        {
                            T tempRef = mRef;
                            mRef = inOther.mRef;
                            inOther.mRef = tempRef;
                        }
							
	void				Adopt(T inRef, CFObjRetainType inRetainType = kCFObjDontRetain)
						{
							if( (inRef != NULL) && (inRetainType == kCFObjRetain) )
								::CFRetain(inRef);
							Release();
							mRef = inRef;
						}

//the following does not work with gcc because of gcc bug/unimplemented feature
	CFObj&				operator=(T &inRef)
						{
							Adopt(inRef, kCFObjDontRetain);
							return *this;
						}

						operator T() const
						{
							return mRef;
						}
						
	T*					operator & ()
						{
							return &mRef;
						}

	T					Get() const
						{
							return mRef;
						}

	T&					GetReference()
						{
							return mRef;
						}

protected:
	T					mRef;

private:
						CFObj(const CFObj&);
	CFObj&				operator=(const CFObj&);
						operator CFTypeRef() const;//no automatic conversion to void *
};

template <> class CFObj<CFTypeRef>
{
public:
						CFObj()
							: mRef(NULL)
						{
						}

						CFObj(CFTypeRef inRef, CFObjRetainType inRetainType = kCFObjDontRetain)
							: mRef(inRef)
						{
							if( (mRef != NULL) && (inRetainType == kCFObjRetain) )
								::CFRetain(mRef);
						}

	virtual				~CFObj()
						{
							Release();
						}
						
	CFTypeRef			Detach()
						{
							CFTypeRef outRef = mRef;
							mRef = NULL;
							return outRef;
						}
							
	void				Release()
						{
							if(mRef != NULL)
							{
								::CFRelease(mRef);
								mRef = NULL;
							}
						}
							
	void				Adopt(CFTypeRef inRef, CFObjRetainType inRetainType = kCFObjDontRetain)
						{
							if( (inRef != NULL) && (inRetainType == kCFObjRetain) )
								::CFRetain(inRef);
							Release();
							mRef = inRef;
						}

    void                Swap(CFObj &inOther)
                        {
                            CFTypeRef tempRef = mRef;
                            mRef = inOther.mRef;
                            inOther.mRef = tempRef;
                        }

//the following does not work with gcc because of gcc bug/unimplemented feature
	CFObj&				operator=(CFTypeRef &inRef)
						{
							Adopt(inRef, kCFObjDontRetain);
							return *this;
						}

						operator CFTypeRef() const
						{
							return mRef;
						}
						
	CFTypeRef*			operator & ()
						{
							return &mRef;
						}

	CFTypeRef			Get() const
						{
							return mRef;
						}

	CFTypeRef&			GetReference()
						{
							return mRef;
						}

protected:
	CFTypeRef			mRef;

private:
						CFObj(const CFObj&);
	CFObj&				operator=(const CFObj&);
};


template< class T > bool operator==( CFObj<T>& inObj, int *inNULL )
{
   return ( (T)inObj == (T)inNULL );
}
template< class T > bool operator!=( CFObj<T>& inObj, int *inNULL )
{
   return ( (T)inObj != (T)inNULL );
}

//mimics CFObj methods but without owning the object. Used as alternative CFObjectRef wrap
template <typename T> class CFObjNotOwned
{
public:
						CFObjNotOwned()
							: mRef(NULL)
						{
						}

						CFObjNotOwned(T inRef)
							: mRef(inRef)
						{
						}

	void				Adopt(T inRef)
						{
							mRef = inRef;
						}

						operator T() const
						{
							return mRef;
						}
						
	T*					operator & ()
						{
							return &mRef;
						}

	T					Get() const
						{
							return mRef;
						}

	T&					GetReference()
						{
							return mRef;
						}

private:
						CFObjNotOwned(T /*inRef*/, CFObjRetainType /*inRetainType*/);//don't allow this constructor

protected:
	T					mRef;
};

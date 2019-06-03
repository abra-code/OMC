#pragma once

#include "CFObj.h"
#include "ACFType.h"

//T typename = CFDictionaryRef or CFMutableDictionaryRef
template <typename T> class ACFDictBase : public CFObj<T>
{
public:
    //note: reverse retain default than CFObj!
	ACFDictBase(T inObj, CFObjRetainType inRetainType = kCFObjRetain) noexcept
        : CFObj<T>(inObj, inRetainType)
	{
	}

	template< typename CFT >
	Boolean GetValue( CFStringRef inKey, CFT &outValue ) const noexcept
	{
		if(this->mRef != NULL)
		{
			CFTypeRef resultRef = NULL;
			Boolean keyExists = ::CFDictionaryGetValueIfPresent( this->mRef, inKey, &resultRef );
			if( keyExists && ACFType<CFT>::DynamicCast(resultRef, outValue) )
				return true;
		}
		return false;
	}
	
	template< typename CFT >
	Boolean CopyValue( CFStringRef inKey, CFT &outValue ) const noexcept
	{
		if( GetValue(inKey, outValue) )
		{
			::CFRetain(outValue);
			return true;
		}
		return false;
	}

	template< typename CFT >
	Boolean CopyValue( CFStringRef inKey, CFObj<CFT> &outValue ) const noexcept
	{
		CFT valueRef = NULL;
		if( GetValue(inKey, valueRef) )
		{
			outValue.Adopt(valueRef, kCFObjRetain);
			return true;
		}
		return false;
	}

	Boolean GetValue( CFStringRef inKey, CFIndex &outValue ) const noexcept
	{
		CFNumberRef theNum = NULL;
		if( GetValue(inKey, theNum) )
			return ::CFNumberGetValue( theNum, kCFNumberCFIndexType, &outValue );
		return false;
	}

	Boolean GetValue( CFStringRef inKey, short &outValue ) const noexcept
	{
		CFNumberRef theNum = NULL;
		if( GetValue(inKey, theNum) )
			return ::CFNumberGetValue( theNum, kCFNumberShortType, &outValue );
		return false;
	}
	
	Boolean GetValue( CFStringRef inKey, float &outValue ) const noexcept
	{
		CFNumberRef theNum = NULL;
		if( GetValue(inKey, theNum) )
			return ::CFNumberGetValue( theNum, kCFNumberFloatType, &outValue );
		return false;
	}
	
	Boolean GetValue( CFStringRef inKey, double &outValue ) const noexcept
	{
		CFNumberRef theNum = NULL;
		if( GetValue(inKey, theNum) )
			return ::CFNumberGetValue( theNum, kCFNumberDoubleType, &outValue );
		return false;
	}
	
	
	Boolean GetValue( CFStringRef inKey, Boolean &outValue ) const noexcept
	{
		CFBooleanRef theBool = NULL;
		if( GetValue(inKey, theBool) )
		{
			outValue = ::CFBooleanGetValue(theBool);
			return true;
		}
		return false;
	}
	
	Boolean GetValue( CFStringRef inKey, CFTypeRef &outValue ) const noexcept
	{
		if(this->mRef != NULL)
		{
			CFTypeRef resultRef = NULL;
			Boolean keyExists = ::CFDictionaryGetValueIfPresent( this->mRef, inKey, &resultRef );
			if( keyExists && (resultRef != NULL) )
			{
				outValue = resultRef;
				return true;
			}
		}
		return false;
	}
};
	
typedef ACFDictBase<CFDictionaryRef> ACFDict;

class ACFMutableDict : public ACFDictBase<CFMutableDictionaryRef>
{
public:
    ACFMutableDict() noexcept
        : ACFDictBase<CFMutableDictionaryRef>( CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks ), kCFObjDontRetain )
    {
    }
    
    
    //note: reverse retain default than CFObj!
	ACFMutableDict( CFMutableDictionaryRef inObj, CFObjRetainType inRetainType = kCFObjRetain ) noexcept
		: ACFDictBase<CFMutableDictionaryRef>( inObj, kCFObjRetain )
	{
	}

	void SetValue( CFStringRef inKey, CFStringRef inValue) noexcept
	{
		if(inValue != NULL)
			::CFDictionarySetValue(mRef, inKey, inValue);
		else
			::CFDictionaryRemoveValue(mRef, inKey);
	}
			
	void SetValue( CFStringRef inKey, CFIndex inValue) noexcept
	{
		CFObj<CFNumberRef> cfNumber( ::CFNumberCreate( kCFAllocatorDefault, kCFNumberCFIndexType, &inValue) );
		::CFDictionarySetValue( mRef, inKey, (CFNumberRef)cfNumber );
	}
	
	void SetValue( CFStringRef inKey, float inValue) noexcept
	{
		CFObj<CFNumberRef> cfNumber( ::CFNumberCreate( kCFAllocatorDefault, kCFNumberFloatType, &inValue) );
		::CFDictionarySetValue(mRef, inKey, (CFNumberRef)cfNumber );
	}
	
	void SetValue( CFStringRef inKey, double inValue) noexcept
	{
		CFObj<CFNumberRef> cfNumber( ::CFNumberCreate( kCFAllocatorDefault, kCFNumberDoubleType, &inValue) );
		::CFDictionarySetValue(mRef, inKey, (CFNumberRef)cfNumber );
	}
	
	void SetValue( CFStringRef inKey, Boolean inValue) noexcept
	{
		::CFDictionarySetValue(mRef, inKey, inValue ? kCFBooleanTrue : kCFBooleanFalse );
	}
	
	void SetValue( CFStringRef inKey, bool inValue) noexcept
	{
		::CFDictionarySetValue(mRef, inKey, inValue ? kCFBooleanTrue : kCFBooleanFalse );
	}

	void SetValue( CFStringRef inKey, CFTypeRef inValue) noexcept
	{
		if(inValue != NULL)
			::CFDictionarySetValue(mRef, inKey, inValue);
		else
			::CFDictionaryRemoveValue(mRef, inKey);
	}
};
	

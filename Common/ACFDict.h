#pragma once

#include "CFObj.h"
#include "ACFType.h"

//T typename = CFDictionaryRef or CFMutableDictionaryRef
//TWrap<> = CFObj<> or CFObjNotOwned<>
template <typename T, template<typename> class TWrap > class ACFDictBase : public TWrap<T>
{
public:

	ACFDictBase()
	{
	}

	ACFDictBase( T inObj )
		: TWrap<T>(inObj)
	{
	
	}

	//only for CFObj:
	ACFDictBase( T inObj, CFObjRetainType inRetainType )
		: CFObj<T>(inObj, inRetainType)
	{
	
	}
		
	template< typename CFT >
	Boolean GetValue( CFStringRef inKey, CFT &outValue )
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
	Boolean CopyValue( CFStringRef inKey, CFT &outValue )
	{
		if( GetValue(inKey, outValue) )
		{
			::CFRetain(outValue);
			return true;
		}
		return false;
	}

	template< typename CFT >
	Boolean CopyValue( CFStringRef inKey, CFObj<CFT> &outValue )
	{
		CFT valueRef = NULL;
		if( GetValue(inKey, valueRef) )
		{
			outValue.Adopt(valueRef, kCFObjRetain);
			return true;
		}
		return false;
	}

	Boolean GetValue( CFStringRef inKey, CFIndex &outValue )
	{
		CFNumberRef theNum = NULL;
		if( GetValue(inKey, theNum) )
			return ::CFNumberGetValue( theNum, kCFNumberCFIndexType, &outValue );
		return false;
	}

	Boolean GetValue( CFStringRef inKey, short &outValue )
	{
		CFNumberRef theNum = NULL;
		if( GetValue(inKey, theNum) )
			return ::CFNumberGetValue( theNum, kCFNumberShortType, &outValue );
		return false;
	}
	
	Boolean GetValue( CFStringRef inKey, float &outValue )
	{
		CFNumberRef theNum = NULL;
		if( GetValue(inKey, theNum) )
			return ::CFNumberGetValue( theNum, kCFNumberFloatType, &outValue );
		return false;
	}
	
	Boolean GetValue( CFStringRef inKey, double &outValue )
	{
		CFNumberRef theNum = NULL;
		if( GetValue(inKey, theNum) )
			return ::CFNumberGetValue( theNum, kCFNumberDoubleType, &outValue );
		return false;
	}
	
	
	Boolean GetValue( CFStringRef inKey, Boolean &outValue )
	{
		CFBooleanRef theBool = NULL;
		if( GetValue(inKey, theBool) )
		{
			outValue = ::CFBooleanGetValue(theBool);
			return true;
		}
		return false;
	}
	
	Boolean GetValue( CFStringRef inKey, CFTypeRef &outValue )
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
	
typedef ACFDictBase<CFDictionaryRef, CFObjNotOwned> ACFDict;
typedef ACFDictBase<CFDictionaryRef, CFObj> ACFDictOwned;

typedef ACFDictBase<CFMutableDictionaryRef, CFObj> ACFMutableDictBaseOwned;
	
class ACFMutableDict : public ACFMutableDictBaseOwned
{
public:
	ACFMutableDict()
	: ACFMutableDictBaseOwned ( ::CFDictionaryCreateMutable( kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks ) )
	{
	}

	ACFMutableDict( CFMutableDictionaryRef inObj, CFObjRetainType inRetainType = kCFObjRetain )
		: ACFMutableDictBaseOwned ( inObj, inRetainType )
	{
	}

	void SetValue( CFStringRef inKey, CFStringRef inValue)
	{
		if(inValue != NULL)
			::CFDictionarySetValue(mRef, inKey, inValue);
		else
			::CFDictionaryRemoveValue(mRef, inKey);
	}
			
	void SetValue( CFStringRef inKey, CFIndex inValue)
	{
		CFObj<CFNumberRef> cfNumber( ::CFNumberCreate( kCFAllocatorDefault, kCFNumberCFIndexType, &inValue) );
		::CFDictionarySetValue( mRef, inKey, (CFNumberRef)cfNumber );
	}
	
	void SetValue( CFStringRef inKey, float inValue)
	{
		CFObj<CFNumberRef> cfNumber( ::CFNumberCreate( kCFAllocatorDefault, kCFNumberFloatType, &inValue) );
		::CFDictionarySetValue(mRef, inKey, (CFNumberRef)cfNumber );
	}
	
	void SetValue( CFStringRef inKey, double inValue)
	{
		CFObj<CFNumberRef> cfNumber( ::CFNumberCreate( kCFAllocatorDefault, kCFNumberDoubleType, &inValue) );
		::CFDictionarySetValue(mRef, inKey, (CFNumberRef)cfNumber );
	}
	
	void SetValue( CFStringRef inKey, Boolean inValue)
	{
		::CFDictionarySetValue(mRef, inKey, inValue ? kCFBooleanTrue : kCFBooleanFalse );
	}
	
	void SetValue( CFStringRef inKey, bool inValue)
	{
		::CFDictionarySetValue(mRef, inKey, inValue ? kCFBooleanTrue : kCFBooleanFalse );
	}

	void SetValue( CFStringRef inKey, CFTypeRef inValue)
	{
		if(inValue != NULL)
			::CFDictionarySetValue(mRef, inKey, inValue);
		else
			::CFDictionaryRemoveValue(mRef, inKey);
	}
};
	

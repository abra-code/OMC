#pragma once

#include "CFObj.h"
#include "ACFType.h"

//T typename = CFArrayRef | CFMutableArrayRef
template <typename T> class ACFArrayBase : public CFObj<T>
{
public:

	ACFArrayBase()
	{
	}
	
	ACFArrayBase( T inObj, CFObjRetainType inRetainType = kCFObjRetain )
		: CFObj<T>(inObj, inRetainType)
	{
	
	}

	CFIndex GetCount()
	{
		if(this->mRef != NULL)
			return ::CFArrayGetCount( this->mRef );
		return 0;
	}

	template< typename CFT >
	Boolean GetValueAtIndex( CFIndex idx, CFT &outValue )
	{
		if(this->mRef != NULL)
		{
			CFTypeRef resultRef = ::CFArrayGetValueAtIndex( this->mRef, idx );
			return ACFType<CFT>::DynamicCast(resultRef, outValue);
		}
		return false;
	}

	template< typename CFT >
	Boolean CopyValueAtIndex( CFIndex idx, CFT &outValue )
	{
		if( GetValueAtIndex(idx, outValue) )
		{
			::CFRetain(outValue);
			return true;
		}
		return false;
	}

	CFTypeRef GetValueAtIndex( CFIndex idx )
	{
		if(this->mRef != NULL)
			return ::CFArrayGetValueAtIndex( this->mRef, idx );
		return NULL;
	}
};

typedef ACFArrayBase<CFArrayRef> ACFArr;

class ACFMutableArr : public ACFArrayBase<CFMutableArrayRef>
{
public:
	ACFMutableArr(CFIndex maxCount = 0)
	: ACFArrayBase<CFMutableArrayRef>( ::CFArrayCreateMutable( kCFAllocatorDefault, maxCount, &kCFTypeArrayCallBacks ) )
	{
	}

	ACFMutableArr( CFMutableArrayRef inObj, CFObjRetainType inRetainType = kCFObjRetain )
		: ACFArrayBase<CFMutableArrayRef>( inObj, inRetainType )
	{
	}

	template< typename CFT >
	void InsertValueAtIndex( CFIndex idx, CFT inCFObj )
	{
		::CFArrayInsertValueAtIndex( mRef, idx, (const void *)inCFObj );
	}

	template< typename CFT >
	void SetValueAtIndex( CFIndex idx, CFT inCFObj )
	{
		::CFArraySetValueAtIndex( mRef, idx, (const void *)inCFObj );
	}
	
	template< typename CFT >
	void AppendValue( CFT inCFObj )
	{
		::CFArrayAppendValue( mRef, (const void *)inCFObj );
	}

	void RemoveValueAtIndex( CFIndex idx )
	{
		::CFArrayRemoveValueAtIndex( mRef, idx );
	}

	void RemoveAllValues()
	{
		::CFArrayRemoveAllValues( mRef );
	}
};
	

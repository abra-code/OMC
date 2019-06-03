#pragma once

#include "CFObj.h"
#include "ACFType.h"

//T typename = CFArrayRef | CFMutableArrayRef
template <typename T> class ACFArrayBase : public CFObj<T>
{
public:
    //note: reverse retain default than CFObj!
	ACFArrayBase( T inObj, CFObjRetainType inRetainType = kCFObjRetain ) noexcept
		: CFObj<T>(inObj, inRetainType)
	{
	
	}

	CFIndex GetCount() const noexcept
	{
		if(this->mRef != NULL)
			return ::CFArrayGetCount( this->mRef );
		return 0;
	}

	template< typename CFT >
	Boolean GetValueAtIndex( CFIndex idx, CFT &outValue ) const noexcept
	{
		if(this->mRef != NULL)
		{
			CFTypeRef resultRef = ::CFArrayGetValueAtIndex( this->mRef, idx );
			return ACFType<CFT>::DynamicCast(resultRef, outValue);
		}
		return false;
	}

	template< typename CFT >
	Boolean CopyValueAtIndex( CFIndex idx, CFT &outValue ) const noexcept
	{
		if( GetValueAtIndex(idx, outValue) )
		{
			::CFRetain(outValue);
			return true;
		}
		return false;
	}

	CFTypeRef GetValueAtIndex( CFIndex idx ) const noexcept
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
	ACFMutableArr(CFIndex maxCount = 0) noexcept
	: ACFArrayBase<CFMutableArrayRef>( ::CFArrayCreateMutable( kCFAllocatorDefault, maxCount, &kCFTypeArrayCallBacks ) )
	{
	}

    //note: reverse retain default than CFObj!
	ACFMutableArr( CFMutableArrayRef inObj, CFObjRetainType inRetainType = kCFObjRetain ) noexcept
		: ACFArrayBase<CFMutableArrayRef>( inObj, inRetainType )
	{
	}

	template< typename CFT >
	void InsertValueAtIndex( CFIndex idx, CFT inCFObj ) noexcept
	{
		::CFArrayInsertValueAtIndex( mRef, idx, (const void *)inCFObj );
	}

	template< typename CFT >
	void SetValueAtIndex( CFIndex idx, CFT inCFObj ) noexcept
	{
		::CFArraySetValueAtIndex( mRef, idx, (const void *)inCFObj );
	}
	
	template< typename CFT >
	void AppendValue( CFT inCFObj ) noexcept
	{
		::CFArrayAppendValue( mRef, (const void *)inCFObj );
	}

	void RemoveValueAtIndex( CFIndex idx ) noexcept
	{
		::CFArrayRemoveValueAtIndex( mRef, idx );
	}

	void RemoveAllValues() noexcept
	{
		::CFArrayRemoveAllValues( mRef );
	}
};
	

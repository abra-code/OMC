#pragma once

#include "CFObj.h"
#include "ACFType.h"

//T typename = CFArrayRef | CFMutableArrayRef
template <typename T> class ACFArrayBase : public CFObj<T>
{
public:
	ACFArrayBase() noexcept
		: CFObj<T>()
	{
	}

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
	bool GetValueAtIndex( CFIndex idx, CFT &outValue ) const noexcept
	{
		if(this->mRef != NULL)
		{
			CFTypeRef resultRef = ::CFArrayGetValueAtIndex( this->mRef, idx );
			return ACFType<CFT>::DynamicCast(resultRef, outValue);
		}
		return false;
	}

	template< typename CFT >
	bool CopyValueAtIndex( CFIndex idx, CFT &outValue ) const noexcept
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

	// The value at idx, of any type; NULL when idx is out of range (GetValueAtIndex does not check)
	CFTypeRef operator[]( CFIndex idx ) const noexcept
	{
		if( (this->mRef == NULL) || (idx < 0) || (idx >= ::CFArrayGetCount(this->mRef)) )
			return NULL;
		return ::CFArrayGetValueAtIndex( this->mRef, idx );
	}
};

typedef ACFArrayBase<CFArrayRef> ACFArr;

class ACFMutableArr : public ACFArrayBase<CFMutableArrayRef>
{
public:
	explicit ACFMutableArr(CFIndex maxCount = 0) noexcept
	: ACFArrayBase<CFMutableArrayRef>( ::CFArrayCreateMutable( kCFAllocatorDefault, maxCount, &kCFTypeArrayCallBacks ), kCFObjDontRetain )
	{
	}

    //note: reverse retain default than CFObj!
	ACFMutableArr( CFMutableArrayRef inObj, CFObjRetainType inRetainType = kCFObjRetain ) noexcept
		: ACFArrayBase<CFMutableArrayRef>( inObj, inRetainType )
	{
	}

	// The writes take a CF object: any CF reference, or a CFObj and the wrappers through their conversion
	// to the reference. Not a template casting anything to a pointer, which let a number through.
	void InsertValueAtIndex( CFIndex idx, CFTypeRef inValue ) noexcept
	{
		::CFArrayInsertValueAtIndex( mRef, idx, inValue );
	}

	void SetValueAtIndex( CFIndex idx, CFTypeRef inValue ) noexcept
	{
		::CFArraySetValueAtIndex( mRef, idx, inValue );
	}

	void AppendValue( CFTypeRef inValue ) noexcept
	{
		::CFArrayAppendValue( mRef, inValue );
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


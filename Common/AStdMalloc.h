//**************************************************************************************
// Filename:	AStdMalloc.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright � 2003 Abracode, Inc.  All rights reserved.
//
// Description:	auto_ptr idea taken beyond simple objects allocated with "new"
//**************************************************************************************

#pragma once

#include "AMemoryCommon.h"
#include <stdlib.h>
#include <string>

template <class T>
class AStdMalloc
{
public:
		AStdMalloc()
			: mObject(NULL), mIsOwner( kMemObj_NotOwned) {}
		
		//memory allocation constructor
		//CAUTION: the size is interpreted as a count of T objects
		AStdMalloc(size_t inSize, EMemObjClearOption inClearOption = kMemObj_DontClearMemory)
			: mObject(NULL), mIsOwner(kMemObj_NotOwned)
		{
			AllocateAndCopy(NULL, inSize, inClearOption);
		}

		//plain assignment with optional ownership taking, no copy.
		//inMallocPtr must be allocated with malloc or calloc
		AStdMalloc(
				void * inMallocPtr,
				EMemObjOwnershipType inIsOwner = kMemObj_Owned)
			: mObject(static_cast<T*>(inMallocPtr)), mIsOwner(inIsOwner) {}
		
		//pointer and size constructor 
		//the input pointer may not be allocated by malloc, so we allocate private copy
		//CAUTION: the size is interpreted as a count of T objects
		AStdMalloc(
				const T *inPtr,
				size_t inSize)
			: mObject(NULL), mIsOwner(kMemObj_NotOwned)
		{
			AllocateAndCopy(inPtr,inSize);
		}
		
		//copy constructor - only shallow is allowed here
		//becaue we do not keep the size of the block so we cannot copy it
		//the object is detached from the original
		AStdMalloc(const AStdMalloc& inOrig)
			: mObject(NULL), mIsOwner(kMemObj_NotOwned)
		{
			EMemObjOwnershipType isOwner = inOrig.mIsOwner;
			Reset(inOrig.Detach(), isOwner );
		}

	virtual
		~AStdMalloc() { Dispose(); }

		//object assignment as a shallow copy with ownership change
	AStdMalloc&
		operator=(
				const AStdMalloc& inMallocPtr)
		{
			EMemObjOwnershipType isOwner = inMallocPtr.mIsOwner;
			Reset(inMallocPtr.Detach(), isOwner );
			return *this;
		}

		//plain pointer assignment with ownership taking, no copy
		//inMallocPtr must be allocated with  malloc or calloc
	AStdMalloc&
		operator=(
				const void * inMallocPtr)
		{
			Reset(static_cast<T*>(const_cast<void*>(inMallocPtr)), kMemObj_Owned);
			return *this;
		}

		operator T*() const
		{
			return mObject;
		}

	T&
		operator * () const
		{
			return *mObject;
		}

	T*
		operator -> () const
		{
			return mObject;
		}

	T&
		operator [] (size_t index) const
		{
			return mObject[index];
		}

	T&
		operator [] (CFIndex index) const
		{
			return mObject[index];
		}

	//CAUTION: potentially costly
	//CAUTION: you cannot reallocate not owned pointer so resize will fail
	//CAUTION: the size is interpreted as a count of T objects
	void
		Resize(size_t inNewSize)
		{
			if(mObject != NULL)
			{
				if(mIsOwner == kMemObj_Owned)
				{//reallocate ONLY if we own the pointer
					T *newPtr = static_cast<T*>(realloc(mObject, inNewSize*sizeof(T)));
					if(newPtr == NULL)
					{
						THROW_IF_ERROR(-108);//aka memFullErr in Mac OS
					}
					mObject = newPtr;
				}
				else
				{
					THROW_IF_ERROR(-50);//aka paramErr in Mac OS, misuse
				}
			}
			else
				AllocateAndCopy(NULL, inNewSize);
		}

	static void
		CopyData(const T *inSource, T *inDest, size_t inSize)
		{
			memmove(inDest, inSource, inSize *sizeof(T));
		}

	static void
		ClearData(void *inPtr, size_t inSize)
		{
			memset(inPtr, 0, inSize*sizeof(T) );
		}

	T *
		Get() const
		{
			return mObject;
		}

	T *
		Detach() const
		{
			mIsOwner = kMemObj_NotOwned;
			return mObject;
		}

	void
		Reset(
				T *inObject,
				EMemObjOwnershipType inIsOwner = kMemObj_Owned)
		{
			if ((mIsOwner == kMemObj_Owned) && (mObject != NULL) && (inObject != mObject)) DisposeSelf();
			mObject = inObject;
			mIsOwner = inIsOwner;
		}

	void
		Dispose()
		{
			if (mObject != NULL)
			{
				if(mIsOwner == kMemObj_Owned) DisposeSelf();
				mObject = NULL;
			}
			mIsOwner = kMemObj_NotOwned;
		}

	static void
		DisposeProc(void *inObj)
		{
			if(inObj != NULL)
			{
				void **objPtr = reinterpret_cast<void **>(inObj);
				if(*objPtr != NULL)
					free(*objPtr);
				*objPtr = NULL;
			}
		}

#ifdef DEFINE_CF_CALLBACKS
//inSize in CoreFoundation callbacks is real size, not count of sizeof(T)!

	static void *
		AllocateCallback(CFIndex inSize, CFOptionFlags /*hint*/, void * /*info*/)
		{
			return malloc(inSize);
		}

	static void *
		ReallocateCallback(void *inPtr, CFIndex inNewSize, CFOptionFlags /*hint*/, void * /*info*/)
		{
			if( (inPtr == NULL) || (inNewSize < 0) )
				return NULL;
			return realloc(inPtr, inNewSize);
		}

	static void
		DeallocateCallback(void *inPtr, void * /*info*/)
		{
			if(inPtr != NULL)
				free(inPtr);
		}

	static CFIndex
		PreferredSizeCallback(CFIndex inSize, CFOptionFlags /*hint*/, void * /*info*/)
		{
			return inSize; //malloc_good_size(inSize);
		}

	static CFAllocatorRef
		GetCFAllocator()
		{
			static CFAllocatorRef sAllocator = NULL;
			if(sAllocator != NULL)
				return sAllocator;
			CFAllocatorContext allocContext = 
			{
				0,//version
				NULL, //info
				NULL, //retain for "info" field context
				NULL, //release for "info" field context
				NULL, //copyDescription
				AllocateCallback, //allocate
				ReallocateCallback, //reallocate
				DeallocateCallback, //deallocate
				PreferredSizeCallback //preferredSize
			};
			sAllocator = ::CFAllocatorCreate(kCFAllocatorDefault, &allocContext);
			return sAllocator;
		}

#endif //DEFINE_CF_CALLBACKS

protected:

	void
		AllocateAndCopy(
				const T *inSrcPtr,
				size_t inSize,
				EMemObjClearOption inClearOption = kMemObj_DontClearMemory)
		{
			if(inSize != 0)
			{
				if(	(inClearOption == kMemObj_ClearMemory) && (inSrcPtr == NULL) )
					mObject = static_cast<T*>(calloc(inSize, sizeof(T)));
				else
					mObject = static_cast<T*>(malloc(inSize*sizeof(T)));
				
				if(mObject == NULL)
				{
					THROW_IF_ERROR(-108);//aka memFullErr
				}
				
				mIsOwner = kMemObj_Owned;
				
				if( (inSrcPtr != NULL) && (mObject != NULL) )
					CopyData(inSrcPtr, mObject, inSize);
			}
		}

	void
		DisposeSelf()
		{
			free(mObject);
		}

protected:
	T *mObject;
	mutable EMemObjOwnershipType mIsOwner;
};

typedef AStdMalloc<char> AMalloc;

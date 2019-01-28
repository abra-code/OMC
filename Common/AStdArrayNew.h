//**************************************************************************************
// Filename:	AStdArrayNew.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright � 2003 Abracode, Inc.  All rights reserved.
//
// Description:	auto_ptr idea taken beyond simple objects allocated with "new"
// Revision 12/26/06: Removed the owned/not owned flag which is practically useless (we always want it "owned")
//						and a bug that caused a leak in constructor with count of items
//**************************************************************************************

#pragma once

#include "AMemoryCommon.h"
#include <string.h>

template <class T>
class AStdArrayNew
{
public:
		AStdArrayNew()
			: mObject(NULL) {}

		AStdArrayNew(T *inObj)
			: mObject(inObj) { }
		
		//copy constructor - only shallow copy is allowed here
		//the object is detached from the original
		AStdArrayNew(const AStdArrayNew& inOrig)
			: mObject(NULL)
		{
			Reset( inOrig.Detach() );
		}

	//CAUTION: the size is interpreted as a count of T objects
		AStdArrayNew(size_t inSize, EMemObjClearOption inClearOption = kMemObj_DontClearMemory)
			: mObject(NULL)
			{
				mObject = new T[inSize];
				if(inClearOption == kMemObj_ClearMemory)
				{
					::memset(mObject, 0, inSize*sizeof(T) );
				}
			}
	
	virtual
		~AStdArrayNew() { Dispose(); }

		//object assignment as a shallow copy with ownership change
	AStdArrayNew&
		operator=(
				const AStdArrayNew& inObj)
		{
			Reset( inObj.Detach() );
			return *this;
		}

		//plain pointer assignment with ownership taking, no copy
		//inObj must be allocated with "new []"
	AStdArrayNew&
		operator=(
				const T* inObj)
		{
			Reset(inObj);
			return *this;
		}

	T *
		Get() const
		{
			return mObject;
		}

		operator T*() const
		{
			return mObject;
		}
	
	//fast, not safe version of []
	//caller must be sure mObject is not null and index is within range
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

	T*
		operator -> () const
		{
			if(mObject == NULL)
				throw OSStatus(-50);//paramErr
			return mObject;
		}

	T *
		Detach() const
		{
			T *outObj = mObject;
			mObject = NULL;
			return outObj;
		}

	void
		Reset(T *inObject)
		{
			if( (mObject != NULL) && (inObject != mObject) )
				DisposeSelf();
			mObject = inObject;
		}

	void
		Dispose()
		{
			if (mObject != NULL)
			{
				DisposeSelf();
				mObject = NULL;
			}
		}

	static void
		DisposeProc(void *inObj)
		{
			if(inObj != NULL)
			{
				T** objPtr = reinterpret_cast<T **>(inObj);
				delete [] *objPtr;
				*objPtr = NULL;
			}
		}

    void
		Swap(AStdArrayNew &ioOther)
		{
			T *tempObj = mObject;
			mObject = ioOther.mObject;
			ioOther.mObject = tempObj;
		}

#ifdef DEFINE_CF_CALLBACKS
//inSize in CoreFoundation callbacks is real size, not count of sizeof(T)!

	static void *
		AllocateCallback(CFIndex inSize, CFOptionFlags /*hint*/, void * /*info*/)
		{
			int theCount = inSize/sizeof(T);
			if( (inSize % sizeof(T)) != 0)
				theCount++;
			void *newObj = NULL;
			try { newObj = (void*) new T[theCount]; } catch(...) { }
			return newObj;
		}

	static void *
		ReallocateCallback(void *inPtr, CFIndex inNewSize, CFOptionFlags /*hint*/, void * /*info*/)
		{//reallocation is not allowed.
		//we would have to keep the previous size info in context (to copy all existing data)
		//if could be done if really needed
			return NULL;
		}

	static void
		DeallocateCallback(void *inPtr, void * /*info*/)
		{
			try { delete [] (reinterpret_cast<T *>(inPtr)); } catch(...) { }
		}

	static CFIndex
		PreferredSizeCallback(CFIndex inSize, CFOptionFlags /*hint*/, void * /*info*/)
		{
			if((inSize % sizeof(T)) != 0)
				return sizeof(T) * (inSize/sizeof(T) + 1);
			return inSize;
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
		DisposeSelf()
		{
			delete [] mObject;
		}

protected:
	mutable T *mObject;
};

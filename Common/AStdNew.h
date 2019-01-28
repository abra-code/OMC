//**************************************************************************************
// Filename:	AStdNew.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright � 2003 Abracode, Inc.  All rights reserved.
//
// Description:	auto_ptr idea taken beyond simple objects allocated with "new"
//**************************************************************************************

#pragma once

//#include "AMemoryCommon.h"


template <class T>
class AStdNew
{
public:
		AStdNew()
			: mObject(NULL) {}

		AStdNew(T *inObj)
			: mObject(inObj) { }
		
		//copy constructor - only shallow copy is allowed here
		//the object is detached from the original
		AStdNew(const AStdNew& inOrig)
			: mObject(NULL)
		{
			Reset(inOrig.Detach() );
		}

	virtual
		~AStdNew() { Dispose(); }

		//object assignment as a shallow copy with ownership change
	AStdNew&
		operator=(
				const AStdNew& inObj)
		{
			Reset(inObj.Detach());
			return *this;
		}

		//plain pointer assignment with ownership taking, no copy
		//inObj must be allocated with "new"
	AStdNew&
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
		
	T&
		operator * () const
		{
			return *mObject;
		}

	T*
		operator -> () const
		{
			if(mObject == NULL)
				throw OSStatus(-50);//paramErr
			return mObject;
		}

	T *
		Detach()
		{
			T *outObj = mObject;
			mObject = NULL;
			return outObj;
		}

	void
		Reset( T *inObject )
		{
			if( (mObject != NULL) && (inObject != mObject) )
				DisposeSelf();
			mObject = inObject;
		}

//synonyms for Reset
	void
		Adopt( T *inObject ) { Reset(inObject);  }

	void
		Attach( T *inObject ) { Reset(inObject);  }
	
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
				delete *objPtr;
				*objPtr = NULL;
			}
		}

    void
		Swap(AStdNew &ioOther)
		{
			T *tempObj = mObject;
			mObject = ioOther.mObject;
			ioOther.mObject = tempObj;
		}

#ifdef DEFINE_CF_CALLBACKS
//inSize in CoreFoundation callbacks is real size, not count of sizeof(T)!

//the following callbacks slightly stretch their designed usage
//but they might be actually helpful for deallocation of "new" object

	static void *
		AllocateCallback(CFIndex inSize, CFOptionFlags /*hint*/, void * /*info*/)
		{
			if(inSize == sizeof(T))
			{
				void *newObj = NULL;
				try { newObj = (void*) new T; } catch(...) { }//the T class must provide a default constructor for this to compile
				return newObj;
			}
			return NULL;
		}

	static void *
		ReallocateCallback(void *inPtr, CFIndex inNewSize, CFOptionFlags /*hint*/, void * /*info*/)
		{//reallocation is not allowed
			if(inNewSize == sizeof(T))
				return inPtr;
			return NULL;
		}

	static void
		DeallocateCallback(void *inPtr, void * /*info*/)
		{
			try { delete (reinterpret_cast<T *>(inPtr)); } catch(...) { }
		}

	static CFIndex
		PreferredSizeCallback(CFIndex /*inSize*/, CFOptionFlags /*hint*/, void * /*info*/)
		{
			return sizeof(T);
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
			delete mObject;
		}

protected:
	T *mObject;
};

//**************************************************************************************
// Filename:	AMemoryCommon.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright � 2003 Abracode, Inc.  All rights reserved.
//
// Description:	auto_ptr idea taken beyond simple objects allocated with "new"
//**************************************************************************************

#pragma once

#define THROW_IF_ERROR(_inErr) { if((_inErr) != 0) throw OSStatus(_inErr); }

//enable or disable CoreFoundation callback definitions for misc memory allocations
#define DEFINE_CF_CALLBACKS


#ifdef DEFINE_CF_CALLBACKS
	#include <CoreFoundation/CoreFoundation.h>
#endif

//Some constructors take an additional param telling
//if the memory space referenced by the pointer or Handle
//is going to be copied (deep) or just the reference to existing memory block is stored (shallow)

typedef enum
{
	kMemObj_ShallowCopy,
	kMemObj_DeepCopy
} EMemObjCopyType;


//Ownership type. Could have been Boolean but it is better if it is enum:

typedef enum
{
	kMemObj_NotOwned,
	kMemObj_Owned
} EMemObjOwnershipType;

//Additional parameter for constructors which allocate memory:

typedef enum
{
	kMemObj_DontClearMemory, //default in most cases
	kMemObj_ClearMemory	//zero memory on allocation
} EMemObjClearOption;


typedef void (*ADisposeProc)(void *inObj);


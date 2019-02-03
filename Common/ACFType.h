//**************************************************************************************
// Filename:	ACFType.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
//
// Copyright � 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	helper for CoreFountation types
//	
//
//
//**************************************************************************************

#pragma once

#include <CoreFoundation/CoreFoundation.h>

template <typename T> class ACFType
{
public:

//dynamic_cast<T> for CoreFoundation objects
	static T	DynamicCast(CFTypeRef inValue)
				{
					if( (inValue == NULL) || (::CFGetTypeID(inValue) != sTypeID) )
						return NULL;
					return (T)inValue;
				}

//specialized version which does not change the original value of outValue
//if the cast did not succeed. it returns false instead to indicate a problem
//designed for ACFDict so getting non-existing key does not change the default value
	static bool DynamicCast(CFTypeRef inValue, T &outValue)
				{
					if( (inValue == NULL) || (::CFGetTypeID(inValue) != sTypeID) )
						return false;
					outValue = (T)inValue;
					return true;
				}

	static CFTypeID GetTypeID() { return sTypeID; }

	static CFTypeID sTypeID;
};

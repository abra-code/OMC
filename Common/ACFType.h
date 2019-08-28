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
	static T	DynamicCast(CFTypeRef inValue) noexcept
				{
					if( (inValue == nullptr) || (::CFGetTypeID(inValue) != sTypeID) )
						return nullptr;
					return (T)inValue;
				}

//specialized version which does not change the original value of outValue
//if the cast did not succeed. it returns false instead to indicate a problem
//designed for ACFDict so getting non-existing key does not change the default value
	static bool DynamicCast(CFTypeRef inValue, T &outValue) noexcept
				{
					if( (inValue == nullptr) || (::CFGetTypeID(inValue) != sTypeID) )
						return false;
					outValue = (T)inValue;
					return true;
				}

	static CFTypeID GetTypeID() noexcept { return sTypeID; }

	static CFTypeID sTypeID;
};

template <> CFTypeID ACFType<CFStringRef>::sTypeID;
template <> CFTypeID ACFType<CFMutableStringRef>::sTypeID;
template <> CFTypeID ACFType<CFDictionaryRef>::sTypeID;
template <> CFTypeID ACFType<CFMutableDictionaryRef>::sTypeID;
template <> CFTypeID ACFType<CFArrayRef>::sTypeID;
template <> CFTypeID ACFType<CFMutableArrayRef>::sTypeID;
template <> CFTypeID ACFType<CFNumberRef>::sTypeID;
template <> CFTypeID ACFType<CFBooleanRef>::sTypeID;
template <> CFTypeID ACFType<CFDataRef>::sTypeID;
template <> CFTypeID ACFType<CFMutableDataRef>::sTypeID;
template <> CFTypeID ACFType<CFDateRef>::sTypeID;
template <> CFTypeID ACFType<CFBundleRef>::sTypeID;
template <> CFTypeID ACFType<CFURLRef>::sTypeID;
template <> CFTypeID ACFType<CFSetRef>::sTypeID;
template <> CFTypeID ACFType<CFMutableSetRef>::sTypeID;

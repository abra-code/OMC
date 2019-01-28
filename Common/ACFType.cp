//**************************************************************************************
// Filename:	ACFType.cp
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

#include "ACFType.h"

//most common CF types that can be used in property lists:

template <> CFTypeID ACFType<CFStringRef>::sTypeID		= ::CFStringGetTypeID();
template <> CFTypeID ACFType<CFMutableStringRef>::sTypeID = ::CFStringGetTypeID();
template <> CFTypeID ACFType<CFDictionaryRef>::sTypeID	= ::CFDictionaryGetTypeID();
template <> CFTypeID ACFType<CFMutableDictionaryRef>::sTypeID = ::CFDictionaryGetTypeID();
template <> CFTypeID ACFType<CFArrayRef>::sTypeID		= ::CFArrayGetTypeID();
template <> CFTypeID ACFType<CFMutableArrayRef>::sTypeID = ::CFArrayGetTypeID();
template <> CFTypeID ACFType<CFNumberRef>::sTypeID		= ::CFNumberGetTypeID();
template <> CFTypeID ACFType<CFBooleanRef>::sTypeID		= ::CFBooleanGetTypeID();
template <> CFTypeID ACFType<CFDataRef>::sTypeID		= ::CFDataGetTypeID();
template <> CFTypeID ACFType<CFMutableDataRef>::sTypeID	= ::CFDataGetTypeID();
template <> CFTypeID ACFType<CFDateRef>::sTypeID		= ::CFDateGetTypeID();
template <> CFTypeID ACFType<CFBundleRef>::sTypeID		= ::CFBundleGetTypeID();
template <> CFTypeID ACFType<CFURLRef>::sTypeID			= ::CFURLGetTypeID();

//Some other, currently unused CF types.
//Uncomment when needed
#if 0

template <> CFTypeID ACFType<CFSetRef>::sTypeID = ::CFSetGetTypeID();
template <> CFTypeID ACFType<CFDateFormatterRef>::sTypeID = ::CFDateFormatterGetTypeID();
template <> CFTypeID ACFType<CFLocaleRef>::sTypeID = ::CFLocaleGetTypeID();
template <> CFTypeID ACFType<CFNumberFormatterRef>::sTypeID = ::CFNumberFormatterGetTypeID();
template <> CFTypeID ACFType<CFPlugInRef>::sTypeID = ::CFPlugInGetTypeID();
template <> CFTypeID ACFType<CFAllocatorRef>::sTypeID = ::CFAllocatorGetTypeID();
template <> CFTypeID ACFType<CFNullRef>::sTypeID = ::CFNullGetTypeID();
template <> CFTypeID ACFType<CFBagRef>::sTypeID = ::CFBagGetTypeID();
template <> CFTypeID ACFType<CFAttributedStringRef>::sTypeID = ::CFAttributedStringGetTypeID();
template <> CFTypeID ACFType<CFMessagePortRef>::sTypeID = ::CFMessagePortGetTypeID();
template <> CFTypeID ACFType<CFUUIDRef>::sTypeID = ::CFUUIDGetTypeID();

#endif
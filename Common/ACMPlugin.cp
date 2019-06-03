//**************************************************************************************
// Filename:	ACMPlugin.cp
//				Part of Abracode Workshop.
//
// Description:	Base code for CM plugin taking care of COM interface and communication with a host.
//				Not needed to be modified in most cases.
//				
// Usage:		see Documentation.txt
//
// License:		FreeBSD-like
//						
//**************************************************************************************


#include "ACMPlugin.h"
#include "CFObj.h"
#include "DebugSettings.h"

ACMPlugin::ACMPlugin(CFStringRef inBundleID)
{
	TRACE_CSTR( "ACMPlugin::ACMPlugin\n" );

	if(inBundleID != NULL)
		mBundleRef.Adopt( ::CFBundleGetBundleWithIdentifier(inBundleID), kCFObjRetain );

#if _DEBUG_
	if( (CFBundleRef)mBundleRef != NULL)
	{
		CFIndex bundleRetainCount = ::CFGetRetainCount( (CFBundleRef)mBundleRef );
		DEBUG_CSTR("ACMPlugin::ACMPlugin. CFBundleRef retain count after getting it and retaining is %d\n", (int)bundleRetainCount );
	}
	else
	{
		DEBUG_CSTR("CFBundleGetBundleWithIdentifier returned NULL!\n");
	}
#endif
}

ACMPlugin::~ACMPlugin()
{
	TRACE_CSTR( "ACMPlugin::~ACMPlugin\n" );

#if _DEBUG_
	if( (CFBundleRef)mBundleRef != NULL)
	{
		CFIndex bundleRetainCount = ::CFGetRetainCount( (CFBundleRef)mBundleRef );
		DEBUG_CSTR("ACMPlugin::~ACMPlugin(). CFBundleRef retain count before release is %d\n", (int)bundleRetainCount );
	}
	else
	{
		DEBUG_CSTR("ACMPlugin::~ACMPlugin. NULL mBundleRef!\n");
	}
#endif
}

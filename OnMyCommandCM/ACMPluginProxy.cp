//**************************************************************************************
// Filename:	ACMPluginProxy.cp
//				Part of Abracode Workshop.
//
// Description:	Base code for CM plugin taking care of COM interface and communication with a host.
//				Not needed to be modified in most cases.
//				
// Usage:		see Documentation.txt
//
// License:		This code is based on "CFPluginMenu.cp" and "SampleCMPlugin.c"
//				of "SampleCMPlugin" from Apple.
//				Great thanks to George Warner for providing these sources.
//						
//**************************************************************************************

#include <CoreServices/CoreServices.h>
#include <CoreFoundation/CFPlugInCOM.h>
#include <Carbon/Carbon.h>
#include "CFObj.h"
#include "ARefCounted.h"
#include "DebugSettings.h"
#include "ACMPlugin.h"

//main entry point to the plugin's bundle code
//this is the only function being exported and it is the one specified in plugin's bundle Info.plist
extern "C" void * ACMPluginFactory( CFAllocatorRef allocator, CFUUIDRef typeID );

void * CreateACMPluginProxy();

SInt32 ACMPluginProxyQueryInterface( void *thisInstance, CFUUIDBytes iid, void **ppv );
UInt32 ACMPluginProxyAddRef( void *thisInstance );
UInt32 ACMPluginProxyRelease( void *thisInstance );
OSStatus ACMPluginProxyExamineContext( void *, const AEDesc *, AEDescList *);
OSStatus ACMPluginProxyHandleSelection( void *, AEDesc *, SInt32);
void ACMPluginProxyPostMenuCleanup(void * /*thisInstance*/);

ContextualMenuInterfaceStruct sACMPluginProxyInterface =
{ 
// Required padding for COM
	NULL,
		
// These three are the required COM functions
	ACMPluginProxyQueryInterface,
	ACMPluginProxyAddRef, 
	ACMPluginProxyRelease, 

// Interface implementation
	ACMPluginProxyExamineContext,
	ACMPluginProxyHandleSelection,
	ACMPluginProxyPostMenuCleanup
};


// -----------------------------------------------------------------------------
//	ACMPluginFactory
// -----------------------------------------------------------------------------
//	Implementation of the factory function for this type.
//
extern "C" void *ACMPluginFactory( CFAllocatorRef allocator, CFUUIDRef typeID )
{
#pragma unused( allocator )

	TRACE_CSTR( "Entering ACMPluginFactory\n" );

	if(typeID == NULL)
		return NULL;

	void *pluginProxy = NULL;
	// If correct type is being requested, allocate an
	// instance and return the IUnknown interface.
	if ( ::CFEqual( typeID, kContextualMenuTypeID ) )
		pluginProxy = CreateACMPluginProxy();

	TRACE_CSTR( "Exiting ACMPluginFactory\n" );
	// If the requested type is incorrect, return NULL.
	return pluginProxy;
}


typedef struct ACMPluginProxy
{
	ContextualMenuInterfaceStruct	*interface;
	UInt32							refCount;
//	CFObj<CFUUIDRef>				factoryID;
    ARefCountedObj<ACMPlugin>		plugin; //defined and used by plugin implementation
} ACMPluginProxy;


void *
CreateACMPluginProxy()
{
	ACMPluginProxy *proxy = NULL;
	try
	{
		proxy = new ACMPluginProxy();
		proxy->interface = &sACMPluginProxyInterface;
		proxy->refCount = 1;
		::CFPlugInAddInstanceForFactory( kCMPluginFactoryID );
		return (void *)proxy;
	}
	catch(...)
	{
		delete proxy;
	}
	return NULL;
}


#pragma mark -


// -----------------------------------------------------------------------------
//	AbstractCMPluginQueryInterface
// -----------------------------------------------------------------------------
//  Implementation of the IUnknown QueryInterface function.
//
SInt32 ACMPluginProxyQueryInterface( void *thisInstance, CFUUIDBytes iid, void **ppv )
{
	TRACE_CSTR( "ACMPluginProxyQueryInterface\n" );
	
	if(thisInstance == NULL)
		return E_NOINTERFACE;

    // Create a CoreFoundation UUIDRef for the requested interface.
    CFObj<CFUUIDRef> interfaceID( ::CFUUIDCreateFromUUIDBytes( NULL, iid ) );
    if(interfaceID == NULL)
    	return E_NOINTERFACE;//unable to create UUID

	ACMPluginProxy *proxy = (ACMPluginProxy *)thisInstance;

    // Test the requested ID against the valid interfaces.
    if ( ::CFEqual( (CFUUIDRef)interfaceID, kContextualMenuInterfaceID) )
    {
        // If the kContextualMenuInterfaceID was requested, bump the ref count,
        // set the ppv parameter equal to the instance, and return good status.
        proxy->refCount++;
        *ppv = &(proxy->interface);
        return S_OK;
    }
    else if ( ::CFEqual( (CFUUIDRef)interfaceID, IUnknownUUID ) )
    {
        // If the IUnknown interface was requested, same as above.
        proxy->refCount++;
        *ppv = &(proxy->interface);
        return S_OK;
    }
    else
    {
        // Requested interface unknown, bail with error.
        *ppv = NULL;
        return E_NOINTERFACE;
    }
}


// -----------------------------------------------------------------------------
//	AbstractCMPluginAddRef
// -----------------------------------------------------------------------------
//	Implementation of reference counting for this type. Whenever an interface
//	is requested, bump the refCount for the instance. NOTE: returning the
//	refcount is a convention but is not required so don't rely on it.
//
UInt32 ACMPluginProxyAddRef( void *thisInstance )
{
	TRACE_CSTR( "ACMPluginProxyAddRef\n" );
	ACMPluginProxy *proxy = (ACMPluginProxy *)thisInstance;
	if(proxy != NULL)
		return proxy->refCount++;
	return 0;
}


// -----------------------------------------------------------------------------
//  AbstractCMPluginRelease
// -----------------------------------------------------------------------------
//	When an interface is released, decrement the refCount.
//	If the refCount goes to zero, deallocate the instance.
//
UInt32 ACMPluginProxyRelease( void *thisInstance )
{
	TRACE_CSTR( "ACMPluginProxyRelease\n" );
	ACMPluginProxy *proxy = (ACMPluginProxy *)thisInstance;
	if(proxy != NULL)
	{
		if(proxy->refCount > 0)
			proxy->refCount--;
		if(proxy->refCount == 0)
		{
			::CFPlugInRemoveInstanceForFactory( kCMPluginFactoryID );
			delete proxy; //plugin will get Release() message in proxy destructor
		}
	}
	return 0;
}


OSStatus ACMPluginProxyExamineContext(
					  void *          thisInstance,
					  const AEDesc *  inContext,
					  AEDescList *    outCommandPairs)
{
	TRACE_CSTR( "ACMPluginExamineContext\n" );
	OSStatus err = noErr;
	ACMPluginProxy *proxy = (ACMPluginProxy *)thisInstance;

	try
	{
		if( proxy != NULL )
		{
			proxy->plugin.Adopt( CreateNewCMPlugin(), kARefCountDontRetain );//the real plugin object creation, supplied by user
			err = proxy->plugin->ExamineContext(inContext, outCommandPairs);
		}
	}
	catch(...)
	{
		err = paramErr;
	}

	//when error is returned, the cleanup is not called? anyway, clean up right away
	if( (err != noErr) && ( proxy != NULL ) && (proxy->plugin != NULL) )
		proxy->plugin.Adopt(NULL);
		
	return err;
}

OSStatus ACMPluginProxyHandleSelection(
					  void *    thisInstance,
					  AEDesc *  inContext,
					  SInt32    inCommandID)
{
	TRACE_CSTR( "ACMPluginExamineContext\n" );
	try
	{
		ACMPluginProxy *proxy = (ACMPluginProxy *)thisInstance;
		if( (proxy != NULL) && (proxy->plugin != NULL) ) 
			return proxy->plugin->HandleSelection(inContext, inCommandID);
	}
	catch(...)
	{
	
	}
	return paramErr;
}

void 
ACMPluginProxyPostMenuCleanup(void *thisInstance)
{
	TRACE_CSTR( "ACMPluginExamineContext\n" );
	try
	{
		ACMPluginProxy *proxy = (ACMPluginProxy *)thisInstance;
		if( (proxy != NULL) && (proxy->plugin != NULL) )
		{
			proxy->plugin->PostMenuCleanup();
			proxy->plugin.Adopt(NULL);
		}
	}
	catch(...)
	{
	
	}
}


//**************************************************************************************
// Filename:	ACMPlugin.h
//				Part of Abracode Workshop
//
// Description:	Base code for CM plugin taking care of COM interface and communication with a host.
//				Not needed to be modified in most cases.
//				
// Usage:		see Documentation.txt
//						
//**************************************************************************************


#ifndef __ACMPlugin__
#define __ACMPlugin__

#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include "ARefCounted.h"
#include "CFObj.h"

class ACMPlugin : public ARefCounted
{
public:
	
	ACMPlugin(CFStringRef inBundleID);
	virtual ~ACMPlugin();

	virtual OSStatus		ExamineContext( const AEDesc *inContext, AEDescList *outCommandPairs ) = 0;
	virtual OSStatus		HandleSelection( AEDesc *inContext, SInt32 inCommandID ) = 0;
	virtual void			PostMenuCleanup() = 0;
	virtual CFBundleRef		GetBundleRef() const { return mBundleRef; }
protected:
	CFObj<CFBundleRef>		mBundleRef;
};

//plugin should implement this method and return a new object inherited from ACMPlugin
ACMPlugin *CreateNewCMPlugin();
extern CFUUIDRef kCMPluginFactoryID; //client provides this symbol with unique ID

#endif //__ACMPlugin__

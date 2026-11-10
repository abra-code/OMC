//
//  OMCEngineBundle.cpp
//  Abracode
//
//  The macOS implementation of Platform/OMCEngineBundle.h: Abracode.framework is loaded by dyld,
//  so CoreFoundation finds it by its bundle identifier.
//

#include "OMCEngineBundle.h"
#include "CFObj.h"
#include <dispatch/dispatch.h>

static CFObj<CFBundleRef> sEngineBundle;

CFBundleRef
OMCGetEngineBundle(void)
{
	static dispatch_once_t sOnce;
	dispatch_once_f(&sOnce, nullptr, [](void *) {
		// A Get: CoreFoundation owns it; retained for the life of the process
		sEngineBundle.Adopt(CFBundleGetBundleWithIdentifier(CFSTR(OMC_ENGINE_BUNDLE_IDENTIFIER)), kCFObjRetain);
	});
	return sEngineBundle;
}

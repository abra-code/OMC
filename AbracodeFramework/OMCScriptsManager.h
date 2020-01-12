/*
 *  OMCScriptsManager.h
 */

#pragma once

#ifdef __cplusplus

#include "CFObj.h"

class OMCScriptsManager
{
public:

	static OMCScriptsManager* GetScriptsManager();

	OMCScriptsManager();
	~OMCScriptsManager() { }

	CFStringRef GetScriptPath(CFBundleRef inBundle, CFStringRef inScriptName);

private:
	CFMutableDictionaryRef CreateScriptsCacheForBundle(CFBundleRef inBundle);

private:
	CFObj<CFMutableDictionaryRef> mBundles; //key:bundle, value:dict of name/path pairs
};

#endif //__cplusplus

#ifdef __cplusplus
extern "C" {
#endif

CFStringRef OMCGetScriptPath(CFBundleRef inBundle, CFStringRef inScriptName);

#ifdef __cplusplus
}
#endif


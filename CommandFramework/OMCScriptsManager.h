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

	// Returns the full name to path dictionary for the bundle, building the cache if needed.
	// Keys are lowercase script names without extension; values are absolute POSIX path strings.
	// The returned dictionary is owned by the singleton — do NOT release it.
	CFDictionaryRef GetAllScriptPaths(CFBundleRef inBundle);

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


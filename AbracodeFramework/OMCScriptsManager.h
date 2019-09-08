/*
 *  OMCScriptsManager.h
 */

#pragma once
#include "CFObj.h"

class OMCScriptsManager
{
public:

	OMCScriptsManager();
	~OMCScriptsManager() { }

	CFStringRef GetScriptPath(CFBundleRef inBundle, CFStringRef inScriptName);

private:
	CFMutableDictionaryRef CreateScriptsCacheForBundle(CFBundleRef inBundle);

private:
	CFObj<CFMutableDictionaryRef> mBundles; //key:bundle, value:dict of name/path pairs
};

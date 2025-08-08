/*
 *  OMCScriptsManager.cpp
 */
 
#include "OMCScriptsManager.h"
#include "OMCStrings.h"

OMCScriptsManager*
OMCScriptsManager::GetScriptsManager()
{
	static OMCScriptsManager* sScriptsManager = new OMCScriptsManager();
	return sScriptsManager;
}

CFStringRef OMCGetScriptPath(CFBundleRef inBundle, CFStringRef inScriptName)
{
	return OMCScriptsManager::GetScriptsManager()->GetScriptPath(inBundle, inScriptName);
}


OMCScriptsManager::OMCScriptsManager()
	: mBundles(CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks))
{
}

CFStringRef
OMCScriptsManager::GetScriptPath(CFBundleRef inBundle, CFStringRef inScriptName)
{
	if((inBundle == nullptr) || (inScriptName == nullptr))
		return nullptr;

	CFMutableDictionaryRef scriptsDict = (CFMutableDictionaryRef)CFDictionaryGetValue(mBundles, inBundle);
	if(scriptsDict == nullptr)
	{//this bundle was never queried before: create a new entry and search for files
		CFObj<CFMutableDictionaryRef> newScriptsDict = CreateScriptsCacheForBundle(inBundle);
		CFDictionaryAddValue(mBundles, inBundle, newScriptsDict);
		scriptsDict = newScriptsDict;
	}
	
	CFObj<CFStringRef> scriptNameLowercase = CreateLowercaseString(inScriptName);
	CFStringRef outScriptPath = (CFStringRef)CFDictionaryGetValue(scriptsDict, scriptNameLowercase);
	return outScriptPath;
}

// Find all files in "Scripts" dir in the bundle and create a dictionary of {script_name: script_file_path}
// where script_name is a file name without extension and normalized to lowercase
// and script_file_path is an absolute POSIX path to the corresponding script file

CFMutableDictionaryRef
OMCScriptsManager::CreateScriptsCacheForBundle(CFBundleRef inBundle)
{
	CFObj<CFMutableDictionaryRef> newScriptsDict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFObj<CFArrayRef> allScriptURLs = CFBundleCopyResourceURLsOfType(inBundle, nullptr, CFSTR("Scripts"));
	if(allScriptURLs == nullptr)
		return newScriptsDict.Detach();

	CFIndex scriptCount = CFArrayGetCount(allScriptURLs);
	for(CFIndex i = 0; i < scriptCount; i++)
	{
		CFURLRef oneScriptURL = (CFURLRef)CFArrayGetValueAtIndex(allScriptURLs, i); //cannot be null
		CFObj<CFURLRef> scriptNoExtURL = CFURLCreateCopyDeletingPathExtension(kCFAllocatorDefault, oneScriptURL);
		if(scriptNoExtURL == nullptr)
			continue; //should not happen, but...

		CFObj<CFStringRef> scriptNameNoExt = CFURLCopyLastPathComponent(scriptNoExtURL);
		CFObj<CFStringRef> scriptNameNoExtLowercase = CreateLowercaseString(scriptNameNoExt); //null-safe
		if(scriptNameNoExt == nullptr)
			continue; //should not happen, but...

		CFObj<CFURLRef> absoluteURL(CFURLCopyAbsoluteURL(oneScriptURL));
		if(absoluteURL == nullptr)
			continue; //should not happen, but...

		CFObj<CFStringRef> absoluteScriptPath = CFURLCopyFileSystemPath(absoluteURL, kCFURLPOSIXPathStyle);
		if(absoluteScriptPath == nullptr)
			continue; //should not happen, but...

		CFDictionaryAddValue(newScriptsDict, scriptNameNoExtLowercase, absoluteScriptPath);
	}

	return newScriptsDict.Detach();
}


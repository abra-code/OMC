//
//  OMCEngineBundle.cpp (Linux)
//  Abracode
//
//  The Linux implementation of Platform/OMCEngineBundle.h. Not built yet: the Linux port has no
//  build. CoreFoundation on Linux knows only the main bundle and the bundles created (it has no
//  dyld to find loaded frameworks), so the engine creates its framework's bundle once; lookups by
//  identifier find it afterwards. Probed: ~/git/AppleCoreLibrariesForLinux/build/probe/
//  cfbundle-framework/REPORT.md.
//
//  - The engine is libAbracode.so: the folder holding it, up to the one named *.framework
//    (a flat framework, or Versions/A in a versioned one), found with dladdr on the engine's code.
//  - The engine is linked into the applet's executable: the applet's
//    Frameworks/Abracode.framework, which then holds only resources and support tools.
//

#include "OMCEngineBundle.h"
#include "CFObj.h"
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <string>

static CFObj<CFBundleRef> sEngineBundle;

// The *.framework folder at or above the folder holding `inPath`, empty when there is none
static std::string
FrameworkFolderAbove(const char *inPath)
{
	std::string path(inPath);
	std::string::size_type slash = path.rfind('/');
	while(slash != std::string::npos && slash > 0)
	{
		path.resize(slash);
		std::string::size_type nameStart = path.rfind('/');
		std::string name = path.substr((nameStart == std::string::npos) ? 0 : nameStart + 1);
		const std::string suffix(".framework");
		if((name.size() > suffix.size()) && (name.compare(name.size() - suffix.size(), suffix.size(), suffix) == 0))
			return path;
		slash = nameStart;
	}
	return std::string();
}

// The bundle at `inURL` when it is Abracode.framework (by its identifier), else NULL: a framework
// found above the engine's code may be another one (the engine linked into some other framework's
// executable)
static CFBundleRef
CreateEngineBundleAtURL(CFURLRef inURL)
{
	if(inURL == nullptr)
		return nullptr;
	CFObj<CFBundleRef> bundle( CFBundleCreate(kCFAllocatorDefault, inURL) );
	if(bundle == nullptr)
		return nullptr;
	CFStringRef identifier = CFBundleGetIdentifier(bundle);
	if((identifier == nullptr) || (CFStringCompare(identifier, CFSTR(OMC_ENGINE_BUNDLE_IDENTIFIER), 0) != kCFCompareEqualTo))
		return nullptr;
	return bundle.Detach();
}

static CFBundleRef
CreateEngineBundle()
{
	// The engine as a shared library: the framework around it
	Dl_info info = {};
	if((dladdr((const void *)&OMCGetEngineBundle, &info) != 0) && (info.dli_fname != nullptr))
	{
		std::string framework = FrameworkFolderAbove(info.dli_fname);
		if(!framework.empty())
		{
			CFObj<CFURLRef> url( CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault,
									(const UInt8 *)framework.c_str(), (CFIndex)framework.size(), true) );
			CFBundleRef bundle = CreateEngineBundleAtURL(url);
			if(bundle != nullptr)
				return bundle;
		}
	}

	// The engine linked into the applet (or the framework above was not the engine's): the
	// applet's Frameworks/Abracode.framework
	CFBundleRef mainBundle = CFBundleGetMainBundle();
	if(mainBundle == nullptr)
		return nullptr;
	CFObj<CFURLRef> frameworks( CFBundleCopyPrivateFrameworksURL(mainBundle) );
	if(frameworks == nullptr)
		return nullptr;
	CFObj<CFURLRef> framework( CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, frameworks,
								CFSTR("Abracode.framework"), true) );
	return CreateEngineBundleAtURL(framework);
}

CFBundleRef
OMCGetEngineBundle(void)
{
	static dispatch_once_t sOnce;
	dispatch_once_f(&sOnce, nullptr, [](void *) {
		sEngineBundle.Adopt(CreateEngineBundle()); // a Create: owned here for the life of the process
	});
	return sEngineBundle;
}

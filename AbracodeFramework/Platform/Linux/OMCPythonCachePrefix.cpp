//
//  OMCPythonCachePrefix.cpp (Linux)
//  Abracode
//
//  The Linux OMCGetPythonPycachePrefix (OMCPrivateConstants.h); the macOS one is in
//  Platform/Apple/OMCAppLifecycleObserver.mm. Not built yet: the Linux port has no build.
//
//  <cache>/omc/Pyc, where <cache> is $XDG_CACHE_HOME or ~/.cache, the folder XDG gives for data
//  that may be deleted and made again, as macOS's per-user temporary folder is. Not
//  $XDG_RUNTIME_DIR: it is memory, limited in size and emptied at logout, and bytecode is
//  neither small nor worth losing. The engine's <cache>/omc folder is used only when it is
//  private and on a path no other user can change (OMCPlatformEngineCacheDir), because what
//  collects here is bytecode the interpreter runs after checking only its source's time and size
//  (see the header); Python makes Pyc and the folders under it itself.
//

#include "OMCPrivateConstants.h"
#include "OMCUserTempDirPlatform.h"
#include <limits.h>
#include <string.h>
#include <string>

// Worked out once, on the first call from any thread (a C++ static is made once, safely). Never
// freed, as on macOS: a static std::string would be destroyed at exit while other threads may
// still use it, and the header promises the string for the life of the process.
const char *OMCGetPythonPycachePrefix(void)
{
	static const char *const sPycachePrefix = []() -> const char *
	{
		char engineCacheDir[PATH_MAX];
		if(!OMCPlatformEngineCacheDir(engineCacheDir, sizeof(engineCacheDir)))
			return nullptr;
		std::string prefix = std::string(engineCacheDir) + "/Pyc";
		return ::strdup(prefix.c_str());
	}();
	return sPycachePrefix;
}

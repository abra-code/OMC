/*
 *  OMCEnvironmentExportScript.cpp
 */
 
#include "OMCEnvironmentExportScript.h"
#include "OMCConstants.h"
#include "OMCStrings.h"
#include "CFObj.h"
#include "ACFType.h"
#include <vector>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>   // confstr
#include <fcntl.h>    // open, O_NOFOLLOW
#include <errno.h>
#include <limits.h>   // PATH_MAX

/* The content of environment variable exports script:
for .sh family of shells:
 export OMC_FOO='omc foo'
 /bin/unlink "$TMPDIR/omc_environment_setup_123456789.sh"

for .csh and .tcsh shells
 setenv OMC_FOO 'omc foo'
 /bin/unlink "$TMPDIR/omc_environment_setup_123456789.csh"

 */

static inline CFStringRef CreateEnvironmentExportScript(CFDictionaryRef inEnvironmentDict, CFStringRef scriptPath, bool isSh)
{
	if(inEnvironmentDict == nullptr)
		return nullptr;
		
	CFIndex itemCount = CFDictionaryGetCount(inEnvironmentDict);
	if(itemCount == 0)
		return nullptr;
	
	std::vector<CFTypeRef> keyList(itemCount);
	std::vector<CFTypeRef> valueList(itemCount);
	CFDictionaryGetKeysAndValues(inEnvironmentDict, (const void **)keyList.data(), (const void **)valueList.data());

	CFObj<CFMutableStringRef> scriptContent = CFStringCreateMutable(kCFAllocatorDefault, 0);

	for(CFIndex i = 0; i < itemCount; i++)
	{
		CFStringRef theKey = ACFType<CFStringRef>::DynamicCast( keyList[i] );
		CFStringRef theValue = ACFType<CFStringRef>::DynamicCast( valueList[i] );
		if((theKey != nullptr) && (theValue != nullptr))
		{
			CFObj<CFStringRef> quotedValue = CreateEscapedStringCopy(theValue, kEscapeWrapWithSingleQuotesForShell);
			CFObj<CFStringRef> oneExport;
			if(isSh)
			{
				oneExport.Adopt(CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("export %@=%@\n"), theKey, (CFStringRef)quotedValue));
			}
			else
			{
				oneExport.Adopt(CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("setenv %@ %@\n"), theKey, (CFStringRef)quotedValue));
			}
			CFStringAppend(scriptContent, oneExport);
		}
	}

	CFObj<CFStringRef> unlinkCommand = CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("/bin/unlink \"%@\"\n"), scriptPath);
	CFStringAppend(scriptContent, unlinkCommand);

	return scriptContent.Detach();
}

// Returns the per-user temporary directory (mode 0700, e.g. /var/folders/.../T/), which
// is private to the current user - unlike the world-accessible /tmp. Falls back to
// $TMPDIR then /tmp/ if the platform call is unavailable. The result always ends with '/'.
static CFStringRef CreatePerUserTempDir()
{
	char buf[PATH_MAX];
	size_t n = confstr(_CS_DARWIN_USER_TEMP_DIR, buf, sizeof(buf));
	const char *dir = nullptr;
	if((n > 0) && (n <= sizeof(buf)))
		dir = buf; // confstr guarantees a trailing '/'
	else
	{
		dir = getenv("TMPDIR");
		if((dir == nullptr) || (dir[0] == '\0'))
			dir = "/tmp/";
	}
	return CFStringCreateWithCString(kCFAllocatorDefault, dir, kCFStringEncodingUTF8);
}

// Builds the path of the environment-setup script. Both the writer
// (WriteEnvironmentSetupScriptToTmp) and the shell command generator
// (CreateEnvironmentSetupCommandForShell) must agree on this exact path.
static CFStringRef CreateEnvironmentSetupScriptPath(CFStringRef inCommandGUID, bool isSh)
{
	CFStringRef ext = isSh ? CFSTR("sh") : CFSTR("csh");
	CFObj<CFStringRef> tempDir(CreatePerUserTempDir());
	Boolean hasSlash = (tempDir != nullptr) && CFStringHasSuffix(tempDir, CFSTR("/"));
	return CFStringCreateWithFormat(kCFAllocatorDefault, nullptr,
									hasSlash ? CFSTR("%@omc_environment_setup_%@.%@")
											 : CFSTR("%@/omc_environment_setup_%@.%@"),
									(CFStringRef)tempDir, inCommandGUID, ext);
}

// Writes the script with O_CREAT|O_TRUNC|O_NOFOLLOW and mode 0600. O_NOFOLLOW refuses to
// follow a symlink planted at the final path (defense in depth - the per-user temp dir is
// already inaccessible to other users), and 0600 keeps the file private. This replaces the
// previous WriteStringToFile (NSString writeToFile), which follows symlinks.
static bool WriteScriptFileSecurely(CFStringRef inContent, CFStringRef inPath)
{
	if((inContent == nullptr) || (inPath == nullptr))
		return false;

	char pathBuf[PATH_MAX];
	if(!CFStringGetFileSystemRepresentation(inPath, pathBuf, sizeof(pathBuf)))
		return false;

	int fd = open(pathBuf, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600);
	if(fd < 0)
		return false;

	bool ok = false;
	CFIndex contentLen = CFStringGetLength(inContent);
	CFIndex maxBytes = CFStringGetMaximumSizeForEncoding(contentLen, kCFStringEncodingUTF8);
	char *bytes = (char *)malloc((size_t)maxBytes + 1);
	if(bytes != nullptr)
	{
		CFIndex usedLen = 0;
		CFStringGetBytes(inContent, CFRangeMake(0, contentLen), kCFStringEncodingUTF8,
						 0, false, (UInt8 *)bytes, maxBytes, &usedLen);
		ssize_t totalWritten = 0;
		ok = true;
		while(totalWritten < usedLen)
		{
			ssize_t w = write(fd, bytes + totalWritten, (size_t)(usedLen - totalWritten));
			if(w <= 0)
			{
				if((w < 0) && (errno == EINTR))
					continue;
				ok = false;
				break;
			}
			totalWritten += w;
		}
		free(bytes);
	}

	close(fd);
	return ok;
}

bool
WriteEnvironmentSetupScriptToTmp(CFDictionaryRef inEnvironmentDict, CFStringRef inCommandGUID, bool isSh)
{
	CFObj<CFStringRef> scriptPath(CreateEnvironmentSetupScriptPath(inCommandGUID, isSh));

	CFObj<CFStringRef> scriptContent = CreateEnvironmentExportScript(inEnvironmentDict, scriptPath, isSh);
	return WriteScriptFileSecurely(scriptContent, scriptPath);
}

/* Invocation command to source the script at the beginning of terminal session
for .sh family of shells:
 . "$TMPDIR/omc_environment_setup_123456789.sh"

for .csh and .tcsh shells
 source "$TMPDIR/omc_environment_setup_123456789.csh"

 */

CFStringRef CreateEnvironmentSetupCommandForShell(CFStringRef inCommandGUID, bool isSh)
{
	// "." command works in most shells
	// dash does not have a 'source' command but works with "."
	// in csh and tcsh "." command if failing for me with unaccessible PATH dir while 'source' is working
	CFStringRef sourceCmd = isSh ? CFSTR(".") : CFSTR("source");
	// Must match the path used by WriteEnvironmentSetupScriptToTmp exactly.
	CFObj<CFStringRef> scriptPath(CreateEnvironmentSetupScriptPath(inCommandGUID, isSh));
	return CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("%@ \"%@\"\n"), sourceCmd, (CFStringRef)scriptPath);
}

bool IsShDefaultLoginShell()
{
	char *shellEnv = getenv("SHELL");
	if(shellEnv != nullptr)
	{
		char *foundPtr = strstr(shellEnv, "csh"); //only csh or tcsh need different treatment
		return (foundPtr == nullptr);
	}
	return true;
}



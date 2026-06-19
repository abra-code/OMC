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

static inline bool IsShDefaultLoginShell()
{
	char *shellEnv = getenv("SHELL");
	if(shellEnv != nullptr)
	{
		char *foundPtr = strstr(shellEnv, "csh"); //only csh or tcsh need different treatment
		return (foundPtr == nullptr);
	}
	return true;
}

// It is reasonable to check default shell only once during the lifetime of the process.
// If the user changes Terminal or iTerm shell while an OMC applet is running
// the change would go unnoticed. Sorry, we will not pay the price of hitting this code every time
// to cover the corner case which has an easy workaround (restart the darn app)
// Save the cycles, save the energy, save the Earth...

bool IsShDefaultInTerminal()
{
	static bool sIsShDefault = true;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		CFObj<CFTypeRef> resultRef( ::CFPreferencesCopyAppValue(CFSTR("Shell"), CFSTR("com.apple.Terminal")) );
		CFStringRef shellPath = ACFType<CFStringRef>::DynamicCast(resultRef);
		if((shellPath != nullptr) && (CFStringGetLength(shellPath) > 0))
		{
			//all shells but csh or tcsh are behaving the same for OMC environment export purposes
			CFRange foundRange = ::CFStringFind(shellPath, CFSTR("csh"), 0);
			sIsShDefault = (foundRange.location == kCFNotFound);
		}
		else
		{
			sIsShDefault = IsShDefaultLoginShell();
		}
	});

	return sIsShDefault;
}

/*
   Looking at  com.googlecode.iterm2.plist:

   more complex structure with multiple profiles named "bookmarks"
   the default one is identified by GUID in root level
   the shell is named "command"
   even if "command" is set, its activation is controlled by "Custom Command" string
   
<key>Default Bookmark Guid</key>
<string>6777374D-5516-4559-907C-F1A309BA889D</string>

<key>New Bookmarks</key>
<array>
	<dict>

		<key>Command</key>
		<string>/bin/tcsh</string>

		<key>Custom Command</key>
		<string>No</string>

		<key>Guid</key>
		<string>6777374D-5516-4559-907C-F1A309BA889D</string>

*/

bool IsShDefaultInITem()
{
	static bool sIsShDefault = true;
	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		CFObj<CFTypeRef> profileArrayRef = CFPreferencesCopyAppValue(CFSTR("New Bookmarks"), CFSTR("com.googlecode.iterm2"));
		CFArrayRef profileArray = ACFType<CFArrayRef>::DynamicCast(profileArrayRef);
		CFDictionaryRef foundDefaultProfile = nullptr;
		CFIndex profileCount = 0;

		if(profileArray != nullptr)
			profileCount = CFArrayGetCount(profileArray);

		if(profileCount == 1)
		{
			foundDefaultProfile = ACFType<CFDictionaryRef>::DynamicCast(CFArrayGetValueAtIndex(profileArray, 0));
		}
		else if(profileCount > 1)
		{
			CFObj<CFTypeRef> defaultProfileGuidRef = CFPreferencesCopyAppValue(CFSTR("Default Bookmark Guid"), CFSTR("com.googlecode.iterm2"));
			CFStringRef defaultProfileGuid = ACFType<CFStringRef>::DynamicCast(defaultProfileGuidRef);
			for(CFIndex i = 0; i < profileCount; i++)
			{
				CFDictionaryRef oneProfile = ACFType<CFDictionaryRef>::DynamicCast(CFArrayGetValueAtIndex(profileArray, i));
				if(oneProfile != nullptr)
				{
					CFStringRef oneGuid = ACFType<CFStringRef>::DynamicCast(CFDictionaryGetValue(oneProfile, CFSTR("Guid")));
					if((oneGuid != nullptr) && (kCFCompareEqualTo == CFStringCompare(oneGuid, defaultProfileGuid, kCFCompareCaseInsensitive)))
					{
						foundDefaultProfile = oneProfile;
					}
				}
			}
		}
		
		bool customShellFound = false;
		if(foundDefaultProfile != nullptr)
		{
			CFStringRef isCustomStr = ACFType<CFStringRef>::DynamicCast(CFDictionaryGetValue(foundDefaultProfile, CFSTR("Custom Command")));
			if((isCustomStr != nullptr) && (kCFCompareEqualTo == CFStringCompare(isCustomStr, CFSTR("Yes"), kCFCompareCaseInsensitive)))
			{
				CFStringRef shellPath = ACFType<CFStringRef>::DynamicCast(CFDictionaryGetValue(foundDefaultProfile, CFSTR("Command")));
				if((shellPath != nullptr) && (CFStringGetLength(shellPath) > 0))
				{
					//all shells but csh or tcsh are behaving the same for OMC environment export purposes
					CFRange foundRange = ::CFStringFind(shellPath, CFSTR("csh"), 0);
					sIsShDefault = (foundRange.location == kCFNotFound);
					customShellFound = true;
				}
			}
		}
		
		if(!customShellFound)
			sIsShDefault = IsShDefaultLoginShell();
	});

	return sIsShDefault;
}

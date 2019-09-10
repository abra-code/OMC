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

/* The content of environment variable exports script:
for .sh family of shells:
 export OMC_FOO='omc foo'
 /bin/unlink "/tmp/omc_environment_setup_123456789.sh"

for .csh and .tcsh shells
 setenv OMC_FOO 'omc foo'
 /bin/unlink "/tmp/omc_environment_setup_123456789.csh"

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

bool
WriteEnvironmentSetupScriptToTmp(CFDictionaryRef inEnvironmentDict, CFStringRef inCommandGUID, bool isSh)
{
	CFStringRef ext = isSh ? CFSTR("sh") : CFSTR("csh");
	CFObj<CFStringRef> scriptPath = CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("/tmp/omc_environment_setup_%@.%@"), inCommandGUID, ext);

	CFObj<CFStringRef> scriptContent = CreateEnvironmentExportScript(inEnvironmentDict, scriptPath, isSh);
	return WriteStringToFile(scriptContent, scriptPath);
}

/* Invocation command to source the script at the beginning of terminal session
for .sh family of shells:
 . "/tmp/omc_environment_setup_123456789.sh"

for .csh and .tcsh shells
 source "/tmp/omc_environment_setup_123456789.csh"

 */

CFStringRef CreateEnvironmentSetupCommandForShell(CFStringRef inCommandGUID, bool isSh)
{
	CFStringRef ext = isSh ? CFSTR("sh") : CFSTR("csh");
	// "." command works in most shells
	// dash does not have a 'source' command but works with "."
	// in csh and tcsh "." command if failing for me with unaccessible PATH dir while 'source' is working
	CFStringRef sourceCmd = isSh ? CFSTR(".") : CFSTR("source");
	return CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("%@ \"/tmp/omc_environment_setup_%@.%@\"\n"), sourceCmd, inCommandGUID, ext);
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

		if(profileArray == nullptr)
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

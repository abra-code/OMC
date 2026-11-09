//
//  OMCCommandRunner.cpp
//  Abracode
//
//  See OMCCommandRunner.h. Moved from OMCCommandExecutor.mm, statement for statement; only the
//  Foundation calls changed (NSString, NSURL, NSBundle, NSFileManager, NSLog, NSMutableDictionary).
//

#include "OMCCommandRunner.h"
#include "OMCFilePanels.h"
#include "OMCNavigationDialogs.h"
#include "OMCStrings.h"
#include "OMCLog.h"
#include "ACFPath.h"
#include "ACFPropertyList.h"
#include "CFObj.h"
#include <sys/stat.h>

namespace
{

// The command files read so far, by absolute URL string; they stay for the life of the process.
CFMutableDictionaryRef sCachedPlists = nullptr;

bool
IsFileOrFolderActivation(UInt32 activationType)
{
	return ((activationType == kActiveFile) ||
			(activationType == kActiveFolder) ||
			(activationType == kActiveFileOrFolder) ||
			(activationType == kActiveFinderWindow) ||
			(activationType == kActiveFolderExcludeFinderWindow) ||
			(activationType == kActiveFileOrFolderExcludeFinderWindow));
}

bool
IsEqualIgnoringCase(CFStringRef inString, CFStringRef inOther)
{
	return (inString != nullptr) && (::CFStringCompare(inString, inOther, kCFCompareCaseInsensitive) == kCFCompareEqualTo);
}

// As NSString's isAbsolutePath: a path that starts with "/" or "~".
bool
IsAbsolutePath(CFStringRef inPath)
{
	if((inPath == nullptr) || (::CFStringGetLength(inPath) == 0))
		return false;
	UniChar first = ::CFStringGetCharacterAtIndex(inPath, 0);
	return (first == '/') || (first == '~');
}

// What NSFileManager fileExistsAtPath: and NSURL fileURLWithPath: looked at: whether the path
// names something (symbolic links followed), and whether that is a folder.
bool
GetPathInfo(CFStringRef inPath, bool *outIsDirectory)
{
	*outIsDirectory = false;
	char path[PATH_MAX];
	if((inPath == nullptr) || !::CFStringGetFileSystemRepresentation(inPath, path, sizeof(path)))
		return false;
	struct stat info;
	if(::stat(path, &info) != 0)
		return false;
	*outIsDirectory = S_ISDIR(info.st_mode);
	return true;
}

// As NSURL fileURLWithPath: a file URL that ends with "/" when the path names a folder.
CFURLRef
CreateFileURL(CFStringRef inPath)
{
	bool isDirectory = false;
	(void)GetPathInfo(inPath, &isDirectory);
	return ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, inPath, kCFURLPOSIXPathStyle, isDirectory);
}

CFPropertyListRef
CachedPlistForURL(CFURLRef inURL)
{
	if(inURL == nullptr)
		return nullptr;

	CFObj<CFURLRef> absURL( ::CFURLCopyAbsoluteURL(inURL) );
	if(absURL == nullptr)
		return nullptr;

	CFStringRef key = ::CFURLGetString(absURL);
	if(sCachedPlists != nullptr)
	{
		CFPropertyListRef outPlist = (CFPropertyListRef)::CFDictionaryGetValue(sCachedPlists, key);
		if(outPlist != nullptr)
			return outPlist;
	}

	//not found, load it and cache
	CFObj<CFPropertyListRef> thePlist( CreatePropertyList(absURL, kCFPropertyListImmutable) );
	if(thePlist == nullptr)
		return nullptr;

	if(sCachedPlists == nullptr)
		sCachedPlists = ::CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

	::CFDictionarySetValue(sCachedPlists, key, thePlist);
	return thePlist;//the cache keeps it
}

CFPropertyListRef
CachedPlistForCommandFile(CFStringRef inFileName)
{
	CFObj<CFURLRef> commandURL( OMCCopyCommandFileURL(inFileName) );
	return CachedPlistForURL(commandURL);
}

} // namespace

CFURLRef
OMCCopyCommandFileURL(CFStringRef inFileName)
{
	if(inFileName == nullptr)
		return nullptr;

	CFObj<CFStringRef> expandedName( CreatePathByExpandingTilde(inFileName) );
	if(IsAbsolutePath(expandedName))
		return CreateFileURL(expandedName);

	// Relative name resolved in the app bundle; prefer Command.json over Command.plist.
	return CopyCommandFileURLInBundle(::CFBundleGetMainBundle(), inFileName);
}

//when inAllowNavDialog = true, missing file context is obtained from nav dialog
//otherwise when the file context is missing the command is not executed
//if USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT is false, the command always executes and no nav dialog is shown
OSStatus
OMCRunCommandFromFile(CFStringRef inCommandNameOrId, CFStringRef inCommandFile, CFTypeRef inContext,
						bool clientAllowsNavDialog, bool allowKeyWindowSubcommand,
						CFStringRef inTriggerURL, bool requireURLInvocable, const OMCRunHooks *inHooks)
{
	OSStatus error = userCanceledErr;//pessimistic scenario

	CFObj<CFURLRef> bundleURL;
	CFTypeRef commandFileRef = nullptr;
	CFObj<CFStringRef> ext( ACFPathCopyExtension(inCommandFile) );
	if((ext != nullptr) && (::CFStringCompare(ext, CFSTR("omc"), 0) == kCFCompareEqualTo))
	{
		bundleURL.Adopt( ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, inCommandFile, kCFURLPOSIXPathStyle, true) );
		commandFileRef = bundleURL;
	}
	else
	{
		commandFileRef = CachedPlistForCommandFile(inCommandFile);
	}

	OMCExecutorRef omcExec = OMCCreateExecutor( commandFileRef );
	if(omcExec != nullptr)
	{
		OMCCommandRef commandRef = OMCFindCommand( omcExec, inCommandNameOrId );
		if( requireURLInvocable )
		{
			// Fail closed: anything but an explicit "allowed" from the engine refuses the URL
			UInt32 urlInvocation = kOmcURLInvocation_RefusedNotOptedIn;
			const char *refusalReason = nullptr;
			if( !OMCIsValidCommandRef(commandRef) )
			{
				refusalReason = "the applet has no such command";
			}
			else if( (OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_URLInvocation, &urlInvocation) != noErr) ||
					 (urlInvocation != kOmcURLInvocation_Allowed) )
			{
				switch(urlInvocation)
				{
					case kOmcURLInvocation_RefusedLifecycleCommand:
						refusalReason = "an application lifecycle command is never run by a URL";
					break;

					case kOmcURLInvocation_RefusedDialogSubcommand:
						refusalReason = "a dialog event handler is never run by a URL";
					break;

					default:
						refusalReason = "the command does not set URL_INVOCABLE to true in the command description";
					break;
				}
			}

			if(refusalReason != nullptr)
			{
				// the id is the sender's: keep the log line short whatever was sent
				CFObj<CFStringRef> loggedID;
				if((inCommandNameOrId != nullptr) && (::CFStringGetLength(inCommandNameOrId) > 128))
					loggedID.Adopt( ::CFStringCreateWithSubstring(kCFAllocatorDefault, inCommandNameOrId, CFRangeMake(0, 128)) );
				else
					loggedID.Adopt( inCommandNameOrId, kCFObjRetain );
				OMCLogMessage("OMC: URL refused for command id \"%s\": %s", OMCLogCString(loggedID).c_str(), refusalReason);
				OMCReleaseExecutor(omcExec);
				return errAEEventNotPermitted;
			}
		}

		if( OMCIsValidCommandRef(commandRef) )
		{
			if(inTriggerURL != nullptr)
				OMCSetTriggerURL(omcExec, inTriggerURL);

			// If the key window is managed by an OMC window controller, dispatch the command
			// as a dialog subcommand so it inherits the window's dialog context and control values.
			// Exception: commands with OPEN_OBJECT_DIALOG need to run independently to show the open panel.
			if(allowKeyWindowSubcommand && (inHooks != nullptr) && (inHooks->dispatchToKeyWindow != nullptr))
			{
				CFDictionaryRef openDialogParams = nullptr;
				OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_OpenObjectDialogParams, &openDialogParams);
				if(openDialogParams == nullptr) // no open dialog: dispatch as window subcommand
				{
					if(inHooks->dispatchToKeyWindow(inHooks->context, inCommandNameOrId, inContext))
					{
						OMCReleaseExecutor(omcExec);
						return noErr;
					}
				}
			}

			error = noErr;

			// evaluate if we have a path object context for requested path OR file or folder activation
			bool hasFiles = false;
			if(inContext != nullptr)
			{
				CFTypeID contextType = ::CFGetTypeID(inContext);
				hasFiles = ((contextType == ::CFArrayGetTypeID()) || (contextType == ::CFURLGetTypeID()));
			}

			bool requiresNavDialog = false;
			UInt32 activationType = kActiveAlways;
			CFObj<CFArrayRef> selectedFiles;

			if(!hasFiles) // no file context provided. consider carefully whether the command needs files and allows displaying nav dialog
			{
				// does the command description allows using nav dialogs for missing file context (default = true, must be explicitly disallowed)
				UInt32 executionOptions = 0;
				OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_ExecutionOptions, &executionOptions);
				if((executionOptions & kExecutionOption_UseNavDialogForMissingFileContext) != 0)
				{
					// do we have file/dir objects referenced in command or declared in environment variables?
					UInt32 objectsInfo = kOmcCommandNoSpecialObjects;
					OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_CommandObjects, &objectsInfo);

					// does the command activation require file/dir?
					OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_ActivationType, &activationType);
					requiresNavDialog = ((objectsInfo & kOmcCommandContainsFileObject) != 0) || IsFileOrFolderActivation(activationType);
				}
			}

			if(requiresNavDialog && clientAllowsNavDialog) // all good to go with nav dialog
			{
				CFStringRef appName = (CFStringRef)::CFBundleGetValueForInfoDictionaryKey(::CFBundleGetMainBundle(), kCFBundleNameKey);
				if((appName == nullptr) || (::CFGetTypeID(appName) != ::CFStringGetTypeID()))
					appName = CFSTR("OMCApplet");

				// Check if the command has OPEN_OBJECT_DIALOG customization
				CFDictionaryRef openDialogParams = nullptr;
				OMCGetCommandInfo(omcExec, commandRef, kOmcInfo_OpenObjectDialogParams, &openDialogParams);

				CFObj<CFStringRef> dialogMessage;
				CFObj<CFArrayRef> dialogDefaultName;
				CFObj<CFArrayRef> dialogDefaultLocation;
				CFObj<CFStringRef> dialogIdentifier;
				CFObj<CFStringRef> dialogPrompt;
				CFObj<CFArrayRef> dialogAllowedContentTypes;
				UInt32 dialogFlags = 0;

				if(openDialogParams != nullptr)
				{
					dialogFlags = CopyNavDialogParams(openDialogParams, &dialogMessage, &dialogDefaultName, &dialogDefaultLocation, &dialogIdentifier, &dialogPrompt, &dialogAllowedContentTypes);
					dialogFlags &= ~kOMCFilePanelUseCachedPath; // not applicable to the startup open dialog
				}

				// Use first element of DEFAULT_LOCATION array as default directory path
				CFStringRef dialogDefaultDir = nullptr;
				if((dialogDefaultLocation != nullptr) && (::CFArrayGetCount(dialogDefaultLocation) > 0))
					dialogDefaultDir = (CFStringRef)::CFArrayGetValueAtIndex(dialogDefaultLocation, 0);

				if(dialogMessage == nullptr)
				{
					dialogMessage.Adopt( CFCopyLocalizedStringFromTable(CFSTR("Choose Objects To Process"), CFSTR("Localizable"), "") );
				}

				// If OPEN_OBJECT_DIALOG didn't set ALLOW_MULTIPLE_ITEMS, default to allowing multiple
				if(openDialogParams == nullptr)
					dialogFlags |= kOMCFilePanelAllowMultipleItems;

				switch(activationType)
				{
					case kActiveFile:
					{
						selectedFiles.Adopt( CreateCFURLsFromOpenDialog( appName, dialogMessage, nullptr, dialogDefaultDir, dialogIdentifier, dialogPrompt, dialogAllowedContentTypes, dialogFlags | kOMCFilePanelCanChooseFiles ) );
					}
					break;

					case kActiveFolder:
					case kActiveFinderWindow:
					case kActiveFolderExcludeFinderWindow:
					{
						selectedFiles.Adopt( CreateCFURLsFromOpenDialog( appName, dialogMessage, nullptr, dialogDefaultDir, dialogIdentifier, dialogPrompt, dialogAllowedContentTypes, dialogFlags | kOMCFilePanelCanChooseDirectories ) );
					}
					break;

					default:
					{
						selectedFiles.Adopt( CreateCFURLsFromOpenDialog( appName, dialogMessage, nullptr, dialogDefaultDir, dialogIdentifier, dialogPrompt, dialogAllowedContentTypes, dialogFlags | kOMCFilePanelCanChooseFiles | kOMCFilePanelCanChooseDirectories ) );
					}
					break;
				}

				error = (selectedFiles != nullptr) ? noErr : userCanceledErr;
			}
			else if(requiresNavDialog)
			{ // we don't have files, we need the nav dialog but command description explicitly disallows it
				error = userCanceledErr; // command will not execute if we don't specify files
			}

			if(error == noErr)
			{
				// Applet execution path: examine the context and prepare runtime data, but do not reject
				// the command when its ACTIVATION_MODE does not match the context (e.g. ACTIVATION_MODE=act_file
				// with USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT=false launched with no files). Activation matching
				// gating is a contextual-menu/service concern; here the command was invoked explicitly and must run.
				error = OMCExamineContext( omcExec, commandRef, (selectedFiles != nullptr) ? (CFTypeRef)selectedFiles.Get() : inContext, kOMCAllowContextMismatch );
			}

			if(selectedFiles != nullptr)
			{
				if((error == noErr) && (inHooks != nullptr) && (inHooks->noteRecentFiles != nullptr))
					inHooks->noteRecentFiles(inHooks->context, selectedFiles); // add to open recent

				selectedFiles.Release(); // not needed past this point, as before
			}

			if(error == noErr)
			{
				// Does the caller want to observe task execution?
				if((inHooks != nullptr) && (inHooks->createObserver != nullptr))
				{
					OMCObserverRef observer = inHooks->createObserver(inHooks->context);
					if(observer != nullptr)
					{
						OMCAddObserver(omcExec, observer);
						OMCReleaseObserver(observer); // the caller keeps its own reference
					}
				}

				error = OMCExecuteCommand( omcExec, commandRef );
				if(error != noErr)
				{
					OMCLogMessage("OMCRunCommand returned error = %d", (int)error);
				}
			}
		}

		OMCReleaseExecutor( omcExec ); // safe to release here. task lives on if execution is asynchronous
	}

	return error;
}

OSStatus
OMCRunCommandForURL(CFStringRef inURLString, bool inIsValidURL, CFStringRef inHost, CFArrayRef inQueryItems,
					CFStringRef inCommandFile, const OMCRunHooks *inHooks)
{
	if((inURLString == nullptr) || (::CFStringGetLength(inURLString) == 0))
		return paramErr;

	// The log lines below name the command id but never the whole URL: its text and file
	// values are the sender's and may be long or private.
	if(!inIsValidURL)
	{
		OMCLogMessage("OMC: URL refused: it is not a valid URL");
		return errAEEventNotPermitted;
	}

	bool isExecuteURL = IsEqualIgnoringCase(inHost, CFSTR("exe"));
	if(!isExecuteURL)
	{
		// Not an "exe" URL: the applet's own URL handler gets the whole URL as text, if it has one
		return OMCRunCommandFromFile(CFSTR("omc.app.handle-url"), inCommandFile, inURLString, false, false, inURLString, false, inHooks);
	}

	CFStringRef urlCommandID = nullptr;
	CFStringRef textContext = nullptr;
	CFObj<CFMutableArrayRef> fileList;

	CFIndex itemCount = (inQueryItems != nullptr) ? ::CFArrayGetCount(inQueryItems) : 0;
	for(CFIndex i = 0; i < itemCount; i++)
	{
		CFArrayRef oneItem = (CFArrayRef)::CFArrayGetValueAtIndex(inQueryItems, i);
		if((oneItem == nullptr) || (::CFGetTypeID(oneItem) != ::CFArrayGetTypeID()) || (::CFArrayGetCount(oneItem) != 2))
			continue;
		CFTypeRef key = ::CFArrayGetValueAtIndex(oneItem, 0);
		CFTypeRef value = ::CFArrayGetValueAtIndex(oneItem, 1);
		if((key == nullptr) || (value == nullptr) ||
		   (::CFGetTypeID(key) != ::CFStringGetTypeID()) || (::CFGetTypeID(value) != ::CFStringGetTypeID()))
			continue; // malformed query item without a value - skip it

		if(IsEqualIgnoringCase((CFStringRef)key, CFSTR("commandID")))
		{
			urlCommandID = (CFStringRef)value;
		}
		else if(IsEqualIgnoringCase((CFStringRef)key, CFSTR("text")))
		{
			textContext = (CFStringRef)value;
		}
		else if(IsEqualIgnoringCase((CFStringRef)key, CFSTR("file")))
		{
			// A relative path would resolve against the applet's working directory, which the
			// sender of the link has no business knowing or depending on. A path to nothing is
			// refused here rather than handed to a command that expects its context to exist.
			bool isDirectory = false;
			if(!IsAbsolutePath((CFStringRef)value) || !GetPathInfo((CFStringRef)value, &isDirectory))
			{
				OMCLogMessage("OMC: URL refused: a \"file\" value is not an absolute path of an existing item");
				return errAEEventNotPermitted;
			}

			if(fileList == nullptr) //lazy creator
				fileList.Adopt( ::CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks) );

			CFObj<CFURLRef> fileURL( CreateFileURL((CFStringRef)value) );
			if(fileURL != nullptr)
				::CFArrayAppendValue(fileList, fileURL);
		}
	}

	if((urlCommandID == nullptr) || (::CFStringGetLength(urlCommandID) == 0))
	{
		OMCLogMessage("OMC: URL refused: it does not name a command id");
		return errAEEventNotPermitted;
	}

	// we don't support both file and text contexts. files take precedence if someone specifies text too
	CFTypeRef urlContext = textContext;
	if((fileList != nullptr) && (::CFArrayGetCount(fileList) > 0))
		urlContext = fileList;

	return OMCRunCommandFromFile(urlCommandID, inCommandFile, urlContext, false, false, inURLString, true, inHooks);
}

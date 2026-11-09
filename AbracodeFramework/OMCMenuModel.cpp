//
//  OMCMenuModel.cpp
//  Abracode
//
//  See OMCMenuModel.h. The Commands menu's rules were PopulateCommandsMenu and
//  CreateSubmenuNameChain in OMCCommandMenu.mm, and the command an item runs was
//  -[OMCCommandMenu executeCommand:]; moved statement for statement, except where the header says.
//

#include "OMCMenuModel.h"
#include "OnMyCommand.h"
#include "CommandDescription.h"
#include "ARefCounted.h"
#include <utility>

namespace
{

// "/" for no SUBMENU_NAME or "..", else the name with a leading "/"
CFStringRef
CreateCommandsMenuSubmenuPath(CFStringRef inSubmenuName)
{
	CFStringRef rootMenuName = CFSTR("/");
	if(inSubmenuName == nullptr)
		return (CFStringRef)::CFRetain(rootMenuName);

	CFIndex subLen = ::CFStringGetLength(inSubmenuName);
	UniChar firstChar = 0;
	if(subLen > 0)
		firstChar = ::CFStringGetCharacterAtIndex(inSubmenuName, 0);

	//check for ".." which means root level
	if( (firstChar == (UniChar)'.') && (subLen == 2) && (::CFStringGetCharacterAtIndex(inSubmenuName, 1) == (UniChar)'.') )
		return (CFStringRef)::CFRetain(rootMenuName);

	if(firstChar != (UniChar)'/')
	{
		CFMutableStringRef newName = ::CFStringCreateMutable(kCFAllocatorDefault, 0);
		if(newName != nullptr)
		{
			::CFStringAppend(newName, CFSTR("/"));
			::CFStringAppend(newName, inSubmenuName);
			return newName;
		}
	}
	return (CFStringRef)::CFRetain(inSubmenuName);
}

bool
IsDotComponent(CFStringRef inName)
{
	return (::CFStringCompare(inName, CFSTR("."), 0) == kCFCompareEqualTo) ||
			(::CFStringCompare(inName, CFSTR(".."), 0) == kCFCompareEqualTo);
}

} // namespace

bool
OMCBuildCommandsMenuModel(CFURLRef inCommandFileURL, OMCMenuModel &outMenu) noexcept
{
	outMenu.items.clear();
	if(inCommandFileURL == nullptr)
		return false;

	ARefCountedObj<OnMyCommand> omcPlugin( new OnMyCommand(inCommandFileURL), kARefCountDontRetain );
	omcPlugin->Init();
	OSStatus error = omcPlugin->ExamineContext((CFTypeRef)nullptr, kOmcUnspecifiedCommand);//no context, all commands
	if(error != noErr)
		return false;

	CommandDescription *commandList = omcPlugin->GetCommandList();
	UInt32 commandCount = omcPlugin->GetCommandCount();
	if(commandList == nullptr)
	{
		omcPlugin->PostMenuCleanup();
		return true;
	}

	UInt32 oldCommandIndex = omcPlugin->GetCurrentCommandIndex();

	for(UInt32 i = 0; i < commandCount; i++)
	{
		CommandDescription &command = commandList[i];
		if(command.isSubcommand) //it is a subcommand, do not add to menu
			continue;

		if(command.disabled)
			continue;//disabled item, don't add it

		// As before: SetCurrentCommandIndex sets the index only when it is out of range
		// (OnMyCommand.h), so the localization bundle below is the current command's at the start
		omcPlugin->SetCurrentCommandIndex(i);

		CFBundleRef localizationBundle = nullptr;
		if(command.localizationTableName != nullptr)//client wants to be localized
		{
			localizationBundle = omcPlugin->GetCurrentCommandExternBundle();
			if(localizationBundle == nullptr)
				localizationBundle = ::CFBundleGetMainBundle();
		}

		OMCMenuItemEntry entry;
		entry.submenuPath.Adopt( CreateCommandsMenuSubmenuPath(command.submenuName) );
		entry.commandID.Adopt(command.commandID, kCFObjRetain);
		if(command.name != nullptr)
		{
			CFObj<CFStringRef> combinedName( ::CFStringCreateByCombiningStrings(kCFAllocatorDefault, command.name, CFSTR("")) );
			if( (combinedName != nullptr) && (command.localizationTableName != nullptr) )
				entry.name.Adopt( ::CFBundleCopyLocalizedString(localizationBundle, combinedName, combinedName, command.localizationTableName) );
			else
				entry.name.Swap(combinedName);
		}
		outMenu.items.push_back(std::move(entry));
	}

	omcPlugin->SetCurrentCommandIndex(oldCommandIndex);
	omcPlugin->PostMenuCleanup();//currently doing nothing, just for completeness
	return true;
}

std::vector<CFObj<CFStringRef>>
OMCCopySubmenuNames(CFStringRef inSubmenuPath)
{
	std::vector<CFObj<CFStringRef>> names;
	if(inSubmenuPath == nullptr)
		return names;

	CFObj<CFURLRef> submenuPath( ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, inSubmenuPath, kCFURLPOSIXPathStyle, true) );
	while(submenuPath != nullptr)
	{
		CFObj<CFStringRef> menuName( ::CFURLCopyLastPathComponent(submenuPath) );
		if( (menuName == nullptr) || (::CFStringGetLength(menuName) == 0) ||
			(::CFStringCompare(menuName, CFSTR("/"), 0) == kCFCompareEqualTo) ||
			IsDotComponent(menuName) )
		{
			break;
		}
		names.insert(names.begin(), menuName);
		submenuPath.Adopt( ::CFURLCreateCopyDeletingLastPathComponent(kCFAllocatorDefault, submenuPath) );
	}
	return names;
}

CFStringRef
OMCCommandsMenuItemCommandToRun(CFStringRef inCommandID, CFStringRef inName) noexcept
{
	if( (inCommandID == nullptr) || (::CFStringGetLength(inCommandID) == 0) ||
		(::CFStringCompare(inCommandID, kOMCTopCommandID, 0) == kCFCompareEqualTo) )
	{
		return inName;
	}
	return inCommandID;//unique ID for top command, let's use it instead of the name
}

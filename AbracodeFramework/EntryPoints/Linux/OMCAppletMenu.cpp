//
//  OMCAppletMenu.cpp
//  Abracode
//
//  See OMCAppletMenu.h. Linux only.
//

#include "OMCAppletMenu.h"
#include "OMCMenuModel.h"
#include "OMCCommandRunner.h"
#include "OMCActionUIWindow.h"
#include "OMCAppShell.h"
#include "OMCLog.h"
#include "ACFString.h"
#include "ACFJSON.h"
#include "CFObj.h"
#include "ActionUIC.h"
#include <initializer_list>
#include <map>
#include <memory>
#include <string>

namespace
{

// What a chosen item does: run a command (by id or name), or one of OMC's own items
struct MenuCommand
{
	enum class Kind { Command, MainCommand, Quit };
	Kind kind {Kind::Command};
	CFObj<CFStringRef> command;
};

struct MenuState
{
	CFObj<CFStringRef> commandFile;
	OMCAppletMenuActions actions {};
	std::map<std::string, MenuCommand> items; // by the action id OMC gave the item
	unsigned nextItemNumber {1};
};

MenuState *sMenu = nullptr; // made once, for the life of the app

const char *kNewActionID = "omc.menu.new";
const char *kOpenActionID = "omc.menu.open";
const char *kQuitActionID = "omc.menu.quit";

#pragma mark - Running

bool
DispatchToKeyWindow(void *inHookContext, CFStringRef inCommandNameOrId, CFTypeRef inContext)
{
	(void)inHookContext;
	// The key window, when it is an ActionUI command window (as OMCCommandExecutor.mm on macOS)
	std::shared_ptr<OMCActionUIWindow> keyWindow = OMCActionUIWindow::FindKeyWindow();
	if(keyWindow == nullptr)
		return false;
	keyWindow->DispatchCommand(inCommandNameOrId, inContext);
	return true;
}

void
NoteRecentFiles(void *inHookContext, CFArrayRef inFileURLs)
{
	(void)inHookContext;
	if(inFileURLs == nullptr)
		return;
	CFIndex count = CFArrayGetCount(inFileURLs);
	for(CFIndex i = 0; i < count; i++)
	{
		CFTypeRef item = CFArrayGetValueAtIndex(inFileURLs, i);
		if((item != nullptr) && (CFGetTypeID(item) == CFURLGetTypeID()))
			OMCNoteRecentDocument((CFURLRef)item);
	}
}

void
HandleMenuAction(const char *inActionID, const char *inWindowUUID, int64_t inViewID, int64_t inViewPartID, const char *inContextJSON)
{
	(void)inWindowUUID; (void)inViewID; (void)inViewPartID; (void)inContextJSON;
	if((sMenu == nullptr) || (inActionID == nullptr))
		return;
	auto found = sMenu->items.find(inActionID);
	if(found == sMenu->items.end())
		return;
	const MenuCommand &item = found->second;
	switch(item.kind)
	{
		case MenuCommand::Kind::MainCommand:
			if(sMenu->actions.runMainCommand != nullptr)
				sMenu->actions.runMainCommand(sMenu->actions.context);
			break;

		case MenuCommand::Kind::Quit:
			if(sMenu->actions.quit != nullptr)
				sMenu->actions.quit(sMenu->actions.context);
			break;

		case MenuCommand::Kind::Command:
		{
			// As the macOS menu runs it (OMCMainMenuController, OMCCommandMenu): the open panel for
			// missing files, and the key command window's subcommand when it has one by that id
			OMCRunHooks hooks = {};
			hooks.dispatchToKeyWindow = DispatchToKeyWindow;
			hooks.noteRecentFiles = NoteRecentFiles;
			hooks.context = nullptr;
			OSStatus err = OMCRunCommandFromFile(item.command, sMenu->commandFile, nullptr, true /*nav dialog*/, true /*key window*/,
												nullptr, false, &hooks);
			(void)err;
		}
		break;
	}
}

#pragma mark - The JSON

CFStringRef
StringValue(CFDictionaryRef inDictionary, CFStringRef inKey)
{
	CFTypeRef value = (inDictionary != nullptr) ? CFDictionaryGetValue(inDictionary, inKey) : nullptr;
	return ((value != nullptr) && (CFGetTypeID(value) == CFStringGetTypeID())) ? (CFStringRef)value : nullptr;
}

CFDictionaryRef
DictionaryValue(CFDictionaryRef inDictionary, CFStringRef inKey)
{
	CFTypeRef value = (inDictionary != nullptr) ? CFDictionaryGetValue(inDictionary, inKey) : nullptr;
	return ((value != nullptr) && (CFGetTypeID(value) == CFDictionaryGetTypeID())) ? (CFDictionaryRef)value : nullptr;
}

CFArrayRef
ArrayValue(CFDictionaryRef inDictionary, CFStringRef inKey)
{
	CFTypeRef value = (inDictionary != nullptr) ? CFDictionaryGetValue(inDictionary, inKey) : nullptr;
	return ((value != nullptr) && (CFGetTypeID(value) == CFArrayGetTypeID())) ? (CFArrayRef)value : nullptr;
}

// Whether a JSON value is true as macOS reads autoPopulate (NSNumber's boolValue): true, or a
// number other than 0
bool
IsTrueValue(CFTypeRef inValue)
{
	if(inValue == nullptr)
		return false;
	if(CFGetTypeID(inValue) == CFBooleanGetTypeID())
		return CFBooleanGetValue((CFBooleanRef)inValue);
	if(CFGetTypeID(inValue) == CFNumberGetTypeID())
	{
		double number = 0;
		(void)CFNumberGetValue((CFNumberRef)inValue, kCFNumberDoubleType, &number);
		return (number != 0);
	}
	return false;
}

bool
IsEqualString(CFStringRef inString, const char *inText)
{
	return (inString != nullptr) && (ACFStringToUTF8(inString) == inText);
}

// A new action id of OMC's own for an item that does inCommand
CFStringRef
CreateItemActionID(MenuCommand inCommand)
{
	std::string actionID = "omc.menu." + std::to_string(sMenu->nextItemNumber++);
	sMenu->items.emplace(actionID, std::move(inCommand));
	return CFStringCreateWithCString(kCFAllocatorDefault, actionID.c_str(), kCFStringEncodingUTF8);
}

CFMutableDictionaryRef
CreateMutableDictionary()
{
	return CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}

CFMutableArrayRef
CreateMutableArray()
{
	return CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
}

// {"type": "Button", "properties": {"title": inTitle, "actionID": inActionID, "keyboardShortcut": {"key": inKey}}}
CFDictionaryRef
CreateButton(CFStringRef inTitle, CFStringRef inActionID, CFStringRef inKey)
{
	CFObj<CFMutableDictionaryRef> properties(CreateMutableDictionary());
	CFDictionarySetValue(properties, CFSTR("title"), inTitle);
	CFDictionarySetValue(properties, CFSTR("actionID"), inActionID);
	if(inKey != nullptr)
	{
		CFObj<CFMutableDictionaryRef> shortcut(CreateMutableDictionary());
		CFDictionarySetValue(shortcut, CFSTR("key"), inKey); // Ctrl, as Command is on Linux
		CFDictionarySetValue(properties, CFSTR("keyboardShortcut"), shortcut);
	}
	CFMutableDictionaryRef button = CreateMutableDictionary();
	CFDictionarySetValue(button, CFSTR("type"), CFSTR("Button"));
	CFDictionarySetValue(button, CFSTR("properties"), properties);
	return button;
}

// {"type": "CommandGroup", "properties": {"placement": inPlacement, "placementTarget": inTarget}, "children": inChildren}
CFDictionaryRef
CreateCommandGroup(CFStringRef inPlacement, CFStringRef inTarget, CFArrayRef inChildren)
{
	CFObj<CFMutableDictionaryRef> properties(CreateMutableDictionary());
	CFDictionarySetValue(properties, CFSTR("placement"), inPlacement);
	CFDictionarySetValue(properties, CFSTR("placementTarget"), inTarget);
	CFMutableDictionaryRef group = CreateMutableDictionary();
	CFDictionarySetValue(group, CFSTR("type"), CFSTR("CommandGroup"));
	CFDictionarySetValue(group, CFSTR("properties"), properties);
	CFDictionarySetValue(group, CFSTR("children"), inChildren);
	return group;
}

// inChildren with every Button's actionID (a command id) replaced by an action id of OMC's own,
// nested Menus included
CFArrayRef
CreateChildrenWithOwnActions(CFArrayRef inChildren)
{
	CFMutableArrayRef children = CreateMutableArray();
	if(inChildren == nullptr)
		return children;
	CFIndex count = CFArrayGetCount(inChildren);
	for(CFIndex i = 0; i < count; i++)
	{
		CFTypeRef child = CFArrayGetValueAtIndex(inChildren, i);
		if((child == nullptr) || (CFGetTypeID(child) != CFDictionaryGetTypeID()))
			continue;
		CFDictionaryRef element = (CFDictionaryRef)child;
		CFStringRef type = StringValue(element, CFSTR("type"));
		CFDictionaryRef properties = DictionaryValue(element, CFSTR("properties"));
		CFStringRef commandID = StringValue(properties, CFSTR("actionID"));
		if(IsEqualString(type, "Button") && (commandID != nullptr))
		{
			MenuCommand command;
			command.command.Adopt(commandID, kCFObjRetain);
			CFObj<CFStringRef> actionID(CreateItemActionID(std::move(command)));
			CFObj<CFMutableDictionaryRef> newProperties(CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, properties));
			CFDictionarySetValue(newProperties, CFSTR("actionID"), actionID);
			CFObj<CFMutableDictionaryRef> newElement(CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, element));
			CFDictionarySetValue(newElement, CFSTR("properties"), newProperties);
			CFArrayAppendValue(children, newElement);
		}
		else if(IsEqualString(type, "Menu"))
		{
			CFObj<CFArrayRef> menuChildren(CreateChildrenWithOwnActions(ArrayValue(element, CFSTR("children"))));
			CFObj<CFMutableDictionaryRef> newElement(CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, element));
			CFDictionarySetValue(newElement, CFSTR("children"), menuChildren);
			CFArrayAppendValue(children, newElement);
		}
		else
		{
			CFArrayAppendValue(children, element);
		}
	}
	return children;
}

// The children array of the Menu titled inTitle among inChildren, made at the end when there is none
// (as OMCCommandMenu.mm's FindOrAddSubmenu)
CFMutableArrayRef
FindOrAddSubmenu(CFMutableArrayRef inChildren, CFStringRef inTitle)
{
	CFIndex count = CFArrayGetCount(inChildren);
	for(CFIndex i = 0; i < count; i++)
	{
		CFDictionaryRef element = (CFDictionaryRef)CFArrayGetValueAtIndex(inChildren, i);
		CFStringRef title = StringValue(DictionaryValue(element, CFSTR("properties")), CFSTR("title"));
		if(IsEqualString(StringValue(element, CFSTR("type")), "Menu") && (title != nullptr) &&
			(CFStringCompare(title, inTitle, 0) == kCFCompareEqualTo))
			return (CFMutableArrayRef)ArrayValue(element, CFSTR("children")); // made mutable below
	}
	CFObj<CFMutableDictionaryRef> properties(CreateMutableDictionary());
	CFDictionarySetValue(properties, CFSTR("title"), inTitle);
	CFObj<CFMutableArrayRef> children(CreateMutableArray());
	CFObj<CFMutableDictionaryRef> menu(CreateMutableDictionary());
	CFDictionarySetValue(menu, CFSTR("type"), CFSTR("Menu"));
	CFDictionarySetValue(menu, CFSTR("properties"), properties);
	CFDictionarySetValue(menu, CFSTR("children"), children);
	CFArrayAppendValue(inChildren, menu);
	return children; // held by menu, which inChildren holds
}

// The Commands menu's items: every command of the command file, in submenus (OMCMenuModel.h)
CFArrayRef
CreateCommandsMenuChildren()
{
	CFMutableArrayRef children = CreateMutableArray();
	CFObj<CFURLRef> commandURL(OMCCopyCommandFileURL(sMenu->commandFile));
	OMCMenuModel model;
	if(!OMCBuildCommandsMenuModel(commandURL, model))
		return children;
	for(const OMCMenuItemEntry &entry : model.items)
	{
		CFMutableArrayRef submenu = children;
		for(const CFObj<CFStringRef> &name : OMCCopySubmenuNames(entry.submenuPath))
			submenu = FindOrAddSubmenu(submenu, name);
		if(entry.name == nullptr)
			continue;
		// The command a Commands menu item runs: its id, or its name when it has none of its own
		CFStringRef toRun = OMCCommandsMenuItemCommandToRun(entry.commandID, entry.name);
		if(toRun == nullptr)
			continue;
		MenuCommand command;
		command.command.Adopt(toRun, kCFObjRetain);
		CFObj<CFStringRef> actionID(CreateItemActionID(std::move(command)));
		CFObj<CFDictionaryRef> button(CreateButton(entry.name, actionID, nullptr));
		CFArrayAppendValue(submenu, button);
	}
	return children;
}

// Whether a MainMenu.json CommandGroup takes away a standard item with one of inTargets
bool
IsReplaced(CFArrayRef inMainMenuElements, std::initializer_list<const char *> inTargets)
{
	if(inMainMenuElements == nullptr)
		return false;
	CFIndex count = CFArrayGetCount(inMainMenuElements);
	for(CFIndex i = 0; i < count; i++)
	{
		CFTypeRef item = CFArrayGetValueAtIndex(inMainMenuElements, i);
		if((item == nullptr) || (CFGetTypeID(item) != CFDictionaryGetTypeID()))
			continue;
		CFDictionaryRef element = (CFDictionaryRef)item;
		CFDictionaryRef properties = DictionaryValue(element, CFSTR("properties"));
		if(!IsEqualString(StringValue(element, CFSTR("type")), "CommandGroup") ||
			!IsEqualString(StringValue(properties, CFSTR("placement")), "replacing"))
			continue;
		std::string target = ACFStringToUTF8(StringValue(properties, CFSTR("placementTarget")));
		for(const char *oneTarget : inTargets)
		{
			if(target == oneTarget)
				return true;
		}
	}
	return false;
}

// OMC's items, then the applet's elements with OMC's action ids
CFArrayRef
CreateMenuElements(CFArrayRef inMainMenuElements)
{
	CFMutableArrayRef elements = CreateMutableArray();

	// New and Open, as macOS's File menu has them, where GNOME's primary menu puts its first items
	CFObj<CFMutableArrayRef> fileItems(CreateMutableArray());
	if(!IsReplaced(inMainMenuElements, {"new", "newItem", "File"}))
	{
		sMenu->items.emplace(kNewActionID, MenuCommand{MenuCommand::Kind::MainCommand, nullptr});
		CFObj<CFDictionaryRef> button(CreateButton(CFSTR("New"), CFSTR("omc.menu.new"), CFSTR("n")));
		CFArrayAppendValue(fileItems, button);
	}
	if(!IsReplaced(inMainMenuElements, {"open", "newItem", "File"}))
	{
		sMenu->items.emplace(kOpenActionID, MenuCommand{MenuCommand::Kind::MainCommand, nullptr});
		// "Open" and an ellipsis (U+2026, in UTF-8), as macOS's File menu titles it
		CFObj<CFStringRef> title(CFStringCreateWithCString(kCFAllocatorDefault, "Open\xE2\x80\xA6", kCFStringEncodingUTF8));
		CFObj<CFDictionaryRef> button(CreateButton(title, CFSTR("omc.menu.open"), CFSTR("o")));
		CFArrayAppendValue(fileItems, button);
	}
	if(CFArrayGetCount(fileItems) > 0)
	{
		CFObj<CFDictionaryRef> group(CreateCommandGroup(CFSTR("before"), CFSTR("newItem"), fileItems));
		CFArrayAppendValue(elements, group);
	}

	if(inMainMenuElements != nullptr)
	{
		CFIndex count = CFArrayGetCount(inMainMenuElements);
		for(CFIndex i = 0; i < count; i++)
		{
			CFTypeRef item = CFArrayGetValueAtIndex(inMainMenuElements, i);
			if((item == nullptr) || (CFGetTypeID(item) != CFDictionaryGetTypeID()))
				continue;
			CFDictionaryRef element = (CFDictionaryRef)item;
			CFStringRef type = StringValue(element, CFSTR("type"));
			CFDictionaryRef properties = DictionaryValue(element, CFSTR("properties"));
			CFTypeRef autoPopulate = (properties != nullptr) ? CFDictionaryGetValue(properties, CFSTR("autoPopulate")) : nullptr;
			bool isCommandsMenu = IsEqualString(type, "CommandMenu") && IsTrueValue(autoPopulate);
			CFObj<CFArrayRef> children(isCommandsMenu ? CreateCommandsMenuChildren()
														: CreateChildrenWithOwnActions(ArrayValue(element, CFSTR("children"))));
			CFObj<CFMutableDictionaryRef> newElement(CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, element));
			if(isCommandsMenu)
			{
				CFStringRef name = StringValue(properties, CFSTR("name"));
				if((name == nullptr) || (CFStringGetLength(name) == 0))
				{
					CFObj<CFMutableDictionaryRef> newProperties(CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, properties));
					CFDictionarySetValue(newProperties, CFSTR("name"), CFSTR("Commands"));
					CFDictionarySetValue(newElement, CFSTR("properties"), newProperties);
				}
			}
			CFDictionarySetValue(newElement, CFSTR("children"), children);
			CFArrayAppendValue(elements, newElement);
		}
	}

	// Quit, where GNOME's primary menu ends; Ctrl+Q
	if(!IsReplaced(inMainMenuElements, {"quit", "appTermination"}))
	{
		sMenu->items.emplace(kQuitActionID, MenuCommand{MenuCommand::Kind::Quit, nullptr});
		CFObj<CFMutableArrayRef> quitItems(CreateMutableArray());
		CFObj<CFDictionaryRef> button(CreateButton(CFSTR("Quit"), CFSTR("omc.menu.quit"), CFSTR("q")));
		CFArrayAppendValue(quitItems, button);
		CFObj<CFDictionaryRef> group(CreateCommandGroup(CFSTR("after"), CFSTR("appTermination"), quitItems));
		CFArrayAppendValue(elements, group);
	}
	return elements;
}

} // namespace

CFArrayRef
OMCCopyAppletMainMenuElements()
{
	CFBundleRef bundle = CFBundleGetMainBundle();
	CFObj<CFURLRef> url((bundle != nullptr) ? CFBundleCopyResourceURL(bundle, CFSTR("MainMenu"), CFSTR("json"), nullptr) : nullptr);
	if(url == nullptr)
		return nullptr; // optional: no applet menu items
	CFObj<CFDataRef> data;
	SInt32 errorCode = 0;
	if(!CFURLCreateDataAndPropertiesFromResource(kCFAllocatorDefault, url, &data, nullptr, nullptr, &errorCode) || (data == nullptr))
	{
		OMCLogMessage("MainMenu.json could not be read (error %d)", (int)errorCode);
		return nullptr;
	}
	CFObj<CFStringRef> parseError;
	CFObj<CFPropertyListRef> parsed(ACFJSONCreatePropertyList(data, kCFPropertyListImmutable, &parseError));
	if((parsed == nullptr) || (CFGetTypeID(parsed) != CFArrayGetTypeID()))
	{
		OMCLogMessage("MainMenu.json must be an array of menu elements: %s", OMCLogCString(parseError).c_str());
		return nullptr;
	}
	return (CFArrayRef)parsed.Detach();
}

bool
OMCInstallAppletMenu(CFArrayRef inMainMenuElements, CFStringRef inCommandFile, const OMCAppletMenuActions &inActions)
{
	if(sMenu == nullptr)
		sMenu = new MenuState(); // never freed: its handlers live as long as the app
	sMenu->commandFile.Adopt(inCommandFile, kCFObjRetain);
	sMenu->actions = inActions;

	CFObj<CFArrayRef> elements(CreateMenuElements(inMainMenuElements));
	ACFJSONWriteStatus status = kACFJSONWriteOK;
	CFObj<CFDataRef> json(ACFJSONCreateData(elements, &status));
	if(json == nullptr)
	{
		OMCLogMessage("the applet's menu could not be written as JSON (status %d)", (int)status);
		return false;
	}
	for(const auto &item : sMenu->items)
		(void)actionUIRegisterActionHandler(item.first.c_str(), HandleMenuAction);
	std::string text((const char *)CFDataGetBytePtr(json), (size_t)CFDataGetLength(json));
	if(!actionUILoadMenuBarJSON(text.c_str()))
	{
		OMCLogMessage("ActionUI did not load the applet's menu");
		return false;
	}
	return true;
}

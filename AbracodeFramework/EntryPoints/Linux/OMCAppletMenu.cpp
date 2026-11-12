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
#include <gtk/gtk.h>
#include <algorithm>
#include <initializer_list>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace
{

// What a chosen item does: run a command (by id or name), or one of OMC's own items
struct MenuCommand
{
	enum class Kind { Command, MainCommand, Quit, RecentFile, ClearRecent };
	Kind kind {Kind::Command};
	CFObj<CFStringRef> command;
	size_t recentIndex {0}; // RecentFile: which of MenuState::recentURIs
};

struct MenuState
{
	CFObj<CFStringRef> commandFile;
	OMCAppletMenuActions actions {};
	std::map<std::string, MenuCommand> items; // by the action id OMC gave the item
	unsigned nextItemNumber {1};
	bool hasOpenRecent {false};
	std::vector<std::string> recentURIs; // the files Open Recent shows now, in its order
	std::string recentJSON; // what Open Recent was last loaded from (see RebuildOpenRecent)
};

MenuState *sMenu = nullptr; // made once, for the life of the app

const char *kNewActionID = "omc.menu.new";
const char *kOpenActionID = "omc.menu.open";
const char *kQuitActionID = "omc.menu.quit";
const char *kRecentKey = "omc.open-recent"; // the menu part actionUIReplaceMenuBarJSON keeps current
const char *kClearRecentActionID = "omc.menu.recent.clear";
const size_t kRecentLimit = 10; // as macOS's Open Recent

void RebuildOpenRecent();
void ClearRecentFiles();

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

		case MenuCommand::Kind::RecentFile:
			if((item.recentIndex < sMenu->recentURIs.size()) && (sMenu->actions.openFile != nullptr))
			{
				const std::string &uri = sMenu->recentURIs[item.recentIndex];
				CFObj<CFURLRef> url(CFURLCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)uri.data(), (CFIndex)uri.size(), kCFStringEncodingUTF8, nullptr));
				if(url != nullptr)
					sMenu->actions.openFile(sMenu->actions.context, url);
			}
			break;

		case MenuCommand::Kind::ClearRecent:
			ClearRecentFiles();
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

#pragma mark - Open Recent

struct RecentFile
{
	std::string uri;
	std::string name;
	std::string folder;
	gint64 modified {0};
};

// The applet's recent files, newest first, at most kRecentLimit: the desktop's recent list (GTK's)
// holds every app's, each with the apps that added it; OMCNoteRecentDocument adds under GLib's
// application name. Local files that are gone are left out.
std::vector<RecentFile>
CopyRecentFiles()
{
	std::vector<RecentFile> files;
	const char *appName = g_get_application_name();
	if(!gtk_is_initialized() || (appName == nullptr))
		return files;
	GList *items = gtk_recent_manager_get_items(gtk_recent_manager_get_default());
	for(GList *item = items; item != nullptr; item = item->next)
	{
		GtkRecentInfo *info = static_cast<GtkRecentInfo *>(item->data);
		if(gtk_recent_info_has_application(info, appName) && (!gtk_recent_info_is_local(info) || gtk_recent_info_exists(info)))
		{
			RecentFile file;
			file.uri = gtk_recent_info_get_uri(info);
			const char *name = gtk_recent_info_get_display_name(info);
			file.name = (name != nullptr) ? name : file.uri;
			GFile *location = g_file_new_for_uri(file.uri.c_str());
			GFile *parent = g_file_get_parent(location);
			char *folder = (parent != nullptr) ? g_file_get_basename(parent) : nullptr;
			file.folder = (folder != nullptr) ? folder : "";
			g_free(folder);
			if(parent != nullptr)
				g_object_unref(parent);
			g_object_unref(location);
			// When the applet last used it (its own stamp in the list, as macOS keeps a list per app),
			// else when any app did; in microseconds, so files opened within one second keep their order
			const char *exec = nullptr;
			guint count = 0;
			GDateTime *used = nullptr;
			if(!gtk_recent_info_get_application_info(info, appName, &exec, &count, &used) || (used == nullptr))
				used = gtk_recent_info_get_modified(info);
			file.modified = (used != nullptr) ? (g_date_time_to_unix(used) * G_USEC_PER_SEC + g_date_time_get_microsecond(used)) : 0;
			files.push_back(std::move(file));
		}
		gtk_recent_info_unref(info);
	}
	g_list_free(items);
	std::stable_sort(files.begin(), files.end(), [](const RecentFile &a, const RecentFile &b) { return a.modified > b.modified; });
	if(files.size() > kRecentLimit)
		files.resize(kRecentLimit);
	return files;
}

CFStringRef
CreateCFString(const std::string &inText)
{
	return CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)inText.data(), (CFIndex)inText.size(), kCFStringEncodingUTF8, false);
}

// The Open Recent part of the menu: a CommandGroup after New and Open holding the submenu
CFArrayRef
CreateOpenRecentElements()
{
	std::vector<RecentFile> files = CopyRecentFiles();
	sMenu->recentURIs.clear();
	CFObj<CFMutableArrayRef> children(CreateMutableArray());
	for(size_t i = 0; i < files.size(); i++)
	{
		// Two files of one name: each with its folder, as macOS shows them
		bool shared = std::count_if(files.begin(), files.end(), [&](const RecentFile &f) { return f.name == files[i].name; }) > 1;
		std::string title = (shared && !files[i].folder.empty()) ? (files[i].name + " - " + files[i].folder) : files[i].name;
		sMenu->recentURIs.push_back(files[i].uri);
		CFObj<CFStringRef> titleString(CreateCFString(title));
		CFObj<CFStringRef> actionID(CreateCFString("omc.menu.recent." + std::to_string(i)));
		CFObj<CFDictionaryRef> button(CreateButton(titleString, actionID, nullptr));
		CFArrayAppendValue(children, button);
	}
	if(!files.empty())
	{
		CFObj<CFMutableDictionaryRef> divider(CreateMutableDictionary());
		CFDictionarySetValue(divider, CFSTR("type"), CFSTR("Divider"));
		CFArrayAppendValue(children, divider);
	}
	// Clear Menu, greyed out (no action) when there is nothing to clear, as on macOS
	CFObj<CFMutableDictionaryRef> clearProperties(CreateMutableDictionary());
	CFDictionarySetValue(clearProperties, CFSTR("title"), CFSTR("Clear Menu"));
	if(!files.empty())
	{
		CFObj<CFStringRef> clearID(CreateCFString(kClearRecentActionID));
		CFDictionarySetValue(clearProperties, CFSTR("actionID"), clearID);
	}
	CFObj<CFMutableDictionaryRef> clear(CreateMutableDictionary());
	CFDictionarySetValue(clear, CFSTR("type"), CFSTR("Button"));
	CFDictionarySetValue(clear, CFSTR("properties"), clearProperties);
	CFArrayAppendValue(children, clear);

	CFObj<CFMutableDictionaryRef> menuProperties(CreateMutableDictionary());
	CFDictionarySetValue(menuProperties, CFSTR("title"), CFSTR("Open Recent"));
	CFObj<CFMutableDictionaryRef> menu(CreateMutableDictionary());
	CFDictionarySetValue(menu, CFSTR("type"), CFSTR("Menu"));
	CFDictionarySetValue(menu, CFSTR("properties"), menuProperties);
	CFDictionarySetValue(menu, CFSTR("children"), children);
	CFObj<CFMutableArrayRef> groupChildren(CreateMutableArray());
	CFArrayAppendValue(groupChildren, menu);
	CFObj<CFDictionaryRef> group(CreateCommandGroup(CFSTR("after"), CFSTR("newItem"), groupChildren));
	CFMutableArrayRef elements = CreateMutableArray();
	CFArrayAppendValue(elements, group);
	return elements;
}

void
RebuildOpenRecent()
{
	if((sMenu == nullptr) || !sMenu->hasOpenRecent)
		return;
	CFObj<CFArrayRef> elements(CreateOpenRecentElements());
	ACFJSONWriteStatus status = kACFJSONWriteOK;
	CFObj<CFDataRef> json(ACFJSONCreateData(elements, &status));
	if(json == nullptr)
	{
		OMCLogMessage("Open Recent could not be written as JSON (status %d)", (int)status);
		return;
	}
	std::string text((const char *)CFDataGetBytePtr(json), (size_t)CFDataGetLength(json));
	// The list changes with every app's files: when the applet's look the same, the menu stays as it
	// is (a rebuild gives every menu button a new popover, closing one that is open)
	if(text == sMenu->recentJSON)
		return;
	if(!actionUIReplaceMenuBarJSON(kRecentKey, text.c_str()))
	{
		OMCLogMessage("ActionUI did not load Open Recent");
		return;
	}
	sMenu->recentJSON = text;
}

// Clear Menu: all the applet's files leave the desktop's recent list, not only the ones shown, as
// macOS clears them all (the "changed" signal rebuilds)
void
ClearRecentFiles()
{
	const char *appName = g_get_application_name();
	if(appName == nullptr)
		return;
	GtkRecentManager *manager = gtk_recent_manager_get_default();
	std::vector<std::string> uris;
	GList *items = gtk_recent_manager_get_items(manager);
	for(GList *item = items; item != nullptr; item = item->next)
	{
		GtkRecentInfo *info = static_cast<GtkRecentInfo *>(item->data);
		if(gtk_recent_info_has_application(info, appName))
			uris.push_back(gtk_recent_info_get_uri(info));
		gtk_recent_info_unref(info);
	}
	g_list_free(items);
	for(const std::string &uri : uris)
		(void)gtk_recent_manager_remove_item(manager, uri.c_str(), nullptr);
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

	// Open Recent goes with Open, as on macOS (its submenu follows Open there): its items have fixed
	// action ids, each the file at its place in the list it shows now
	sMenu->hasOpenRecent = (sMenu->items.count(kOpenActionID) != 0) && gtk_is_initialized();
	if(sMenu->hasOpenRecent)
	{
		for(size_t i = 0; i < kRecentLimit; i++)
		{
			MenuCommand recent;
			recent.kind = MenuCommand::Kind::RecentFile;
			recent.recentIndex = i;
			sMenu->items.emplace("omc.menu.recent." + std::to_string(i), std::move(recent));
		}
		sMenu->items.emplace(kClearRecentActionID, MenuCommand{MenuCommand::Kind::ClearRecent, nullptr});
	}

	for(const auto &item : sMenu->items)
		(void)actionUIRegisterActionHandler(item.first.c_str(), HandleMenuAction);
	std::string text((const char *)CFDataGetBytePtr(json), (size_t)CFDataGetLength(json));
	if(!actionUILoadMenuBarJSON(text.c_str()))
	{
		OMCLogMessage("ActionUI did not load the applet's menu");
		return false;
	}
	if(sMenu->hasOpenRecent)
	{
		RebuildOpenRecent();
		g_signal_connect(gtk_recent_manager_get_default(), "changed", G_CALLBACK(+[](GtkRecentManager *, gpointer) {
			RebuildOpenRecent();
		}), nullptr);
	}
	return true;
}

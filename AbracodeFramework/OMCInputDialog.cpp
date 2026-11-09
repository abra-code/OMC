//
//  OMCInputDialog.cpp
//  Abracode
//
//  A command's INPUT dialog (OMCInputDialog.h). Portable: the window comes from the window host,
//  and the values go to and come from the document through ActionUI's C interface.
//

#include "OMCInputDialog.h"
#include "OMCWindowHost.h"
#include "OMCConstants.h"
#include "OnMyCommand.h"
#include "CommandRuntimeData.h"
#include "ACFString.h"
#include "ACFJSON.h"
#include "ActionUIC.h"
#include <map>
#include <memory>
#include <string>

// The documents' element ids (BuiltInDocuments/omc_input_*.json)
static const int64_t kMessageTextID = 2;
static const int64_t kInputFieldID = 3;			// TextField, SecureField or Picker
static const int64_t kComboMenuID = 4;			// the combo box's menu
static const int64_t kCancelButtonID = 5;
static const int64_t kOKButtonID = 6;
static const int64_t kFirstMenuItemID = 100;	// the combo box menu's buttons, inserted at run time

static const char *const kOKActionID = "omc.builtin.input.ok";
static const char *const kCancelActionID = "omc.builtin.input.cancel";
static const char *const kMenuItemActionID = "omc.builtin.input.menu";

extern CFStringRef kBundleIDString; // OnMyCommand.cp: Abracode.framework's bundle identifier

static std::string JSONText(CFPropertyListRef inValue)
{
	CFObj<CFDataRef> json( ACFJSONCreateData(inValue, nullptr) );
	if(json == nullptr)
		return std::string();
	return std::string((const char *)CFDataGetBytePtr(json), (size_t)CFDataGetLength(json));
}

static void SetProperty(const char *inWindowUUID, int64_t inViewID, const char *inPropertyName, CFPropertyListRef inValue)
{
	std::string json = JSONText(inValue);
	if(!json.empty())
		actionUISetElementPropertyJSON(inWindowUUID, inViewID, inPropertyName, json.c_str());
}

static void SetValueString(const char *inWindowUUID, int64_t inViewID, CFStringRef inValue)
{
	std::string value = ACFStringToUTF8(inValue);
	actionUISetElementValueString(inWindowUUID, inViewID, 0, value.c_str(), nullptr);
}

static CFStringRef CopyValueString(const char *inWindowUUID, int64_t inViewID)
{
	char *value = actionUIGetElementValueString(inWindowUUID, inViewID, 0, nullptr);
	if(value == nullptr)
		return nullptr;
	CFStringRef outString = CFStringCreateWithCString(kCFAllocatorDefault, value, kCFStringEncodingUTF8);
	actionUIFreeString(value);
	return outString;
}

static CFStringRef CopyFrameworkString(CFStringRef inKey)
{
	CFBundleRef frameworkBundle = CFBundleGetBundleWithIdentifier(kBundleIDString);
	CFStringRef outString = nullptr;
	if(frameworkBundle != nullptr)
		outString = CFCopyLocalizedStringFromTableInBundle(inKey, CFSTR("Private"), frameworkBundle, "");
	if(outString == nullptr)
		outString = (CFStringRef)CFRetain(inKey);
	return outString;
}

static bool StringsEqual(CFStringRef inA, CFStringRef inB)
{
	return (inA != nullptr) && (inB != nullptr) && (CFStringCompare(inA, inB, 0) == kCFCompareEqualTo);
}

class OMCInputDialog
{
public:
	explicit				OMCInputDialog(const OMCInputDialogSettings &inSettings) : mSettings(inSettings) { }

	bool					Run(CFObj<CFStringRef> &outChoice);

	static void				ActionHandler(const char *inActionID, const char *inWindowUUID, int64_t inViewID, int64_t inViewPartID, const char *inContextJSON);

private:
	void					Fill();
	void					OK();
	void					MenuItemChosen(int64_t inViewID);
	CFStringRef				ValueOfName(CFStringRef inName) const; // not retained; NULL: no item has that name

	static std::map<std::string, OMCInputDialog *> &OpenDialogs()
							{
								static std::map<std::string, OMCInputDialog *> *sDialogs = new std::map<std::string, OMCInputDialog *>();
								return *sDialogs;
							}

	const OMCInputDialogSettings &mSettings;
	std::unique_ptr<OMCHostedWindow> mWindow;
	std::string				mWindowUUID;
	CFObj<CFStringRef>		mChoice;
	bool					mOKed {false};
};

bool
OMCInputDialog::Run(CFObj<CFStringRef> &outChoice)
{
	static bool sHandlersRegistered = false;
	if(!sHandlersRegistered)
	{
		actionUIRegisterActionHandler(kOKActionID, ActionHandler);
		actionUIRegisterActionHandler(kCancelActionID, ActionHandler);
		actionUIRegisterActionHandler(kMenuItemActionID, ActionHandler);
		sHandlersRegistered = true;
	}

	OMCHostedWindowSpec spec;
	switch(mSettings.type)
	{
		case kInputPasswordText:	spec.documentName = CFSTR("omc_input_password");	break;
		case kInputPopupMenu:		spec.documentName = CFSTR("omc_input_popup");		break;
		case kInputComboBox:		spec.documentName = CFSTR("omc_input_combo");		break;
		case kInputClearText:
		default:					spec.documentName = CFSTR("omc_input_text");		break;
	}
	spec.title = mSettings.title;
	spec.resizable = false;

	// closing the window is Cancel: RunModal returns with mOKed still false
	mWindow = OMCCreateHostedWindow(spec, nullptr);
	if(mWindow == nullptr)
		return false;

	mWindowUUID = ACFStringToUTF8(mWindow->GetWindowUUID());
	OpenDialogs()[mWindowUUID] = this;
	Fill();
	mWindow->SizeToContent(); // the message may wrap onto several lines
	mWindow->RunModal();
	OpenDialogs().erase(mWindowUUID);
	mWindow.reset(); // closes the window and forgets the document

	if(mOKed)
		outChoice.Adopt(mChoice.Detach());
	return mOKed;
}

void
OMCInputDialog::Fill()
{
	const char *uuid = mWindowUUID.c_str();

	// a Text's "text" property is only its first content: at run time its text is its value
	if( (mSettings.message != nullptr) && (CFStringGetLength(mSettings.message) > 0) )
		SetValueString(uuid, kMessageTextID, mSettings.message);
	else
		SetProperty(uuid, kMessageTextID, "hidden", kCFBooleanTrue);

	CFObj<CFStringRef> okTitle(mSettings.okTitle, kCFObjRetain);
	if(okTitle == nullptr)
		okTitle.Adopt( CopyFrameworkString(CFSTR("OK")) );
	SetProperty(uuid, kOKButtonID, "title", okTitle);

	CFObj<CFStringRef> cancelTitle(mSettings.cancelTitle, kCFObjRetain);
	if(cancelTitle == nullptr)
		cancelTitle.Adopt( CopyFrameworkString(CFSTR("Cancel")) );
	SetProperty(uuid, kCancelButtonID, "title", cancelTitle);

	if(mSettings.type == kInputPopupMenu)
	{ // the options' tags are their 1-based positions (an empty tag would not be drawn)
		CFObj<CFMutableArrayRef> options( CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks) );
		CFIndex chosen = 0;
		for(size_t i = 0; i < mSettings.menuItems.size(); i++)
		{
			CFObj<CFStringRef> tag( CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("%ld"), (long)(i + 1)) );
			const void *keys[] = { CFSTR("title"), CFSTR("tag") };
			const void *values[] = { (CFStringRef)mSettings.menuItems[i].name, (CFStringRef)tag };
			CFObj<CFDictionaryRef> option( CFDictionaryCreate(kCFAllocatorDefault, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks) );
			CFArrayAppendValue(options, option);
			if( (chosen == 0) && StringsEqual(mSettings.menuItems[i].name, mSettings.defaultValue) )
				chosen = (CFIndex)(i + 1);
		}
		SetProperty(uuid, kInputFieldID, "options", options);
		if( !mSettings.menuItems.empty() )
		{ // the default value's item, else the first one
			CFObj<CFStringRef> tag( CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, CFSTR("%ld"), (long)((chosen > 0) ? chosen : 1)) );
			SetValueString(uuid, kInputFieldID, tag);
		}
		return;
	}

	if(mSettings.type == kInputComboBox)
	{
		for(size_t i = 0; i < mSettings.menuItems.size(); i++)
		{
			int64_t buttonID = kFirstMenuItemID + (int64_t)i;
			CFObj<CFNumberRef> idNumber( CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &buttonID) );
			CFObj<CFStringRef> actionID( CFStringCreateWithCString(kCFAllocatorDefault, kMenuItemActionID, kCFStringEncodingUTF8) );
			const void *propertyKeys[] = { CFSTR("title"), CFSTR("actionID") };
			const void *propertyValues[] = { (CFStringRef)mSettings.menuItems[i].name, (CFStringRef)actionID };
			CFObj<CFDictionaryRef> properties( CFDictionaryCreate(kCFAllocatorDefault, propertyKeys, propertyValues, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks) );
			const void *keys[] = { CFSTR("type"), CFSTR("id"), CFSTR("properties") };
			const void *values[] = { CFSTR("Button"), (CFNumberRef)idNumber, (CFDictionaryRef)properties };
			CFObj<CFDictionaryRef> button( CFDictionaryCreate(kCFAllocatorDefault, keys, values, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks) );
			std::string json = JSONText(button);
			actionUIInsertElement(uuid, kComboMenuID, json.c_str(), nullptr, ActionUIInsertPositionAppend, 0);
		}
		if(mSettings.menuItems.empty())
			SetProperty(uuid, kComboMenuID, "disabled", kCFBooleanTrue);
	}

	if(mSettings.defaultValue != nullptr)
		SetValueString(uuid, kInputFieldID, mSettings.defaultValue);
}

CFStringRef
OMCInputDialog::ValueOfName(CFStringRef inName) const
{
	for(const OMCInputMenuItem &item : mSettings.menuItems)
	{
		if(StringsEqual(item.name, inName))
			return (item.value != nullptr) ? (CFStringRef)item.value : (CFStringRef)item.name;
	}
	return nullptr;
}

void
OMCInputDialog::OK()
{
	const char *uuid = mWindowUUID.c_str();
	CFObj<CFStringRef> fieldValue( CopyValueString(uuid, kInputFieldID) );

	if(mSettings.type == kInputPopupMenu)
	{ // the chosen option's tag is its 1-based position
		long position = (fieldValue != nullptr) ? (long)CFStringGetIntValue(fieldValue) : 0;
		if( (position >= 1) && ((size_t)position <= mSettings.menuItems.size()) )
		{
			const OMCInputMenuItem &item = mSettings.menuItems[(size_t)(position - 1)];
			mChoice.Adopt( (item.value != nullptr) ? (CFStringRef)item.value : (CFStringRef)item.name, kCFObjRetain );
		}
	}
	else
	{
		CFStringRef menuValue = (mSettings.type == kInputComboBox) ? ValueOfName(fieldValue) : nullptr;
		if(menuValue != nullptr)
			mChoice.Adopt(menuValue, kCFObjRetain);
		else
			mChoice.Swap(fieldValue);
	}

	if(mChoice == nullptr)
		mChoice.Adopt(CFSTR(""), kCFObjRetain);
	mOKed = true;
	mWindow->EndModal();
}

void
OMCInputDialog::MenuItemChosen(int64_t inViewID)
{
	int64_t index = inViewID - kFirstMenuItemID;
	if( (index < 0) || ((size_t)index >= mSettings.menuItems.size()) )
		return;
	SetValueString(mWindowUUID.c_str(), kInputFieldID, mSettings.menuItems[(size_t)index].name);
}

void
OMCInputDialog::ActionHandler(const char *inActionID, const char *inWindowUUID, int64_t inViewID, int64_t inViewPartID, const char *inContextJSON)
{
	if( (inActionID == nullptr) || (inWindowUUID == nullptr) )
		return;
	auto found = OpenDialogs().find(inWindowUUID);
	if(found == OpenDialogs().end())
		return;
	OMCInputDialog *dialog = found->second;

	std::string actionID(inActionID);
	if(actionID == kOKActionID)
		dialog->OK();
	else if(actionID == kCancelActionID)
		dialog->mWindow->EndModal();
	else if(actionID == kMenuItemActionID)
		dialog->MenuItemChosen(inViewID);
}

bool
OMCRunInputDialog(const OMCInputDialogSettings &inSettings, CFObj<CFStringRef> &outChoice)
{
	OMCInputDialog dialog(inSettings);
	return dialog.Run(outChoice);
}

// The command's localized string, or the string itself without a localization table
static CFStringRef CopyLocalizedString(CFStringRef inString, CFBundleRef inBundle, CFStringRef inTableName)
{
	if(inString == nullptr)
		return nullptr;
	if(inTableName == nullptr)
		return (CFStringRef)CFRetain(inString);
	return CFCopyLocalizedStringFromTableInBundle(inString, inTableName, inBundle, "");
}

Boolean
RunInputDialog(OnMyCommandCM *inPlugin, CommandRuntimeData &commandRuntimeData)
{
	if(inPlugin == nullptr)
		return false;

	CommandDescription &currCommand = inPlugin->GetCurrentCommand();
	CFStringRef tableName = currCommand.localizationTableName;

	CFBundleRef localizationBundle = nullptr;
	if(tableName != nullptr)//client wants to be localized
	{
		localizationBundle = inPlugin->GetCurrentCommandExternBundle();
		if(localizationBundle == nullptr)
			localizationBundle = CFBundleGetMainBundle();
	}

	OMCInputDialogSettings settings;
	settings.type = currCommand.inputDialogType;
	if(currCommand.name != nullptr)
		settings.title.Adopt( inPlugin->CreateDynamicCommandName(currCommand, commandRuntimeData, tableName, localizationBundle) );
	settings.message.Adopt( CopyLocalizedString(currCommand.inputDialogMessage, localizationBundle, tableName) );
	settings.okTitle.Adopt( CopyLocalizedString(currCommand.inputDialogOK, localizationBundle, tableName) );
	settings.cancelTitle.Adopt( CopyLocalizedString(currCommand.inputDialogCancel, localizationBundle, tableName) );
	settings.defaultValue.Adopt( inPlugin->CreateCombinedStringWithObjects(currCommand.inputDialogDefault, commandRuntimeData, tableName, localizationBundle) );

	// INPUT_MENU: dictionaries with a NAME (shown, localized) and an optional VALUE (the choice)
	CFArrayRef menuItems = currCommand.inputDialogMenuItems;
	CFIndex itemCount = (menuItems != nullptr) ? CFArrayGetCount(menuItems) : 0;
	for(CFIndex i = 0; i < itemCount; i++)
	{
		CFTypeRef oneItem = CFArrayGetValueAtIndex(menuItems, i);
		if( (oneItem == nullptr) || (CFGetTypeID(oneItem) != CFDictionaryGetTypeID()) )
			continue;
		CFTypeRef name = CFDictionaryGetValue((CFDictionaryRef)oneItem, CFSTR("NAME"));
		if( (name == nullptr) || (CFGetTypeID(name) != CFStringGetTypeID()) )
			continue;
		CFTypeRef value = CFDictionaryGetValue((CFDictionaryRef)oneItem, CFSTR("VALUE"));

		OMCInputMenuItem item;
		item.name.Adopt( CopyLocalizedString((CFStringRef)name, localizationBundle, tableName) );
		if( (value != nullptr) && (CFGetTypeID(value) == CFStringGetTypeID()) )
			item.value.Adopt((CFStringRef)value, kCFObjRetain);
		settings.menuItems.push_back(item);
	}

	CFObj<CFStringRef> choice;
	if( !OMCRunInputDialog(settings, choice) )
		return false;
	commandRuntimeData.inputText.Adopt(choice.Detach());
	return true;
}

//
//  OMCAboutWindow.cpp
//  Abracode
//
//  The applet's About window (OMCAboutWindow.h). Portable: the window comes from the window host,
//  and the values go to the document through ActionUI's C interface.
//

#include "OMCAboutWindow.h"
#include "OMCWindowHost.h"
#include "OMCEngineBundle.h"
#include "OMCHostInfo.h"
#include "OMCActionUIAddOns.h"
#include "OMCLog.h"
#include "ACFString.h"
#include "ACFJSON.h"
#include "ActionUIC.h"
#include "CFObj.h"
#include <fstream>
#include <memory>
#include <sstream>
#include <string>

namespace
{

// The document's element ids (BuiltInDocuments/command_about.json)
const int64_t kIconID = 1;
const int64_t kNameID = 2;
const int64_t kVersionID = 3;
const int64_t kCreditsAreaID = 4;
const int64_t kCreditsID = 5;
const int64_t kCopyrightID = 6;

struct AboutWindow
{
	std::unique_ptr<OMCHostedWindow> window;
	CFObj<CFBundleRef> bundle;
	bool closed {false}; // the user closed it; the window object goes when About is chosen again
};

AboutWindow *sAbout = nullptr; // made once, for the life of the app

// A non-empty string of the bundle's Info.plist, not retained; NULL otherwise
CFStringRef
InfoString(CFBundleRef inBundle, CFStringRef inKey)
{
	CFTypeRef value = CFBundleGetValueForInfoDictionaryKey(inBundle, inKey);
	if((value == nullptr) || (CFGetTypeID(value) != CFStringGetTypeID()) || (CFStringGetLength((CFStringRef)value) == 0))
		return nullptr;
	return (CFStringRef)value;
}

// One of the engine's strings (the Private table), in the user's language
CFStringRef
CopyEngineString(CFStringRef inKey)
{
	CFBundleRef engineBundle = OMCGetEngineBundle();
	if(engineBundle != nullptr)
		return CFCopyLocalizedStringFromTableInBundle(inKey, CFSTR("Private"), engineBundle, "");
	return (CFStringRef)CFRetain(inKey);
}

// CFBundleDisplayName, else CFBundleName, else the bundle's file name without its extension
CFStringRef
CopyAppName(CFBundleRef inBundle)
{
	CFStringRef name = InfoString(inBundle, CFSTR("CFBundleDisplayName"));
	if(name == nullptr)
		name = InfoString(inBundle, kCFBundleNameKey);
	if(name != nullptr)
		return (CFStringRef)CFRetain(name);
	CFObj<CFURLRef> bundleURL(CFBundleCopyBundleURL(inBundle));
	CFObj<CFURLRef> withoutExtension((bundleURL != nullptr) ? CFURLCreateCopyDeletingPathExtension(kCFAllocatorDefault, bundleURL) : nullptr);
	return (withoutExtension != nullptr) ? CFURLCopyLastPathComponent(withoutExtension) : nullptr;
}

// "Version 1.2 (345)"; "Version 1.2" when the build is missing or the same; NULL with neither
CFStringRef
CopyVersionLine(CFBundleRef inBundle)
{
	CFStringRef shortVersion = InfoString(inBundle, CFSTR("CFBundleShortVersionString"));
	CFStringRef buildVersion = InfoString(inBundle, kCFBundleVersionKey);
	if((shortVersion != nullptr) && (buildVersion != nullptr) && (CFStringCompare(shortVersion, buildVersion, 0) != kCFCompareEqualTo))
	{
		CFObj<CFStringRef> format(CopyEngineString(CFSTR("Version %@ (%@)")));
		return CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, format, shortVersion, buildVersion);
	}
	CFStringRef version = (shortVersion != nullptr) ? shortVersion : buildVersion;
	if(version == nullptr)
		return nullptr;
	CFObj<CFStringRef> format(CopyEngineString(CFSTR("Version %@")));
	return CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, format, version);
}

// The bundle's Resources/Credits.md as UTF-8; empty when there is none or it cannot be read
std::string
ReadCredits(CFBundleRef inBundle)
{
	CFObj<CFURLRef> url(CFBundleCopyResourceURL(inBundle, CFSTR("Credits"), CFSTR("md"), nullptr));
	if(url == nullptr)
		return std::string();
	char path[PATH_MAX];
	if(!CFURLGetFileSystemRepresentation(url, true, (UInt8 *)path, sizeof(path)))
		return std::string();
	std::ifstream file(path, std::ios::in | std::ios::binary);
	if(!file)
	{
		OMCLogMessage("Credits.md could not be read: %s", path);
		return std::string();
	}
	std::ostringstream contents;
	contents << file.rdbuf();
	std::string text = contents.str();
	// A byte order mark is not part of the Markdown
	if((text.size() >= 3) && ((unsigned char)text[0] == 0xEF) && ((unsigned char)text[1] == 0xBB) && ((unsigned char)text[2] == 0xBF))
		text.erase(0, 3);
	return text;
}

void
SetText(const char *inWindowUUID, int64_t inViewID, CFStringRef inText)
{
	std::string text = ACFStringToUTF8(inText);
	(void)actionUISetElementValueString(inWindowUUID, inViewID, 0, text.c_str(), nullptr);
}

// Fills the window's document from the bundle and takes out what the bundle lacks
void
FillDocument(const char *inWindowUUID, CFBundleRef inBundle)
{
	CFObj<CFURLRef> iconURL(OMCCopyBundleIconURL(inBundle));
	char iconPath[PATH_MAX];
	if((iconURL != nullptr) && CFURLGetFileSystemRepresentation(iconURL, true, (UInt8 *)iconPath, sizeof(iconPath)))
	{
		CFObj<CFStringRef> path(CFStringCreateWithFileSystemRepresentation(kCFAllocatorDefault, iconPath));
		CFObj<CFDataRef> json(ACFJSONCreateData(path, nullptr));
		if(json != nullptr)
		{
			std::string jsonText((const char *)CFDataGetBytePtr(json), (size_t)CFDataGetLength(json));
			(void)actionUISetElementPropertyJSON(inWindowUUID, kIconID, "filePath", jsonText.c_str());
		}
	}
	else
	{
		(void)actionUIRemoveElement(inWindowUUID, kIconID);
	}

	CFObj<CFStringRef> name(CopyAppName(inBundle));
	if(name != nullptr)
		SetText(inWindowUUID, kNameID, name);
	else
		(void)actionUIRemoveElement(inWindowUUID, kNameID);

	CFObj<CFStringRef> version(CopyVersionLine(inBundle));
	if(version != nullptr)
		SetText(inWindowUUID, kVersionID, version);
	else
		(void)actionUIRemoveElement(inWindowUUID, kVersionID);

	std::string credits = ReadCredits(inBundle);
	if(!credits.empty())
		(void)actionUISetElementValueString(inWindowUUID, kCreditsID, 0, credits.c_str(), nullptr);
	else
		(void)actionUIRemoveElement(inWindowUUID, kCreditsAreaID);

	CFStringRef copyright = InfoString(inBundle, CFSTR("NSHumanReadableCopyright"));
	if(copyright != nullptr)
		SetText(inWindowUUID, kCopyrightID, copyright);
	else
		(void)actionUIRemoveElement(inWindowUUID, kCopyrightID);
}

} // namespace

void
OMCShowAboutWindow(CFBundleRef inBundle)
{
	if(inBundle == nullptr)
		inBundle = CFBundleGetMainBundle();
	if(inBundle == nullptr)
		return;
	if(sAbout == nullptr)
		sAbout = new AboutWindow();
	OMCRegisterActionUIAddOns(); // the credits are a RichText element; registered once

	if((sAbout->window != nullptr) && !sAbout->closed && (sAbout->bundle == inBundle))
	{
		sAbout->window->Show(); // to the front
		return;
	}
	// A closed window, or another bundle's: made again, so the window shows the bundle as it is now.
	// Not from the close callback, while the window is still telling its delegate.
	sAbout->window.reset();
	sAbout->bundle.Adopt(inBundle, kCFObjRetain);
	sAbout->closed = false;

	CFObj<CFStringRef> name(CopyAppName(inBundle));
	CFObj<CFStringRef> titleFormat(CopyEngineString(CFSTR("About %@")));
	CFObj<CFStringRef> title(CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, titleFormat, (name != nullptr) ? (CFStringRef)name : CFSTR("")));

	OMCHostedWindowSpec spec;
	spec.documentName = CFSTR("command_about");
	spec.title = title;
	spec.resizable = false;
	spec.miniaturizable = false;
	spec.placement = OMCHostedWindowPlacement::alert; // as macOS places its About panel
	sAbout->window = OMCCreateHostedWindow(spec, []()
	{
		if(sAbout != nullptr)
			sAbout->closed = true;
	});
	if(sAbout->window == nullptr)
	{
		OMCLogMessage("the About window could not be made (command_about.json)");
		return;
	}

	std::string uuid = ACFStringToUTF8(sAbout->window->GetWindowUUID());
	FillDocument(uuid.c_str(), inBundle);
	sAbout->window->SizeToContent(); // without the parts taken out
	sAbout->window->Show();
}

CFStringRef
OMCCopyAboutWindowUUID(void)
{
	if((sAbout == nullptr) || (sAbout->window == nullptr) || sAbout->closed)
		return nullptr;
	return (CFStringRef)CFRetain(sAbout->window->GetWindowUUID());
}

void
OMCCloseAboutWindow(void)
{
	if(sAbout == nullptr)
		return;
	sAbout->window.reset(); // closes it
	sAbout->bundle.Release();
	sAbout->closed = false;
}

#include "DropletPreferences.h"

DropletPreferences *gPreferences = NULL;


DropletPreferences::DropletPreferences(CFStringRef inPrefsIdentifier)
	: PlistPreferences(inPrefsIdentifier)
{
	Init();
}



DropletPreferences::~DropletPreferences()
{
}

void
DropletPreferences::Init()
{
	::memset( &mPrefs, 0, sizeof(mPrefs) );
	mPrefs.showNavDialogOnStartup = true;
	mPrefs.quitAfterDropExecution = false;
	mPrefs.runCommandOnReopenEvent = false;
}


void
DropletPreferences::Read()
{
	Init();	
	::CFPreferencesAppSynchronize( mPrefsIdentifier );
	
	CFIndex prefsVersion = kCurrentPrefsVersion;
	GetIntegerValueForKey(CFSTR("VERSION"), prefsVersion);

	GetBoolValueForKey(CFSTR("SHOW_NAV_DIALOG_ON_STARTUP"), mPrefs.showNavDialogOnStartup);
	GetBoolValueForKey(CFSTR("QUIT_AFTER_DROP_EXECUTION"), mPrefs.quitAfterDropExecution);
	GetBoolValueForKey(CFSTR("RUN_COMMAND_ON_REOPEN_EVENT"), mPrefs.runCommandOnReopenEvent);
}

void
DropletPreferences::Save()
{
	CFIndex prefsVersion = kCurrentPrefsVersion;
	SetIntegerValueForKey(CFSTR("VERSION"), prefsVersion);

	SetBoolValueForKey(CFSTR("SHOW_NAV_DIALOG_ON_STARTUP"), mPrefs.showNavDialogOnStartup);
	SetBoolValueForKey(CFSTR("QUIT_AFTER_DROP_EXECUTION"), mPrefs.quitAfterDropExecution);
	SetBoolValueForKey(CFSTR("RUN_COMMAND_ON_REOPEN_EVENT"), mPrefs.runCommandOnReopenEvent);

	::CFPreferencesAppSynchronize( mPrefsIdentifier );
}

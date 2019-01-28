#ifndef __DropletPrefs__
#define __DropletPrefs__

#include "PlistPreferences.h"

typedef	struct
{
	Boolean showNavDialogOnStartup;
	Boolean quitAfterDropExecution;
	Boolean runCommandOnReopenEvent;
}
DropletPrefs;

const CFIndex		kCurrentPrefsVersion = 1;


class DropletPreferences : public PlistPreferences
{

public:
	DropletPrefs		mPrefs;
		
public:
						DropletPreferences(CFStringRef inPrefsIdentifier);
	virtual				~DropletPreferences();
						
	virtual void		Init();
	virtual void		Read();
	virtual void		Save();
	
};

extern DropletPreferences *gPreferences;

#endif //__DropletPrefs__
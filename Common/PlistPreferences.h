#pragma once
#include <CoreFoundation/CoreFoundation.h>


class PlistPreferences
{
public:
						PlistPreferences(CFStringRef inPrefsIdentifier);
	virtual				~PlistPreferences();
						
	virtual void		Init() = 0;
	virtual void		Read();
	virtual void		Save();

	Boolean				GetBoolValueForKey(CFStringRef inKey, Boolean &outBoolValue);
	void				SetBoolValueForKey(CFStringRef inKey, Boolean inBoolValue);

	Boolean				GetIntegerValueForKey(CFStringRef inKey, CFIndex &outIntValue);
	void				SetIntegerValueForKey(CFStringRef inKey, CFIndex inIntValue);

	CFStringRef			CopyStringForKey(CFStringRef inKey);
	void				SetStringForKey(CFStringRef inKey, CFStringRef inString);

protected:
	CFStringRef			mPrefsIdentifier;

};


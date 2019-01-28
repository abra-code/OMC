#include "PlistPreferences.h"
#include "CFObj.h"
#include "ACFType.h"

PlistPreferences::PlistPreferences(CFStringRef inPrefsIdentifier)
	: mPrefsIdentifier(inPrefsIdentifier)
{
	if(mPrefsIdentifier != NULL)
		::CFRetain(mPrefsIdentifier);
}


PlistPreferences::~PlistPreferences()
{
	if(mPrefsIdentifier != NULL)
		::CFRelease(mPrefsIdentifier);
}

void
PlistPreferences::Init()
{
}


void
PlistPreferences::Read()
{
	Init();	
	::CFPreferencesAppSynchronize( mPrefsIdentifier );
}

void
PlistPreferences::Save()
{
	::CFPreferencesAppSynchronize( mPrefsIdentifier );
}

//sets the output value only if the key exists in prefs. otherwise value remains unchanged (presumably inited to default value)
Boolean
PlistPreferences::GetBoolValueForKey(CFStringRef inKey, Boolean &outBoolValue)
{
	Boolean isValid = false;
	Boolean boolValue = ::CFPreferencesGetAppBooleanValue(inKey, mPrefsIdentifier, &isValid );
	if( isValid )
		outBoolValue = boolValue;

	return isValid;
}

void
PlistPreferences::SetBoolValueForKey(CFStringRef inKey, Boolean inBoolValue)
{
	::CFPreferencesSetAppValue( inKey, inBoolValue ? kCFBooleanTrue : kCFBooleanFalse, mPrefsIdentifier );
}


//sets the output value only if the key exists in prefs. otherwise value remains unchanged (presumably inited to default value)
Boolean
PlistPreferences::GetIntegerValueForKey(CFStringRef inKey, CFIndex &outIntValue)
{
	Boolean isValid = false;
	CFIndex intValue = ::CFPreferencesGetAppIntegerValue(inKey, mPrefsIdentifier, &isValid );
	if( isValid )
		outIntValue = intValue;

	return isValid;
}

void
PlistPreferences::SetIntegerValueForKey(CFStringRef inKey, CFIndex inIntValue)
{
	CFNumberRef theNum = ::CFNumberCreate(kCFAllocatorDefault, kCFNumberLongType, &inIntValue);
	if(theNum != NULL)
	{
		::CFPreferencesSetAppValue( inKey, theNum, mPrefsIdentifier );
		::CFRelease(theNum);
	}
}


//caller responslible for releasing non-null outString

CFStringRef
PlistPreferences::CopyStringForKey(CFStringRef inKey)
{
	CFObj<CFTypeRef> resultRef( ::CFPreferencesCopyAppValue(inKey, mPrefsIdentifier) );
	if( ACFType<CFStringRef>::DynamicCast(resultRef) != NULL )
		return (CFStringRef)resultRef.Detach();
	return NULL;
}
	
void
PlistPreferences::SetStringForKey(CFStringRef inKey, CFStringRef inString)
{
	::CFPreferencesSetAppValue( inKey, inString, mPrefsIdentifier );
}


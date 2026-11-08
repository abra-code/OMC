//
//  OMCActionUIModelLifetime.cpp
//  Abracode
//
//  See OMCActionUIModelLifetime.h. Portable.
//

#include "OMCActionUIModelLifetime.h"
#include "OMCActionUIModels.h"
#include "OMCMainThreadSignal.h"
#include "CFObj.h"
#include <cstring>
#include <map>
#include <memory>
#include <string>

namespace
{

struct WindowHold
{
	CFIndex	tasks {0};
	bool	closed {false};
};

// Keyed by the window's UUID. An entry exists while the window has tasks or is closed and waiting
// for the check after its close. Never destroyed, so nothing depends on the order of exit-time
// destructors.
std::map<std::string, WindowHold> &
WindowHolds()
{
	static auto *sWindowHolds = new std::map<std::string, WindowHold>();
	return *sWindowHolds;
}

std::string
KeyOf(CFStringRef inWindowUUID)
{
	std::string key;
	if(inWindowUUID == nullptr)
		return key;
	CFIndex maxSize = ::CFStringGetMaximumSizeForEncoding(::CFStringGetLength(inWindowUUID), kCFStringEncodingUTF8) + 1;
	key.resize(static_cast<size_t>(maxSize));
	if(!::CFStringGetCString(inWindowUUID, &key[0], maxSize, kCFStringEncodingUTF8))
		return std::string();
	key.resize(std::strlen(key.c_str()));
	return key;
}

// Drops the entry once no task holds the window; a closed window's model goes with it.
void
ForgetIfUnheld(const std::string &inKey)
{
	auto found = WindowHolds().find(inKey);
	if((found == WindowHolds().end()) || (found->second.tasks > 0))
		return;

	bool wasClosed = found->second.closed;
	WindowHolds().erase(found);
	if(!wasClosed)
		return;

	CFObj<CFStringRef> windowUUID( ::CFStringCreateWithCString(kCFAllocatorDefault, inKey.c_str(), kCFStringEncodingUTF8), kCFObjDontRetain );
	if(windowUUID != nullptr)
		OMCPlatformForgetActionUIModel(windowUUID);
}

void
CheckClosedWindow(void *inContext)
{
	std::unique_ptr<std::string> key( static_cast<std::string *>(inContext) );
	ForgetIfUnheld(*key);
}

} // namespace

void
OMCActionUIModelHoldForTask(CFStringRef inWindowUUID)
{
	std::string key = KeyOf(inWindowUUID);
	if(key.empty())
		return;
	WindowHolds()[key].tasks++;
}

void
OMCActionUIModelReleaseForTask(CFStringRef inWindowUUID)
{
	std::string key = KeyOf(inWindowUUID);
	auto found = WindowHolds().find(key);
	if(found == WindowHolds().end())
		return;
	if(found->second.tasks > 0)
		found->second.tasks--;
	ForgetIfUnheld(key);
}

void
OMCActionUIModelWindowClosed(CFStringRef inWindowUUID)
{
	std::string key = KeyOf(inWindowUUID);
	if(key.empty())
		return;
	WindowHolds()[key].closed = true;

	std::unique_ptr<std::string> context( new std::string(key) );
	if(OMCMainThreadSignal::RunAfter(0.0, CheckClosedWindow, context.get()))
	{
		context.release(); // CheckClosedWindow owns it now
		return;
	}
	// Could not be scheduled: decide now. A blocking window's command that has not started its
	// tasks yet then finds its window gone from the bridge; its special words and environment
	// variables were collected before, so only a bridge read in it is affected.
	ForgetIfUnheld(key);
}

//
//  OMCActionUIModels.cpp (Linux)
//  Abracode
//
//  The Linux implementation of OMCPlatformForgetActionUIModel (Platform/OMCActionUIModels.h):
//  ActionUI's C adapter, actionUIRemoveWindow, as the macOS one goes through ActionUIObjC. Closing a
//  hosted window keeps its model (ActionUIC.h), so without this every closed window's model stayed.
//  Main thread only.
//

#include "OMCActionUIModels.h"
#include "ACFString.h"
#include "ActionUIC.h"
#include <string>

void
OMCPlatformForgetActionUIModel(CFStringRef inWindowUUID)
{
	if(inWindowUUID == nullptr)
		return;
	std::string windowUUID = ACFStringToUTF8(inWindowUUID);
	if(!windowUUID.empty())
		actionUIRemoveWindow(windowUUID.c_str());
}

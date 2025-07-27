#pragma once

#include "CFObj.h"

class OMCRuntimeUUIDs
{
public:
    OMCRuntimeUUIDs()
	{
	}
	
	~OMCRuntimeUUIDs()
	{
	}

public:
	CFObj<CFStringRef> commandUUID;
	CFObj<CFStringRef> dialogUUID;// dialog GUID used instead of dialog ptr to look up the instance
};

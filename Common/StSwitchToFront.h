//**************************************************************************************
// Filename:	StSwitchToFront.h
// Copyright © 2005 Abracode, Inc.  All rights reserved.
//
// Description:	
//
//**************************************************************************************
// Revision History:
// Saturday, May 28, 2005 - Original
//**************************************************************************************

#pragma once

#include <Carbon/Carbon.h>

class StSwitchToFront
{
public:
							StSwitchToFront(bool inRestore = true);
	virtual					~StSwitchToFront();

private:
	ProcessSerialNumber		mFrontProcess;
	
		// Defensive programming. No copy constructor nor operator=
							StSwitchToFront(const StSwitchToFront&);
		StSwitchToFront&			operator=(const StSwitchToFront&);
};

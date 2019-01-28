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

#if defined(__MACH__)
    #import <Carbon/Carbon.h>
#else
    #include <Carbon.h>
#endif //defined(__MACH__)

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
//**************************************************************************************
// Filename:	StSwitchToFront.h
//**************************************************************************************

#pragma once
#include <unistd.h>

class StSwitchToFront
{
public:
    StSwitchToFront(bool inRestore = true) noexcept;
	~StSwitchToFront() noexcept;

private:
    pid_t mPreviousFrontAppPID { 0 };
};

//**************************************************************************************
// Filename:	StSwitchToFront.cp
//
// Description:	switched current process to front if not front already and restores
// front application on destruction
//
//**************************************************************************************

#include "StSwitchToFront.h"

StSwitchToFront::StSwitchToFront(bool inRestore /*= true*/) noexcept
{
    @autoreleasepool
    {
        NSRunningApplication *currentApp = [NSRunningApplication currentApplication];
        BOOL isCurrAppActive = [currentApp isActive];
        if(!isCurrAppActive)
        {
            if(inRestore)
            {
                NSRunningApplication *frontmostApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
                mPreviousFrontAppPID = [frontmostApp processIdentifier];
            }
            /*BOOL isOK =*/ [currentApp activateWithOptions:(NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps)];
        }
    }
}

StSwitchToFront::~StSwitchToFront(void) noexcept
{
    @autoreleasepool
    {
        if(mPreviousFrontAppPID != 0)
        {
            NSRunningApplication *previousFrontApp = [NSRunningApplication runningApplicationWithProcessIdentifier:mPreviousFrontAppPID];
            if(previousFrontApp != nil)
            {
                /*BOOL isOK =*/ [previousFrontApp activateWithOptions:(NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps)];
            }
        }
    }
}

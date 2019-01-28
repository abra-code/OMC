//**************************************************************************************
// Filename:	StSwitchToFront.cp
// Copyright © 2005 Abracode, Inc.  All rights reserved.
//
// Description:	switched current process to front if not front already and restores
// front application on destruction
//
//**************************************************************************************
// Revision History:
// Saturday, May 28, 2005 - Original
//**************************************************************************************

#include "StSwitchToFront.h"
#include "DebugSettings.h"

const ProcessSerialNumber kInvalidProcess = {kNoProcess, kNoProcess};

//**************************************************************************************
// Function:	Default Constructor
//
// Description: Builds the StSwitchToFront class.
//
// Inputs:	none
//		
// Outputs:	none	
//
//**************************************************************************************
StSwitchToFront::StSwitchToFront(bool inRestore /*= true*/)
	: mFrontProcess(kInvalidProcess)
{
	OSErr err = noErr;
	Boolean isTheSame = false;
	ProcessSerialNumber currProcess = { 0, kCurrentProcess };

	if( inRestore )
	{
		err = ::GetFrontProcess( &mFrontProcess );
		err = ::SameProcess( &currProcess, &mFrontProcess, &isTheSame );
	}

	if( !isTheSame )
	{
		err = ::SetFrontProcess( &currProcess );
		if(err != noErr)
		{
			DEBUG_CSTR("StSwitchToFront: SetFrontProcess failed with error: %d\n", (int)err);
		}
	}
}


//**************************************************************************************
// Function:	Destructor
//
// Description: Destroys the StSwitchToFront class.
//
// Inputs:	none
//		
// Outputs:	none	
//
//**************************************************************************************
StSwitchToFront::~StSwitchToFront(void)
{
	if( (mFrontProcess.highLongOfPSN != kNoProcess) || (mFrontProcess.lowLongOfPSN != kNoProcess) )
		SetFrontProcess( &mFrontProcess );
	mFrontProcess = kInvalidProcess;
}

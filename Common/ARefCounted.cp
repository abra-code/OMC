//**************************************************************************************
// Filename:	ACFType.cp
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
//
// Copyright © 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	helper for CoreFountation types
//	
//
//
//**************************************************************************************

#include "ARefCounted.h"

const CFArrayCallBacks ARefCounted::sCFArrayCallbacks = 
{
	0, //version
	ARefCounted::RetainCallback,
	ARefCounted::ReleaseCallback,
	NULL, //copyDescription
	NULL //equal
};

const CFSetCallBacks ARefCounted::sCFSetCallbacks = 
{
    0, //version
    ARefCounted::RetainCallback,
    ARefCounted::ReleaseCallback,
    NULL, //copyDescription
    NULL, //equal;
    NULL //hash;
};

const CFDictionaryValueCallBacks ARefCounted::sCFDictionaryCallbacks = 
{
	0, //version
	ARefCounted::RetainCallback,
	ARefCounted::ReleaseCallback,
	NULL, //copyDescription
	NULL //equal
};

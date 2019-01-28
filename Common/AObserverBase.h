//**************************************************************************************
// Filename:	AObserverBase.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
//
// Copyright © 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	AObserverBase defines common notification API but not the protocol details
//	
//
//
//**************************************************************************************

#pragma once
#include "ARefCounted.h"

class ANotifier;

class AObserverBase : public ARefCounted
{
public:
	virtual ~AObserverBase() { } //just to shut up the GCC compiler warning

	virtual void ReceiveNotification(void *ioData) const = 0;

protected:
	virtual void AddNotifier(const ANotifier *inNotifier) const = 0;
	virtual void RemoveNotifier(const ANotifier *inNotifier) const = 0;

	friend class ANotifier;
};

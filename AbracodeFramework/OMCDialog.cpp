/*
 *  OMCDialog.cpp
 *  Abracode
 *
 *  Created by Tomasz Kukielka on 3/2/08.
 *  Copyright 2008 Abracode. All rights reserved.
 *
 */

#include "OMCDialog.h"

OMCDialog * OMCDialog::sChainHead = NULL;

OMCDialog::OMCDialog()
	: next(NULL),
	mTaskObserver( new AObserver<OMCDialog>(this) ),
	mSelectionIterator(NULL)
{
	//add ourselves to linked list
	if(sChainHead == NULL)
	{
		sChainHead = this;
	}
	else
	{
		OMCDialog *oneLink = sChainHead;
		//find the tail
		while(oneLink->next != NULL)
			oneLink = oneLink->next;
		oneLink->next = this;
	}

}

OMCDialog::~OMCDialog()
{
	if(mTaskObserver != NULL)
		mTaskObserver->SetOwner(NULL);//observer may outlive us so it is very important to tell that we died

	//remove ourselves from linked list
	OMCDialog *prevLink = NULL;
	OMCDialog *oneLink = sChainHead;
	while(oneLink != NULL)
	{
		if(oneLink == this)
		{
			if(prevLink != NULL) //connect it to previous
				prevLink->next = this->next;
			else //or make it a head (prevLink is NULL only on first iteration)
				sChainHead = this->next;
			this->next = NULL;
			break;
		}
		prevLink = oneLink;
		oneLink = oneLink->next;
	}
}

//caller should NOT release the result string

CFStringRef
OMCDialog::GetDialogUniqueID()
{
	if(mDialogUniqueID != NULL)
		return mDialogUniqueID;

	CFObj<CFUUIDRef>  myUUID( ::CFUUIDCreate(kCFAllocatorDefault) );
	if(myUUID != NULL)
		mDialogUniqueID.Adopt( ::CFUUIDCreateString(kCFAllocatorDefault, myUUID) );

	return mDialogUniqueID;
}

void
OMCDialog::StartListening()
{
	CFObj<CFStringRef> portName( ::CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("OMCDialogControlPort-%@"), GetDialogUniqueID()) );
	mListener.StartListening(this, portName);
}


/*static*/
OMCDialog *	
OMCDialog::FindDialogByGUID(CFStringRef inGUID)
{
	if(inGUID == NULL)
		return NULL;

	OMCDialog *oneLink = sChainHead;
	while(oneLink != NULL)
	{
		CFStringRef oneGUID = oneLink->mDialogUniqueID;//do not generate if never requested before, cannot be equal in such case
		if( (oneGUID != NULL) && (CFStringCompare(oneGUID, inGUID, 0) == kCFCompareEqualTo) )
			return oneLink;

		oneLink = oneLink->next;
	}

	return NULL;
}

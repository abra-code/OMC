/*
 *  OMCDialog.mm
 *  Abracode
 *
 *  Created by Tomasz Kukielka on 3/2/08.
 *  Copyright 2008 Abracode. All rights reserved.
 *
 */

#include "OMCDialog.h"
#import "OMCControlAccessor.h"
#include "AppGroupIdentifier.h"
#include "OnMyCommand.h"
#include "OMCDialogControlHelpers.h"
#include "ACFType.h"
#include "OmcTaskNotification.h"

OMCDialog* sChainHead = nullptr;

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
OMCDialog::GetDialogUUID()
{
	if(mDialogUUID != NULL)
		return mDialogUUID;

	CFObj<CFUUIDRef>  myUUID( ::CFUUIDCreate(kCFAllocatorDefault) );
	if(myUUID != NULL)
        mDialogUUID.Adopt( ::CFUUIDCreateString(kCFAllocatorDefault, myUUID) );

	return mDialogUUID;
}

void
OMCDialog::StartListening()
{
	CFObj<CFStringRef> portName( ::CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%s.OMCDialogControlPort-%@"), GetAppGroupIdentifier(), GetDialogUUID()) );
	mListener.StartListening(this, portName);
}


/*static*/
ARefCountedObj<OMCDialog>
OMCDialog::FindDialogByUUID(CFStringRef inUUID)
{
	ARefCountedObj<OMCDialog> outDialog;
	if(inUUID == nullptr)
		return outDialog;

	OMCDialog *oneLink = sChainHead;
	while(oneLink != nullptr)
	{
		CFStringRef oneUUID = oneLink->mDialogUUID;//do not generate if never requested before, cannot be equal in such case
		if( (oneUUID != nullptr) && (CFStringCompare(oneUUID, inUUID, 0) == kCFCompareEqualTo) )
		{
			outDialog.Adopt(oneLink, kARefCountRetain);
			break;
		}

		oneLink = oneLink->next;
	}

	return outDialog;
}

//static
CFStringRef
OMCDialog::CreateControlValueString(CFTypeRef controlValue, CFDictionaryRef customProperties, UInt16 escSpecialCharsMode, bool isEnvStyle) noexcept
{
	CFStringRef newStrRef = nullptr;
	if(controlValue == nullptr)
		return nullptr;
	
	CFStringRef oneProperty = nullptr;
	if( !isEnvStyle && (customProperties != nullptr) ) //in environment variables we don't put escapings
	{
		oneProperty = ACFType<CFStringRef>::DynamicCast( CFDictionaryGetValue(customProperties, (const void *)kCustomEscapeMethodKey) );
		if(oneProperty != nullptr)
        {
            escSpecialCharsMode = GetEscapingMode(oneProperty);
        }
	}

	//it can be string or array of strings
	CFTypeID valType = ::CFGetTypeID( (CFTypeRef)controlValue );
	if( valType == ACFType<CFStringRef>::sTypeID )//regular string
	{
		newStrRef = CreateEscapedStringCopy( (CFStringRef)(CFTypeRef)controlValue, escSpecialCharsMode);
	}
	else if( valType == ACFType<CFArrayRef>::sTypeID )
	{
		CFStringRef prefix = nullptr;
		CFStringRef suffix = nullptr;
		CFStringRef separator =  CFSTR("\t"); //separate with tab byy default

		if(customProperties != nullptr)
		{
			oneProperty = ACFType<CFStringRef>::DynamicCast( CFDictionaryGetValue(customProperties, (const void *)kCustomPrefixKey) );
			if(oneProperty != nullptr)
				prefix = oneProperty;

			oneProperty = ACFType<CFStringRef>::DynamicCast( CFDictionaryGetValue(customProperties, (const void *)kCustomSuffixKey) );
			if(oneProperty != nullptr)
				suffix = oneProperty;

			oneProperty = ACFType<CFStringRef>::DynamicCast( CFDictionaryGetValue(customProperties, (const void *)kCustomSeparatorKey) );
			if(oneProperty != nullptr)
				separator = oneProperty;

		}
		newStrRef = CreateCombinedString( (CFArrayRef)(CFTypeRef)controlValue, separator, prefix, suffix, escSpecialCharsMode );
	}

	return newStrRef;
}

Boolean
OMCDialog::IsPredefinedDialogCommandID(CFStringRef inCommandID) noexcept
{
    if(inCommandID == NULL)
        return false;

    if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("omc.dialog.terminate.ok"), 0))
        return true;

    if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("omc.dialog.terminate.cancel"), 0))
        return true;

    if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("omc.dialog.initialize"), 0))
        return true;

    if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("omc.dialog.ok"), 0))
        return true;
    
    if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("omc.dialog.cancel"), 0))
        return true;

    if(CFStringGetLength(inCommandID) != 4)
        return false;
    
    //Carbon legacy - only 4 chars
    if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("ok  "), 0))
        return true;
    
    if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("cncl"), 0))
        return true;

    if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("ini!"), 0))
        return true;

    if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("end!"), 0))
        return true;

    if(kCFCompareEqualTo == CFStringCompare(inCommandID, CFSTR("cnc!"), 0))
        return true;
    
    return false;
}

#pragma mark - Control value access via controller

CFTypeRef
OMCDialog::CopyControlValue(CFStringRef inControlID, CFStringRef inControlPart, SelectionIterator *inSelIterator, CFDictionaryRef *outCustomProperties) noexcept
{
	if(outCustomProperties != NULL)
		*outCustomProperties = NULL;

	id outValue = NULL;

    @try
    {
        if(mControlAccessor != NULL)
        {
            id<OMCControlAccessor> controller = (__bridge id<OMCControlAccessor>)mControlAccessor;
            outValue = [controller controlValueForID:(__bridge NSString *)inControlID
                                             forPart:(__bridge NSString *)inControlPart
                                        withIterator:inSelIterator
                                       outProperties:outCustomProperties];
        }
    }
    @catch (NSException *localException)
    {
        NSLog(@"OMCDialog::CopyControlValue received exception: %@", localException);
    }

    return (CFTypeRef)CFBridgingRetain(outValue);
}

void
OMCDialog::CopyAllControlValues(CFSetRef requestedNibControls, SelectionIterator *inSelIterator) noexcept
{
    if(mControlValues == nullptr)
        mControlValues.Adopt(CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                        0,
                                                        &kCFTypeDictionaryKeyCallBacks,
                                                        &kCFTypeDictionaryValueCallBacks),
                                                        kCFObjDontRetain);

    if(mControlCustomProperties == nullptr)
        mControlCustomProperties.Adopt(CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                                    0,
                                                                    &kCFTypeDictionaryKeyCallBacks,
                                                                    &kCFTypeDictionaryValueCallBacks),
                                                                    kCFObjDontRetain);

    @try
    {
        if(mControlAccessor != NULL)
        {
            id<OMCControlAccessor> controller = (__bridge id<OMCControlAccessor>)mControlAccessor;
            [controller allControlValues:(__bridge NSMutableDictionary *)mControlValues.Get()
                            andProperties:(__bridge NSMutableDictionary *)mControlCustomProperties.Get()
                             withIterator:inSelIterator];
        }
    }
    @catch (NSException *localException)
    {
        NSLog(@"OMCDialog::CopyAllControlValues received exception: %@", localException);
    }
}


// port communication support for dialog
// when this port is set-up the command line tool "omc_dialog_control" sends messages to this port
// instead of saving to file and wait for command to finish
//inData is a plist XML data in exactly the same format as read from temp plist file for disk-based communication

CFDataRef
OMCDialog::ReceivePortMessage( SInt32 msgid, CFDataRef inData ) noexcept
{
	if( mControlAccessor == NULL )
		return NULL;

	CFObj<CFPropertyListRef> thePlist( CFPropertyListCreateWithData( kCFAllocatorDefault, inData,
                                                                       kCFPropertyListImmutable, nullptr, nullptr) );
	CFDictionaryRef plistDict = ACFType<CFDictionaryRef>::DynamicCast( (CFPropertyListRef)thePlist );

    @try
    {
        if(plistDict != NULL)
        {
            id<OMCControlAccessor> controller = (__bridge id<OMCControlAccessor>)mControlAccessor;
            [controller setControlValues:plistDict];
        }
    }
    @catch (NSException *localException)
    {
        NSLog(@"OMCDialog::ReceivePortMessage received exception: %@", localException);
    }

	return NULL;
}

void
OMCDialog::ReceiveNotification(void *ioData) noexcept
{
	if( (ioData == NULL) || (mControlAccessor == NULL) )
		return;

	OmcTaskData *taskData = (OmcTaskData *)ioData;

	switch(taskData->messageID)
	{
		case kOmcTaskFinished:
		{
			if( taskData->dataType == kOmcDataTypeBoolean )
			{
			}

			CFObj<CFDictionaryRef> controlValues( ReadControlValuesFromPlist(GetDialogUUID()) );

            @try
            {
                if(controlValues != NULL)
                {
                    id<OMCControlAccessor> controller = (__bridge id<OMCControlAccessor>)mControlAccessor;
                    [controller setControlValues:(CFDictionaryRef)controlValues];
                }
            }
            @catch (NSException *localException)
            {
                NSLog(@"OMCDialog::ReceiveNotification received exception: %@", localException);
            }
		}
		break;

		case kOmcTaskProgress:
			;
		break;
		
		default:
		break;
	}
}

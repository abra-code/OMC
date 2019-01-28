//**************************************************************************************
// Filename:	NavDialogs.cp
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright � 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	
//
//**************************************************************************************

#include "NavDialogs.h"
#include "CFObj.h"
#include "DebugSettings.h"

//different nav dialogs may be used within the same app for different things
//adding unique value to each key made of ::CFHash(inClientName)
//will give us unique values for different dialogs within the same app

enum
{
	kSaveAsKeyUnique = 1,
	kChooseFileKeyUnique,
	kChooseFolderKeyUnique,
	kChooseObjectKeyUnique,
	kFSRefChooseFolderUnique,
	kFSRefChooseFileUnique,
	kAEListChooseFileUnique,
	kAEListChooseFolderUnique,
	kAEListChooseObjectUnique
};


extern "C"
{
	
static pascal void NavEventProc( const NavEventCallbackMessage callbackSelector, 
								NavCBRecPtr callbackParms, 
								NavCallBackUserData callbackUD );

	
//caller responsible for releasing the CFURLRef path
Boolean
CreatePathFromSaveAsDialog(CFURLRef &outRef, CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags /*= 0*/)
{
	outRef = NULL;

	NavDialogCreationOptions dialogOptions;
	OSStatus err = ::NavGetDefaultDialogCreationOptions( &dialogOptions );
	if( err != noErr)
		return	false;
		
	dialogOptions.optionFlags = kNavNoTypePopup | kNavAllowPreviews | kNavSupportPackages | kNavAllowOpenPackages | inAdditonalNavFlags;
	dialogOptions.modality = kWindowModalityAppModal;
	dialogOptions.clientName = inClientName;
	dialogOptions.message = inMessage;
	dialogOptions.saveFileName = inDefaultName;

	if(inClientName != NULL)
		dialogOptions.preferenceKey = ::CFHash(inClientName) + kSaveAsKeyUnique;//more or less unique value - enough for this purpose

	Boolean outOK = false;

	NavEventUPP navEventHandlerUPP = NULL;
	void *eventHandlerData = NULL;
	if(inDefaultLocation != NULL)
	{
		navEventHandlerUPP = ::NewNavEventUPP( NavEventProc );
		eventHandlerData = (void *)inDefaultLocation;
	}
	
	NavDialogRef	dialogRef = NULL;
	err = ::NavCreatePutFileDialog(&dialogOptions, '????', '????', navEventHandlerUPP, eventHandlerData, &dialogRef);

	if( (err == noErr) && (dialogRef != NULL) )
	{
		err = ::NavDialogRun( dialogRef );
		if( err == noErr )
		{
			NavUserAction theAction = ::NavDialogGetUserAction( dialogRef );
			if( (theAction != kNavUserActionCancel) && (theAction != kNavUserActionNone) )
			{
				NavReplyRecord		reply;
				err = ::NavDialogGetReply(dialogRef, &reply);
				if(err == noErr)
				{
					outRef = FURLCreateFromNavReply(&reply);
					::NavDisposeReply( &reply );
					outOK = true;
				}
			}
		}
		
		 ::NavDialogDispose( dialogRef );
	}

    if( navEventHandlerUPP != NULL )
	{
		DisposeNavEventUPP( navEventHandlerUPP );
		navEventHandlerUPP = NULL;
	}

	return outOK;
}

//caller responsible for releasing non-NULL outRef
Boolean
CreatePathFromChooseFileDialog(CFURLRef &outRef, CFStringRef inClientName, CFStringRef inMessage, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags /*= 0*/)
{
	outRef = NULL;

	NavDialogCreationOptions dialogOptions;
	OSStatus err = ::NavGetDefaultDialogCreationOptions( &dialogOptions );
	if( err != noErr)
		return	false;
	
	dialogOptions.optionFlags = kNavNoTypePopup | kNavAllowPreviews | kNavSupportPackages | kNavAllowOpenPackages | inAdditonalNavFlags;
	dialogOptions.modality = kWindowModalityAppModal;
	dialogOptions.clientName = inClientName;
	dialogOptions.message = inMessage;
	if(inClientName != NULL)
		dialogOptions.preferenceKey = ::CFHash(inClientName) + kChooseFileKeyUnique;//more or less unique value - enough for this purpose


	Boolean outOK = false;

	NavEventUPP navEventHandlerUPP = NULL;
	void *eventHandlerData = NULL;
	if(inDefaultLocation != NULL)
	{
		navEventHandlerUPP = ::NewNavEventUPP( NavEventProc );
		eventHandlerData = (void *)inDefaultLocation;
	}

	NavDialogRef	dialogRef = NULL;
	err = ::NavCreateChooseFileDialog( &dialogOptions,
									NULL, //inTypeList
									navEventHandlerUPP,
									NULL, //inPreviewProc
									NULL, //inFilterProc
									eventHandlerData, //inClientData
									&dialogRef);

	if( (err == noErr) && (dialogRef != NULL) )
	{
		err = ::NavDialogRun( dialogRef );
		if( err == noErr )
		{
			NavUserAction theAction = ::NavDialogGetUserAction( dialogRef );
			if( (theAction != kNavUserActionCancel) && (theAction != kNavUserActionNone) )
			{
				NavReplyRecord		reply;
				err = ::NavDialogGetReply(dialogRef, &reply);
				if(err == noErr)
				{
					outRef = FURLCreateFromNavReply(&reply);
					::NavDisposeReply( &reply );
					outOK = true;
				}
			}
		}
		
		 ::NavDialogDispose( dialogRef );
	}

    if( navEventHandlerUPP != NULL )
	{
		DisposeNavEventUPP( navEventHandlerUPP );
		navEventHandlerUPP = NULL;
	}

	return outOK;
}

//caller responsible for releasing non-NULL outRef

Boolean
CreatePathFromChooseFolderDialog(CFURLRef &outRef, CFStringRef inClientName, CFStringRef inMessage, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags /*= 0*/)
{
	outRef = NULL;

	NavDialogCreationOptions dialogOptions;
	OSStatus err = ::NavGetDefaultDialogCreationOptions( &dialogOptions );
	if( err != noErr)
		return false;
	
	dialogOptions.optionFlags = kNavNoTypePopup | kNavAllowPreviews | kNavSupportPackages | kNavAllowOpenPackages | inAdditonalNavFlags;
	dialogOptions.modality = kWindowModalityAppModal;
	dialogOptions.clientName = inClientName;
	dialogOptions.message = inMessage;
	if(inClientName != NULL)
		dialogOptions.preferenceKey = ::CFHash(inClientName) + kChooseFolderKeyUnique;//more or less unique value - enough for this purpose

	Boolean outOK = false;

	NavEventUPP navEventHandlerUPP = NULL;
	void *eventHandlerData = NULL;
	if(inDefaultLocation != NULL)
	{
		navEventHandlerUPP = ::NewNavEventUPP( NavEventProc );
		eventHandlerData = (void *)inDefaultLocation;
	}

	NavDialogRef	dialogRef = NULL;
	err = ::NavCreateChooseFolderDialog( &dialogOptions,
									navEventHandlerUPP,
									NULL, //inFilterProc
									eventHandlerData, //inClientData
									&dialogRef);

	if( (err == noErr) && (dialogRef != NULL) )
	{
		err = ::NavDialogRun( dialogRef );
		if( err == noErr )
		{
			NavUserAction theAction = ::NavDialogGetUserAction( dialogRef );
			if( (theAction != kNavUserActionCancel) && (theAction != kNavUserActionNone) )
			{
				NavReplyRecord		reply;
				err = ::NavDialogGetReply(dialogRef, &reply);
				if(err == noErr)
				{
					outRef = FURLCreateFromNavReply(&reply);
					::NavDisposeReply( &reply );
					outOK = true;
				}
			}
		}
		
		 ::NavDialogDispose( dialogRef );
	}

    if( navEventHandlerUPP != NULL )
	{
		DisposeNavEventUPP( navEventHandlerUPP );
		navEventHandlerUPP = NULL;
	}

	return outOK;
}

//caller responsible for releasing non-NULL outRef
Boolean
CreatePathFromChooseObjectDialog(CFURLRef &outRef, CFStringRef inClientName, CFStringRef inMessage, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags /*= 0*/)
{
	outRef = NULL;

	NavDialogCreationOptions dialogOptions;
	OSStatus err = ::NavGetDefaultDialogCreationOptions( &dialogOptions );
	if( err != noErr)
		return	false;
	
	dialogOptions.optionFlags = kNavNoTypePopup | kNavAllowPreviews | kNavSupportPackages | kNavAllowOpenPackages | inAdditonalNavFlags;
	dialogOptions.modality = kWindowModalityAppModal;
	dialogOptions.clientName = inClientName;
	dialogOptions.message = inMessage;
	if(inClientName != NULL)
		dialogOptions.preferenceKey = ::CFHash(inClientName) + kChooseObjectKeyUnique;//more or less unique value - enough for this purpose

	Boolean outOK = false;

	NavEventUPP navEventHandlerUPP = NULL;
	void *eventHandlerData = NULL;
	if(inDefaultLocation != NULL)
	{
		navEventHandlerUPP = ::NewNavEventUPP( NavEventProc );
		eventHandlerData = (void *)inDefaultLocation;
	}

	NavDialogRef	dialogRef = NULL;
	err = ::NavCreateChooseObjectDialog( &dialogOptions,
									navEventHandlerUPP,
									NULL, //inPreviewProc
									NULL, //inFilterProc
									eventHandlerData, //inClientData
									&dialogRef);

	if( (err == noErr) && (dialogRef != NULL) )
	{
		err = ::NavDialogRun( dialogRef );
		if( err == noErr )
		{
			NavUserAction theAction = ::NavDialogGetUserAction( dialogRef );
			if( (theAction != kNavUserActionCancel) && (theAction != kNavUserActionNone) )
			{
				NavReplyRecord		reply;
				err = ::NavDialogGetReply(dialogRef, &reply);
				if(err == noErr)
				{
					outRef = FURLCreateFromNavReply(&reply);
					::NavDisposeReply( &reply );
					outOK = true;
				}
			}
		}
		
		 ::NavDialogDispose( dialogRef );
	}

    if( navEventHandlerUPP != NULL )
	{
		DisposeNavEventUPP( navEventHandlerUPP );
		navEventHandlerUPP = NULL;
	}

	return outOK;
}

#pragma mark ---- FSRef versions ----

Boolean
ChooseFolderDialog(FSRef &outFolderRef, CFStringRef inClientName, CFStringRef inMessage, CFStringRef inActionButtLabel, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags /*= 0*/)
{
	DEBUG_CSTR("Entering ChooseFolderDialog.\n");

	NavDialogCreationOptions dialogOptions;
	OSStatus err = ::NavGetDefaultDialogCreationOptions( &dialogOptions );
	if( err != noErr)
		return	false;
	
	dialogOptions.optionFlags = kNavNoTypePopup | kNavAllowPreviews | kNavSupportPackages | kNavAllowOpenPackages | inAdditonalNavFlags;
	dialogOptions.modality = kWindowModalityAppModal;
	dialogOptions.clientName = inClientName;
	dialogOptions.message = inMessage;
	dialogOptions.actionButtonLabel = inActionButtLabel;
	
	if(inClientName != NULL)
		dialogOptions.preferenceKey = ::CFHash(inClientName) + kFSRefChooseFolderUnique;//more or less unique value - enough for this purpose

	Boolean outOK = false;

	NavEventUPP navEventHandlerUPP = NULL;
	void *eventHandlerData = NULL;
	if(inDefaultLocation != NULL)
	{
		navEventHandlerUPP = ::NewNavEventUPP( NavEventProc );
		eventHandlerData = (void *)inDefaultLocation;
	}

	NavDialogRef	dialogRef = NULL;

	err = ::NavCreateChooseFolderDialog( &dialogOptions,
									navEventHandlerUPP,
									NULL, //inFilterProc
									eventHandlerData, //inClientData
									&dialogRef);
				
	DEBUG_CSTR("ChooseFolderDialog. NavCreateChooseFolderDialog returned: %d\n", (int)err);

	if( (err == noErr) && (dialogRef != NULL) )
	{
		err = ::NavDialogRun( dialogRef );
		DEBUG_CSTR("ChooseFolderDialog. NavDialogRun returned: %d\n", (int)err);
		if( err == noErr )
		{
			NavUserAction theAction = ::NavDialogGetUserAction( dialogRef );

			DEBUG_CSTR("ChooseFolderDialog. NavDialogGetUserAction reply is: %d\n", (int)theAction);
			
			if( (theAction != kNavUserActionCancel) && (theAction != kNavUserActionNone) )
			{
				NavReplyRecord		reply;
				err = ::NavDialogGetReply(dialogRef, &reply);
				DEBUG_CSTR("ChooseFolderDialog. NavDialogGetReply returned: %d\n", (int)err);
				if(err == noErr)
				{
					err = GetFSRefFromNavReply(&reply, outFolderRef);
					DEBUG_CSTR("ChooseFolderDialog. GetFSRefFromNavReply returned: %d\n", (int)err);
					::NavDisposeReply( &reply );
					outOK = (err == noErr);
				}
			}
		}
		
		 ::NavDialogDispose( dialogRef );
	}

    if( navEventHandlerUPP != NULL )
	{
		DisposeNavEventUPP( navEventHandlerUPP );
		navEventHandlerUPP = NULL;
	}

	return outOK;
}

Boolean
ChooseFileDialog(FSRef &outRef, CFStringRef inClientName, CFStringRef inMessage, CFStringRef inActionButtLabel, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags /*= 0*/)
{
	NavDialogCreationOptions dialogOptions;
	OSStatus err = ::NavGetDefaultDialogCreationOptions( &dialogOptions );
	if( err != noErr)
		return	false;
	
	dialogOptions.optionFlags = kNavNoTypePopup | kNavAllowPreviews | kNavSupportPackages | kNavAllowOpenPackages | inAdditonalNavFlags;
	dialogOptions.modality = kWindowModalityAppModal;
	dialogOptions.clientName = inClientName;
	dialogOptions.message = inMessage;
	dialogOptions.actionButtonLabel = inActionButtLabel;
	
	if(inClientName != NULL)
		dialogOptions.preferenceKey = ::CFHash(inClientName) + kFSRefChooseFileUnique;//more or less unique value - enough for this purpose

	Boolean outOK = false;

	NavEventUPP navEventHandlerUPP = NULL;
	void *eventHandlerData = NULL;
	if(inDefaultLocation != NULL)
	{
		navEventHandlerUPP = ::NewNavEventUPP( NavEventProc );
		eventHandlerData = (void *)inDefaultLocation;
	}

	NavDialogRef	dialogRef = NULL;
	err = ::NavCreateChooseFileDialog( &dialogOptions,
									NULL, //inTypeList
									navEventHandlerUPP,
									NULL, //inPreviewProc
									NULL, //inFilterProc
									eventHandlerData, //inClientData
									&dialogRef);

	if( (err == noErr) && (dialogRef != NULL) )
	{
		err = ::NavDialogRun( dialogRef );
		if( err == noErr )
		{
			NavUserAction theAction = ::NavDialogGetUserAction( dialogRef );
			if( (theAction != kNavUserActionCancel) && (theAction != kNavUserActionNone) )
			{
				NavReplyRecord		reply;
				err = ::NavDialogGetReply(dialogRef, &reply);
				if(err == noErr)
				{
					err = GetFSRefFromNavReply(&reply, outRef);
					::NavDisposeReply( &reply );
					outOK = (err == noErr);
				}
			}
		}
		
		 ::NavDialogDispose( dialogRef );
	}

    if( navEventHandlerUPP != NULL )
	{
		DisposeNavEventUPP( navEventHandlerUPP );
		navEventHandlerUPP = NULL;
	}

	return outOK;
}


#pragma mark -

CFURLRef
FURLCreateFromNavReply(const NavReplyRecord * navReply)
{
    FSRef parentFSRef;
    AEKeyword theAEKeyword;
    DescType typeCode;
    Size actualSize;
    
    OSErr theErr = ::AEGetNthPtr( &(navReply->selection), 1, typeFSRef, &theAEKeyword, &typeCode, &parentFSRef,  sizeof(FSRef), &actualSize);

    if(theErr == noErr)
    {
    	CFObj<CFURLRef> parentURLRef( ::CFURLCreateFromFSRef(kCFAllocatorDefault, &parentFSRef) );
    	if(parentURLRef != NULL)
    	{
			if(navReply->saveFileName != NULL)
			{
				return ::CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, parentURLRef, navReply->saveFileName, false);
			}
			else
				return parentURLRef.Detach();
		}
    }

    return NULL;
}


OSStatus
GetFSRefFromNavReply(const NavReplyRecord * navReply, FSRef &outFSRef)
{
    AEKeyword theAEKeyword;
    DescType typeCode;
    Size actualSize;
	
	OSErr err;
	
	DEBUG_CSTR("GetFSRefFromNavReply. NavReplyRecord: version=%d, validRecord=%d\n", (int)navReply->version, (int)navReply->validRecord);
    DEBUG_CSTR("GetFSRefFromNavReply. navReply->selection.descriptorType = %d\n", (int)navReply->selection.descriptorType);
	
	long theCount = 0;
	err = AECountItems ( &(navReply->selection), &theCount);

#if _DEBUG_
    DEBUG_CSTR("GetFSRefFromNavReply. AECountItems returned err = %d, theCount=%d\n", (int)err, (int)theCount);
	
	CFShow( navReply->saveFileName );
	
	AEDesc aeDesc;
	err = AEGetNthDesc ( &(navReply->selection), 1, typeWildCard, &theAEKeyword, &aeDesc);
    DEBUG_CSTR("GetFSRefFromNavReply. AEGetNthDesc returned err = %d, theAEKeyword=0x%.8X\n", (int)err, (int)theAEKeyword);
#endif //_DEBUG_

	if(theCount > 0)
	{
		err = ::AEGetNthPtr( &(navReply->selection), 1, typeFSRef, &theAEKeyword, &typeCode, &outFSRef,  sizeof(FSRef), &actualSize);
		DEBUG_CSTR("GetFSRefFromNavReply. AEGetNthPtr returned theAEKeyword=0x%.8X, typeCode=0x%.8X\n", (int)theAEKeyword, (int)typeCode);
	}
	else
	{
		err = fnfErr;
	}
	
	return err;
}

#pragma mark -

Boolean
GetAEListFromChooseFileDialog(AEDescList &outList, CFStringRef inClientName, CFStringRef inMessage, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags /*= 0*/)
{
	NavDialogCreationOptions dialogOptions;
	OSStatus err = ::NavGetDefaultDialogCreationOptions( &dialogOptions );
	if( err != noErr)
		return	false;
	
	dialogOptions.optionFlags = kNavNoTypePopup | kNavAllowPreviews | kNavSupportPackages | kNavAllowOpenPackages | inAdditonalNavFlags;
	dialogOptions.modality = kWindowModalityAppModal;
	dialogOptions.clientName = inClientName;
	dialogOptions.message = inMessage;
	if(inClientName != NULL)
		dialogOptions.preferenceKey = ::CFHash(inClientName) + kAEListChooseFileUnique;//more or less unique value - enough for this purpose


	Boolean outOK = false;

	NavEventUPP navEventHandlerUPP = NULL;
	void *eventHandlerData = NULL;
	if(inDefaultLocation != NULL)
	{
		navEventHandlerUPP = ::NewNavEventUPP( NavEventProc );
		eventHandlerData = (void *)inDefaultLocation;
	}

	NavDialogRef	dialogRef = NULL;
	err = ::NavCreateChooseFileDialog( &dialogOptions,
									NULL, //inTypeList
									navEventHandlerUPP,
									NULL, //inPreviewProc
									NULL, //inFilterProc
									eventHandlerData, //inClientData
									&dialogRef);

	if( (err == noErr) && (dialogRef != NULL) )
	{
		err = ::NavDialogRun( dialogRef );
		if( err == noErr )
		{
			NavUserAction theAction = ::NavDialogGetUserAction( dialogRef );
			if( (theAction != kNavUserActionCancel) && (theAction != kNavUserActionNone) )
			{
				NavReplyRecord		reply;
				err = ::NavDialogGetReply(dialogRef, &reply);
				if(err == noErr)
				{
					err = ::AEDuplicateDesc( &(reply.selection), &outList);
					::NavDisposeReply( &reply );
					outOK = (err == noErr);
				}
			}
		}
		
		 ::NavDialogDispose( dialogRef );
	}

    if( navEventHandlerUPP != NULL )
	{
		DisposeNavEventUPP( navEventHandlerUPP );
		navEventHandlerUPP = NULL;
	}

	return outOK;
}


Boolean
GetAEListFromChooseFolderDialog(AEDescList &outList, CFStringRef inClientName, CFStringRef inMessage, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags /*= 0*/)
{
	NavDialogCreationOptions dialogOptions;
	OSStatus err = ::NavGetDefaultDialogCreationOptions( &dialogOptions );
	if( err != noErr)
		return	false;
	
	dialogOptions.optionFlags = kNavNoTypePopup | kNavAllowPreviews | kNavSupportPackages | kNavAllowOpenPackages | inAdditonalNavFlags;
	dialogOptions.modality = kWindowModalityAppModal;
	dialogOptions.clientName = inClientName;
	dialogOptions.message = inMessage;
	if(inClientName != NULL)
		dialogOptions.preferenceKey = ::CFHash(inClientName) + kAEListChooseFolderUnique;//more or less unique value - enough for this purpose

	Boolean outOK = false;

	NavEventUPP navEventHandlerUPP = NULL;
	void *eventHandlerData = NULL;
	if(inDefaultLocation != NULL)
	{
		navEventHandlerUPP = ::NewNavEventUPP( NavEventProc );
		eventHandlerData = (void *)inDefaultLocation;
	}

	NavDialogRef	dialogRef = NULL;
	err = ::NavCreateChooseFolderDialog( &dialogOptions,
									navEventHandlerUPP,
									NULL, //inFilterProc
									eventHandlerData, //inClientData
									&dialogRef);

	if( (err == noErr) && (dialogRef != NULL) )
	{
		err = ::NavDialogRun( dialogRef );
		if( err == noErr )
		{
			NavUserAction theAction = ::NavDialogGetUserAction( dialogRef );
			if( (theAction != kNavUserActionCancel) && (theAction != kNavUserActionNone) )
			{
				NavReplyRecord		reply;
				err = ::NavDialogGetReply(dialogRef, &reply);
				if(err == noErr)
				{
					err = ::AEDuplicateDesc( &(reply.selection), &outList);
					::NavDisposeReply( &reply );
					outOK = (err == noErr);
				}
			}
		}
		
		 ::NavDialogDispose( dialogRef );
	}

    if( navEventHandlerUPP != NULL )
	{
		DisposeNavEventUPP( navEventHandlerUPP );
		navEventHandlerUPP = NULL;
	}

	return outOK;
}

Boolean
GetAEListFromChooseObjectDialog(AEDescList &outList, CFStringRef inClientName, CFStringRef inMessage, CFURLRef inDefaultLocation, UInt32 inAdditonalNavFlags /*= 0*/)
{
	NavDialogCreationOptions dialogOptions;
	OSStatus err = ::NavGetDefaultDialogCreationOptions( &dialogOptions );
	if( err != noErr)
		return	false;
	
	dialogOptions.optionFlags = kNavNoTypePopup | kNavAllowPreviews | kNavSupportPackages | kNavAllowOpenPackages | inAdditonalNavFlags;
	dialogOptions.modality = kWindowModalityAppModal;
	dialogOptions.clientName = inClientName;
	dialogOptions.message = inMessage;
	if(inClientName != NULL)
		dialogOptions.preferenceKey = ::CFHash(inClientName) + kAEListChooseObjectUnique;//more or less unique value - enough for this purpose

	Boolean outOK = false;

	NavEventUPP navEventHandlerUPP = NULL;
	void *eventHandlerData = NULL;
	if(inDefaultLocation != NULL)
	{
		navEventHandlerUPP = ::NewNavEventUPP( NavEventProc );
		eventHandlerData = (void *)inDefaultLocation;
	}

	NavDialogRef	dialogRef = NULL;
	err = ::NavCreateChooseObjectDialog( &dialogOptions,
									navEventHandlerUPP,
									NULL, //inPreviewProc
									NULL, //inFilterProc
									eventHandlerData, //inClientData
									&dialogRef);

	if( (err == noErr) && (dialogRef != NULL) )
	{
		err = ::NavDialogRun( dialogRef );
		if( err == noErr )
		{
			NavUserAction theAction = ::NavDialogGetUserAction( dialogRef );
			if( (theAction != kNavUserActionCancel) && (theAction != kNavUserActionNone) )
			{
				NavReplyRecord		reply;
				err = ::NavDialogGetReply(dialogRef, &reply);
				if(err == noErr)
				{
					err = ::AEDuplicateDesc( &(reply.selection), &outList);
					::NavDisposeReply( &reply );
					outOK = (err == noErr);
				}
			}
		}
		
		 ::NavDialogDispose( dialogRef );
	}
 
	if( navEventHandlerUPP != NULL )
	{
		DisposeNavEventUPP( navEventHandlerUPP );
		navEventHandlerUPP = NULL;
	}

	return outOK;
}

#pragma mark -

static pascal void NavEventProc( const NavEventCallbackMessage callbackSelector, 
								NavCBRecPtr callbackParms, 
								NavCallBackUserData callbackUD )
// Callback to handle event passing betwwn the navigation dialogs and the applicatio
{
	OSStatus theStatus = noErr;

	switch ( callbackSelector )
	{	
        case kNavCBStart:
		{
			// any initial set up like custom control state is set here
			if(callbackUD != NULL)
			{
				CFURLRef defaultLocationURL = (CFURLRef)callbackUD;
				FSRef defaultFolderRef;
				if( ::CFURLGetFSRef(defaultLocationURL, &defaultFolderRef) )
				{
					AEDesc defaultLocation= {typeNull, NULL};
					theStatus = ::AECreateDesc(
									typeFSRef,
									&defaultFolderRef,
									sizeof(FSRef),
									&defaultLocation );
					if(theStatus == noErr)
						theStatus = ::NavCustomControl(callbackParms->context, kNavCtlSetLocation, (void*)&defaultLocation);
				}
			}
		}
		break;
        
		case kNavCBCustomize:
			// add custom controls to the Nav dialog here
		break;

		case kNavCBEvent:
		{
			switch (callbackParms->eventData.eventDataParms.event->what)
			{
				case updateEvt:
				case activateEvt:
//					HandleEvent(callbackParms->eventData.eventDataParms.event);
				break;
			}
		}
		break;

		case kNavCBUserAction:
		{
			// Call HandleNavUserAction
//			HandleNavUserAction( callbackParms->context, callbackParms->userAction, callbackUD );
		}
		break;
	
		case kNavCBTerminate:
		{
			// Auto-dispose the dialog
//			NavDialogDispose( callbackParms->context );
		}
	}
}

}//extern "C"

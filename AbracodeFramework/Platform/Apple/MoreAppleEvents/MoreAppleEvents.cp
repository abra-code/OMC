/*
	File:		MoreAppleEvents.cp

	Contains:	Apple Event Manager utilities.

	DRI:		George Warner

	Copyright:	Copyright (c) 2000-2001 by Apple Computer, Inc., All Rights Reserved.

	Disclaimer:	IMPORTANT:  This Apple software is supplied to you by Apple Computer, Inc.
				("Apple") in consideration of your agreement to the following terms, and your
				use, installation, modification or redistribution of this Apple software
				constitutes acceptance of these terms.  If you do not agree with these terms,
				please do not use, install, modify or redistribute this Apple software.

				In consideration of your agreement to abide by the following terms, and subject
				to these terms, Apple grants you a personal, non-exclusive license, under AppleÕs
				copyrights in this original Apple software (the "Apple Software"), to use,
				reproduce, modify and redistribute the Apple Software, with or without
				modifications, in source and/or binary forms; provided that if you redistribute
				the Apple Software in its entirety and without modifications, you must retain
				this notice and the following text and disclaimers in all such redistributions of
				the Apple Software.  Neither the name, trademarks, service marks or logos of
				Apple Computer, Inc. may be used to endorse or promote products derived from the
				Apple Software without specific prior written permission from Apple.  Except as
				expressly stated in this notice, no other rights or licenses, express or implied,
				are granted by Apple herein, including but not limited to any patent rights that
				may be infringed by your derivative works or by other works in which the Apple
				Software may be incorporated.

				The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
				WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
				WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
				PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
				COMBINATION WITH YOUR PRODUCTS.

				IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
				CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
				GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
				ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR DISTRIBUTION
				OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY OF CONTRACT, TORT
				(INCLUDING NEGLIGENCE), STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN
				ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

	Change History:
				This is a heavily trimmed and modified version of MoreAppleEvents
				The original licence above allows redistribution of modified copies
*/

//**********	Project Headers			****************************************
#include "MoreAppleEvents.h"
#include "StAEDesc.h"

static AEIdleUPP gAEIdleUPP = nil;

/********************************************************************************
    A very simple idle function. It simply ignors any event it receives,
    returns 30 for the sleep time and nil for the mouse region.
    
    Your application should supply an idle function that handles any events it
    might receive. This is especially important if your application has any windows.
    
    Also see:
        IM:IAC for details about idle functions.
        Pending Update Perils technote for more about handling low-level events.
*/
Boolean MoreAESimpleIdleFunction( EventRecord* event,
                                        SInt32* sleepTime,
                                        RgnHandle* mouseRgn );

/********************************************************************************
 Given a property type, create an new object descriptor for that property,
 contained by containerObj.
 
 pPropertyType        input:    Property type to use for object.
 pContainerAEDesc    input:    Pointer to container object for object being created.
 propertyObjPtr    input:    Pointer to null AEDesc.
 output:    A property object.
 
 RESULT CODES
 ____________
 noErr                    0    No error
 paramErr              -50    Error in parameter list
 memFullErr             -108    Not enough room in heap zone
 errAECoercionFail     -1700    Data could not be coerced to the requested
 Apple event data type
 errAEWrongDataType    -1703    Wrong Apple event data type
 errAENotAEDesc        -1704    Not a valid descriptor record
 errAEBadListItem    -1705    Operation involving a list item failed
 */
OSErr MoreAEOCreatePropertyObject( const DescType pPropertyType,
									AEDesc *pContainerAEDesc,
									AEDesc *propertyObjPtr )
{
	StAEDesc propDesc;
	OSErr anErr = AECreateDesc( typeType, &pPropertyType, sizeof( pPropertyType ), &propDesc );
	if ( noErr == anErr )
	{
		anErr = CreateObjSpecifier( cProperty, pContainerAEDesc, formPropertyID,
									&propDesc, false, propertyObjPtr );
	}

	return anErr;
}//end MoreAEOCreatePropertyObject


/********************************************************************************
 Given selection type, create an new object descriptor for a selection,
 contained by containerObj.
 
 pSelectionAEDesc    input:    Selection type to use for object.
 pContainerAEDesc    input:    Pointer to container object for object being created.
 pSelectionObject        input:    Pointer to null AEDesc.
 output:    A property object.
 
 RESULT CODES
 ____________
 noErr                    0    No error
 paramErr              -50    Error in parameter list
 memFullErr             -108    Not enough room in heap zone
 errAECoercionFail     -1700    Data could not be coerced to the requested
 Apple event data type
 errAEWrongDataType    -1703    Wrong Apple event data type
 errAENotAEDesc        -1704    Not a valid descriptor record
 errAEBadListItem    -1705    Operation involving a list item failed
 */

//inObjectType is usually cObject but can be specific

OSErr MoreAEOCreateSelectionObject( const DescType pSelectionAEDesc,
									AEDesc *pContainerAEDesc,
									AEDesc *pSelectionObject,
									const DescType inObjectType)
{
	StAEDesc selectionDesc;
	OSErr anErr = AECreateDesc( typeAbsoluteOrdinal, &pSelectionAEDesc, sizeof( pSelectionAEDesc ), &selectionDesc );
	if ( noErr == anErr )
	{
		anErr = CreateObjSpecifier( inObjectType, pContainerAEDesc, formAbsolutePosition,
									&selectionDesc, false, pSelectionObject );
	}
	return anErr;
}//end MoreAEOCreateSelectionObject


//*******************************************************************************
#pragma mark ==> Create AEvents ¥


/********************************************************************************
	Create and return an AppleEvent of the given class and ID. The event will be
	targeted at the application with the specific creator.

	psnPtr			==>		Pointer to the PSN to target the event with.
	pAEEventClass	==>		The class of the event to be created.
	pAEEventID		==>		The ID of the event to be created.
	pAppleEvent		==>		Pointer to an AppleEvent where the
							event record will be returned.
					<==		The Apple event.
	
	RESULT CODES
	____________
	noErr			   0	No error	
	memFullErr		-108	Not enough room in heap zone	
	procNotFound	Ð600	No eligible process with specified descriptor
	____________
*/
 OSStatus MoreAECreateAppleEventCreatorTarget(
							const AEEventClass pAEEventClass,
							const AEEventID pAEEventID,
							const OSType pCreator,
							AppleEvent* pAppleEvent)
{
	assert(pAppleEvent != nil);
	
	StAEDesc targetDesc;
	OSStatus anErr = AECreateDesc(typeApplSignature, &pCreator, sizeof(pCreator), &targetDesc);
	if (noErr == anErr)
		anErr = AECreateAppleEvent(pAEEventClass, pAEEventID, &targetDesc, 
									kAutoGenerateReturnID, kAnyTransactionID, pAppleEvent);

	return anErr;
}//end MoreAECreateAppleEventCreatorTarget

//tk:
//c-string with bundle ID
 OSStatus MoreAECreateAppleEventBundleIDTarget(
							const AEEventClass pAEEventClass,
							const AEEventID pAEEventID,
							const char * inBundleID,
							AppleEvent* pAppleEvent)
{
	assert(inBundleID != nil);
	assert(pAppleEvent != nil);
	
	StAEDesc targetDesc;
	OSStatus anErr = AECreateDesc(typeApplicationBundleID, inBundleID, strlen(inBundleID), &targetDesc);
	if (noErr == anErr)
		anErr = AECreateAppleEvent(pAEEventClass, pAEEventID, &targetDesc, 
									kAutoGenerateReturnID, kAnyTransactionID, pAppleEvent);
	
	return anErr;
}//end MoreAECreateAppleEventBundleIDTarget


#pragma mark ==> Send AppleEvents ¥

/********************************************************************************
	Send the provided AppleEvent using the provided idle function.
	Return the direct object as a AEDesc of pAEDescType

	pIdleProcUPP	==>		The idle function to use when sending the event.
	pAppleEvent		==>		The event to be sent.
	pDescType		==>		The type of value returned by the event.
	pAEDescList		<==		The value returned by the event.

	RESULT CODES
	____________
	noErr			   0	No error	
	paramErr		 -50	No idle function provided

	and any other error that can be returned by AESend
	or the handler in the application that gets the event.
	____________
*/
 OSErr MoreAESendEventReturnAEDesc(
						const AEIdleUPP		pIdleProcUPP,
						const AppleEvent	*pAppleEvent,
						const DescType		pDescType,
						AEDesc				*pAEDesc)
{
	//	No idle function is an error, since we are expected to return a value
	if (pIdleProcUPP == nil)
		return paramErr;

	AESendMode sendMode = kAEWaitReply;

	StAEDesc theReply;
    SInt32 timeout = 60 * 5; //wait no longer than 5 secs. kAEDefaultTimeout is 60 secs
	OSErr anErr = AESend(pAppleEvent, &theReply, sendMode, kAENormalPriority, timeout, NULL, NULL);
	//	[ Don't dispose of the event, it's not ours ]
	if (noErr == anErr)
	{
		anErr = MoreAEGetHandlerError(&theReply);

		if (!anErr && theReply.descriptorType != typeNull)
		{
			anErr = AEGetParamDesc(&theReply, keyDirectObject, pDescType, pAEDesc);
		}
	}

	return anErr;
}	// MoreAESendEventReturnAEDesc


#pragma mark -
#pragma mark === ADDED BY _TK_ ===


//_tk_
 OSErr MoreAETellAppToGetAEDesc(	const OSType appCreator,
										const DescType pPropType,
										const DescType pDescType,
										AEDesc *pAEDesc)
{
	StAEDesc containerObj;	// null (application) container
	return MoreAETellAppObjectToGetAEDesc(
									appCreator,
									containerObj,
									pPropType,
									pDescType,
									pAEDesc);
}

//_tk_
 OSErr MoreAETellAppToCoerceAEDescRequestingType(
										const OSType appCreator,
										AEDesc *inOrigAEDesc,
										const DescType inRequestedType,
										AEDesc *pAEDesc)
{
	if (nil == gAEIdleUPP)
		gAEIdleUPP = NewAEIdleUPP(MoreAESimpleIdleFunction);

	StAEDesc tAppleEvent;
	OSErr anErr = MoreAECreateAppleEventCreatorTarget(kAECoreSuite, kAEGetData, appCreator, &tAppleEvent);
	if(noErr != anErr) return anErr;

	{
		anErr = AEPutParamDesc(&tAppleEvent, keyDirectObject, inOrigAEDesc);
		if(noErr != anErr) return anErr;

		anErr = AEPutKeyPtr(&tAppleEvent, keyAERequestedType, typeType, &inRequestedType, sizeof(DescType));
		if(noErr != anErr) return anErr;
	}

	return MoreAESendEventReturnAEDesc(gAEIdleUPP, &tAppleEvent, inRequestedType, pAEDesc);
}


 OSErr MoreAETellBundledAppToGetElementAt(
										const char * appBundleID,
										const DescType inClass,
										const DescType inWhich,
										const DescType resultType,
										AEDesc *outResultAEDesc)
{
	StAEDesc containerObj;	// null (application) container
	return MoreAETellBundledAppObjToGetElementAt(
										appBundleID,
										containerObj,
										inClass,
										inWhich,
										resultType,
										outResultAEDesc);
}



#pragma mark -



 OSErr MoreAETellAppToCreateNewElementIn(
										const OSType appCreator,
										const DescType inClass,
										AEDescList* inProperties,
										AEDesc * insideThisObj,
										const DescType resultType,
										AEDesc *outResultAEDesc)
{
	if (nil == gAEIdleUPP)
		gAEIdleUPP = NewAEIdleUPP(MoreAESimpleIdleFunction);

	StAEDesc tAppleEvent;
	OSErr anErr = MoreAECreateAppleEventCreatorTarget(kAECoreSuite, kAECreateElement, appCreator, &tAppleEvent);
	if(noErr != anErr) return anErr;

	{
		StAEDesc classDesc;
		anErr = ::AECreateDesc(typeType, &inClass, sizeof(inClass), classDesc);
		if(noErr != anErr) return anErr;
		
		anErr = AEPutParamDesc(&tAppleEvent, keyAEObjectClass, classDesc);
		if(noErr != anErr) return anErr;
	}
	
	if(inProperties != NULL)
	{
		anErr = AEPutParamDesc(&tAppleEvent, keyAEPropData, inProperties);
		if(noErr != anErr) return anErr;
	}

	if(insideThisObj != NULL)
	{
		anErr = AEPutParamDesc(&tAppleEvent, keyAEInsertHere, insideThisObj);
		if(noErr != anErr) return anErr;
	}
	
	return  MoreAESendEventReturnAEDesc(gAEIdleUPP, &tAppleEvent, resultType, outResultAEDesc);
}



//Consult: http://developer.apple.com/documentation/mac/IAC/IAC-300.html

/*
Many AppleScript commands, including the copy command, take additional arguments that correspond
to insertion location descriptor records, which are descriptor records of type typeInsertionLoc
defined as part of the Core suite. An insertion location descriptor record is a coerced AE record
that consists of two keyword-specified descriptor records with the following keywords:
keyAEObject				An object specifier record that identifies a single container
keyAEPosition			A constant that specifies where to put the Apple event object described
						in an Apple event's direct parameter in relation to the container specified
						in the descriptor record with the keyword keyAEObject
*/

//inLocation may be:
//kAEBefore	Before the container
//kAEAfter	After the container
//kAEBeginning	In the container and before all other elements of the same class as the object being inserted
//kAEEnd	In the container and after all other objects of the same class as the object being inserted
//kAEReplace	Replace the container


OSErr MoreAETellAppObjToInsertNewElement(
										const OSType appCreator,
										AEDesc *containerObj,
										const DescType inClass,
										const DescType inSelectionObjType,
										AEDescList* inProperties,
										const DescType inLocation,
										const DescType resultType,
										AEDesc *outResultAEDesc)
{
	if (nil == gAEIdleUPP)
		gAEIdleUPP = NewAEIdleUPP(MoreAESimpleIdleFunction);

	StAEDesc tAppleEvent;
	OSErr anErr = MoreAECreateAppleEventCreatorTarget(kAECoreSuite, kAECreateElement, appCreator, &tAppleEvent);
	if(noErr != anErr) return anErr;

	{
		StAEDesc classDesc;
		anErr = ::AECreateDesc(typeType, &inClass, sizeof(inClass), classDesc);
		if(noErr != anErr) return anErr;
		
		anErr = AEPutParamDesc(&tAppleEvent, keyAEObjectClass, classDesc);
		if(noErr != anErr) return anErr;
	}

	{
		StAEDesc insertLocation;
		anErr = ::AECreateList(NULL, 0, true, insertLocation);
		//AAERecord insertLocation;
		StAEDesc posDesc(typeEnumerated, &inLocation, sizeof(inLocation));
//		insertLocation.PutKeyDesc(keyAEPosition, posDesc);
		anErr = ::AEPutKeyDesc(insertLocation, keyAEPosition, posDesc);
		if(noErr != anErr) return anErr;

		StAEDesc selObject;
		anErr = MoreAEOCreateSelectionObject( kAEAll, containerObj, selObject, inSelectionObjType );
		if(noErr != anErr) return anErr;
//		insertLocation.PutKeyDesc(keyAEObject, selObject);
		anErr = ::AEPutKeyDesc(insertLocation, keyAEObject, selObject);
		if(noErr != anErr) return anErr;
		
		((AEDesc *)insertLocation)->descriptorType = typeInsertionLoc;
//		StAEDesc coercedRecord(typeInsertionLoc, insertLocation);

		anErr = AEPutParamDesc(&tAppleEvent, keyAEInsertHere, insertLocation);
		if(noErr != anErr) return anErr;
	}

	if(inProperties != NULL)
	{
		anErr = AEPutParamDesc(&tAppleEvent, keyAEPropData, inProperties);
		if(noErr != anErr) return anErr;
	}

	return  MoreAESendEventReturnAEDesc(gAEIdleUPP, &tAppleEvent, resultType, outResultAEDesc);
}




 OSErr MoreAETellBundledAppObjToGetElementAt(
										const char * appBundleID,
										AEDesc *containerObj,
										const DescType inClass,
										const DescType inWhich,
										const DescType resultType,
										AEDesc *outResultAEDesc)
{
	if (nil == gAEIdleUPP)
		gAEIdleUPP = NewAEIdleUPP(MoreAESimpleIdleFunction);

	StAEDesc tAppleEvent;
	OSErr anErr = MoreAECreateAppleEventBundleIDTarget(kAECoreSuite, kAEGetData, appBundleID, &tAppleEvent);
	if(noErr != anErr) return anErr;

	{
		StAEDesc selObject;
		StAEDesc selectionDesc;
	
		anErr = AECreateDesc( typeAbsoluteOrdinal, &inWhich, sizeof(inWhich), &selectionDesc );
		if ( noErr == anErr )
		{
			anErr = CreateObjSpecifier( inClass, containerObj, formAbsolutePosition,
									&selectionDesc, false, selObject );
		}


		if(noErr != anErr) return anErr;
	
		anErr = AEPutParamDesc(&tAppleEvent, keyDirectObject, selObject);
		if(noErr != anErr) return anErr;
	}

	return  MoreAESendEventReturnAEDesc(gAEIdleUPP, &tAppleEvent, resultType, outResultAEDesc);
}


//_tk_
 OSErr MoreAETellAppObjectToGetAEDesc(
										const OSType appCreator,
										AEDesc *containerObj,
										const DescType pPropType,
										const DescType pDescType,
										AEDesc *pAEDesc)
{
	if (nil == gAEIdleUPP)
		gAEIdleUPP = NewAEIdleUPP(MoreAESimpleIdleFunction);

	StAEDesc tAppleEvent;
	OSErr anErr = MoreAECreateAppleEventCreatorTarget(kAECoreSuite, kAEGetData, appCreator, &tAppleEvent);
	if(noErr != anErr) return anErr;

	{
		StAEDesc propertyObject;
		anErr = MoreAEOCreatePropertyObject(pPropType, containerObj, propertyObject);
		if(noErr != anErr) return anErr;

		anErr = AEPutParamDesc(&tAppleEvent, keyDirectObject, propertyObject);
		if(noErr != anErr) return anErr;
	}

	return MoreAESendEventReturnAEDesc(gAEIdleUPP, &tAppleEvent, pDescType, pAEDesc);
}


#pragma mark -


#pragma mark ==> Misc. AE utility functions ¥


/********************************************************************************
	Takes a reply event checks it for any errors that may have been returned
	by the event handler. A simple function, in that it only returns the error
	number. You can often also extract an error string and three other error
	parameters from a reply event.
	
	Also see:
		IM:IAC for details about returned error strings.
		AppleScript developer release notes for info on the other error parameters.
	
	pAEReply	==>		The reply event to be checked.

	RESULT CODES
	____________
	noErr					0	No error	
	????					??	Pretty much any error, depending on what the
								event handler returns for it's errors.
*/
	OSErr	MoreAEGetHandlerError(const AppleEvent* pAEReply)
{
	if ( pAEReply->descriptorType != typeNull )	// there's a reply, so there may be an error
	{
		OSErr handlerErr = noErr;
		DescType actualType = 0;
		Size actualSize = 0;
		OSErr getErrErr = AEGetParamPtr( pAEReply, keyErrorNumber, typeSInt16, &actualType,
									&handlerErr, sizeof( OSErr ), &actualSize );
		
		if ( getErrErr != errAEDescNotFound )	// found an errorNumber parameter
		{
			return handlerErr;					// so return it's value
		}
	}
	return noErr;
}//end MoreAEGetHandlerError


/********************************************************************************
	A very simple idle function. It simply ignors any event it receives,
	returns 30 for the sleep time and nil for the mouse region.
	
	Your application should supply an idle function that handles any events it
	might receive. This is especially important if your application has any windows.
	
	Also see:
		IM:IAC for details about idle functions.
		Pending Update Perils technote for more about handling low-level events.
*/	
	Boolean	MoreAESimpleIdleFunction(
	EventRecord* event,
	SInt32* sleepTime,
	RgnHandle* mouseRgn )
{
#pragma unused( event )
	*sleepTime = 30;
	*mouseRgn = NULL;
		
	return false;
}//end MoreAESimpleIdleFunction


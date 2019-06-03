/*
	File:		MoreAppleEvents.h

	Contains:	Apple Event Manager utilities.

	DRI:		George Warner

	Copyright:	Copyright (c) 1998-2001 by Apple Computer, Inc., All Rights Reserved.

	Disclaimer:	IMPORTANT:  This Apple software is supplied to you by Apple Computer, Inc.
				("Apple") in consideration of your agreement to the following terms, and your
				use, installation, modification or redistribution of this Apple software
				constitutes acceptance of these terms.  If you do not agree with these terms,
				please do not use, install, modify or redistribute this Apple software.

				In consideration of your agreement to abide by the following terms, and subject
				to these terms, Apple grants you a personal, non-exclusive license, under Apple’s
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

#pragma once

#include <Carbon/Carbon.h>


#ifdef __cplusplus
	extern "C" {
#endif


/********************************************************************************
 Given a property type, create an new object descriptor for that property,
 contained by containerObj.
 
 propType        input:    Property type to use for object.
 containerObjPtr    input:    Pointer to container object for object being created.
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
OSErr MoreAEOCreatePropertyObject( const DescType propType,
									AEDesc *containerObjPtr,
									AEDesc *propertyObjPtr );

/********************************************************************************
 Given selection type, create an new object descriptor for a selection,
 contained by containerObj.
 
 selection        input:    Selection type to use for object.
 containerObjPtr    input:    Pointer to container object for object being created.
 selectionObject    input:    Pointer to null AEDesc.
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
OSErr MoreAEOCreateSelectionObject( const DescType selection,
									AEDesc *containerObjPtr,
									AEDesc *selectionObject,
									const DescType inObjectType );

/********************************************************************************
	Create and return an AppleEvent of the given class and ID. The event will be
	targeted at the application with the specific creator.

	psnPtr			==>	Pointer to the PSN to target the event with.
	pAEEventClass	==>	The class of the event to be created.
	pAEEventID		==>	The ID of the event to be created.
	pAppleEvent		==>	Pointer to an AppleEvent where the
						event record will be returned.
					<==	The Apple event.
	
	RESULT CODES
	____________
	noErr			   0	No error	
	memFullErr		-108	Not enough room in heap zone	
	procNotFound	–600	No eligible process with specified descriptor
	____________
*/
extern  OSStatus MoreAECreateAppleEventCreatorTarget(
							const AEEventClass pAEEventClass,
							const AEEventID pAEEventID,
							const OSType pCreator,
							AppleEvent* pAppleEvent);

//tk							
extern  OSStatus MoreAECreateAppleEventBundleIDTarget(
							const AEEventClass pAEEventClass,
							const AEEventID pAEEventID,
							const char * inBundleID,
							AppleEvent* pAppleEvent);


        /********************************************************************************
	Send the provided AppleEvent using the provided idle function.
	Return the direct object as a AEDesc of pAEDescType

	pIdleProcUPP	==>	The idle function to use when sending the event.
	pAppleEvent		==>	The event to be sent.
	pDescType		==>	The type of value returned by the event.
	pAEDescList		<==	The value returned by the event.

	RESULT CODES
	____________
	noErr			   0	No error	
	paramErr		 -50	No idle function provided

	and any other error that can be returned by AESend or the handler
	in the application that gets the event.
	____________
*/
extern  OSErr MoreAESendEventReturnAEDesc(
						const AEIdleUPP		pIdleProcUPP,
						const AppleEvent	*pAppleEvent,
						const DescType		pDescType,
						AEDesc				*pAEDesc);

extern  OSErr MoreAETellAppToGetAEDesc(
						const OSType appCreator,
						const DescType pPropType,
						const DescType pDescType,
						AEDesc *pAEDesc);

extern  OSErr MoreAETellAppToCoerceAEDescRequestingType(
						const OSType appCreator,
						AEDesc *inOrigAEDesc,
						const DescType inRequestedType,
						AEDesc *pAEDesc);
        

extern  OSErr MoreAETellBundledAppToGetElementAt(
						const char * appBundleID,
						const DescType inClass,
						const DescType inWhich,
						const DescType resultType,
						AEDesc *outResultAEDesc);


extern  OSErr MoreAETellAppObjToInsertNewElement(
						const OSType appCreator,
						AEDesc *containerObj,
						const DescType inClass,
						const DescType inSelectionObjType,
						AEDescList* inProperties,
						const DescType inLocation,
						const DescType resultType,
						AEDesc *outResultAEDesc);

extern  OSErr MoreAETellAppToCreateNewElementIn(
						const OSType appCreator,
						const DescType inClass,
						AEDescList* inProperties,
						AEDesc * insideThisObj,
						const DescType resultType,
						AEDesc *outResultAEDesc);

extern  OSErr MoreAETellBundledAppObjToGetElementAt(
						const char *appBundleID,
						AEDesc *containerObj,
						const DescType inClass,
						const DescType inWhich,
						const DescType resultType,
						AEDesc *outResultAEDesc);


extern  OSErr MoreAETellAppObjectToGetAEDesc(
						const OSType appCreator,
						AEDesc *containerObj,
						const DescType pPropType,
						const DescType pDescType,
						AEDesc *pAEDesc);

/********************************************************************************
	Takes a reply event checks it for any errors that may have been returned
	by the event handler. A simple function, in that it only returns the error
	number. You can often also extract an error string and three other error
	parameters from a reply event.
	
	Also see:
		IM:IAC for details about returned error strings.
		AppleScript developer release notes for info on the other error parameters.
	
	pAEReply		==>	The reply event to be checked.

	RESULT CODES
	____________
	noErr					0	No error	
	????					??	Pretty much any error, depending on what the
								event handler returns for it's errors.
*/
extern OSErr MoreAEGetHandlerError( const AppleEvent* pAEReply );

/********************************************************************************
	A very simple idle function. It simply ignors any event it receives,
	returns 30 for the sleep time and nil for the mouse region.
	
	Your application should supply an idle function that handles any events it
	might receive. This is especially important if your application has any windows.
	
	Also see:
		IM:IAC for details about idle functions.
		Pending Update Perils technote for more about handling low-level events.
*/	
extern Boolean MoreAESimpleIdleFunction( EventRecord* event,
										SInt32* sleepTime,
										RgnHandle* mouseRgn );

#ifdef __cplusplus
}
#endif

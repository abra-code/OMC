//**************************************************************************************
// Filename:	CMUtils.cp
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
//
// Copyright � 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	static utilities for Contextual Menu Plugins
//	
//
//
//**************************************************************************************

#include "CMUtils.h"
#include "DebugSettings.h"
#include "StAEDesc.h"
#include <Carbon/Carbon.h>
#include <vector>


#if 0// UNIVERSAL_INTERFACES_VERSION < 0x0342

//these enums used to be present in ContextualMenuPlugins.h, now they are defined in Menus.h
enum
{
	keyContextualMenuCommandID				=	'cmcd',
	keyContextualMenuSubmenu				=	'cmsb'
};

#endif


// ---------------------------------------------------------------------------
// AddCommandToAEDescList
// ---------------------------------------------------------------------------

OSStatus 
CMUtils::AddCommandToAEDescList(	ConstStr255Param inCommandString,
									SInt32 inCommandID,
									AEDescList* ioCommandList,
									MenuItemAttributes attributes /*= 0*/,
									UInt32 modifiers /*= kMenuNoModifiers*/)
{
	if( (inCommandString == NULL) || (ioCommandList == NULL) )
		return paramErr;

//	TRACE_CSTR("CMUtils. AddCommandToAEDescList with Str255\n" );

	OSStatus err = noErr;
	
	StAEDesc theCommandRecord;//AERecord
	
	// create an apple event record for our command
	err = ::AECreateList(NULL, 0, true, theCommandRecord);
	if (err != noErr) return err;
		
	// stick the command text into the AERecord
	err = ::AEPutKeyPtr( theCommandRecord, keyContextualMenuName /*keyAEName*/, typeChar, &inCommandString[1], inCommandString[0]);
	if (err != noErr) return err;
			
	// stick the command ID into the AERecord
	err = ::AEPutKeyPtr( theCommandRecord, keyContextualMenuCommandID, typeSInt32, &inCommandID, sizeof (inCommandID));
	if (err != noErr) return err;

	//stick menu attributes into AERecord
	if(attributes != 0)
	{
		err = ::AEPutKeyPtr( theCommandRecord, keyContextualMenuAttributes, typeSInt32, &attributes, sizeof (attributes));
		if (err != noErr) return err;
	}

	//stick menu modifiers into AERecord
	if(modifiers != kMenuNoModifiers)
	{
		err = ::AEPutKeyPtr( theCommandRecord, keyContextualMenuModifiers, typeSInt32, &modifiers, sizeof (UInt32));
		if (err != noErr) return err;
	}

	// stick this record into the list of commands that we are passing back to CMM
	err = ::AEPutDesc(	ioCommandList, // the list we're putting our command into
						0, // stick this command onto the end of our list
						theCommandRecord); // the command I'm putting into the list

    return err;
}

OSStatus 
CMUtils::AddCommandToAEDescList( const UniChar *inCommandString,
										UniCharCount inCount,
										SInt32 inCommandID,
										AEDescList* ioCommandList,
										MenuItemAttributes attributes /*= 0*/,
										UInt32 modifiers /*= kMenuNoModifiers*/)
{
	if( (inCommandString == NULL) || (ioCommandList == NULL) )
		return paramErr;

//	TRACE_CSTR("CMUtils. AddCommandToAEDescList with Unicode characters\n" );

	OSStatus err = noErr;
	
	StAEDesc theCommandRecord;//AERecord
	
	// create an apple event record for our command
	err = ::AECreateList(NULL, 0, true, theCommandRecord);
	if (err != noErr) return err;
		
	// stick the command text into the AERecord
	err = ::AEPutKeyPtr( theCommandRecord, keyContextualMenuName /*keyAEName*/, typeUnicodeText, inCommandString, inCount*sizeof(UniChar));
	if (err != noErr) return err;
			
	// stick the command ID into the AERecord
	err = ::AEPutKeyPtr( theCommandRecord, keyContextualMenuCommandID, typeSInt32, &inCommandID, sizeof (inCommandID));
	if (err != noErr) return err;

	//stick menu attributes into AERecord
	if(attributes != 0)
	{
		err = ::AEPutKeyPtr( theCommandRecord, keyContextualMenuAttributes, typeSInt32, &attributes, sizeof (attributes));
		if (err != noErr) return err;
	}

	//stick menu modifiers into AERecord
	if(modifiers != kMenuNoModifiers)
	{
		err = ::AEPutKeyPtr( theCommandRecord, keyContextualMenuModifiers, typeSInt32, &modifiers, sizeof (UInt32));
		if (err != noErr) return err;
	}
	
	// stick this record into the list of commands that we are passing back to CMM
	err = ::AEPutDesc(	ioCommandList, // the list we're putting our command into
						0, // stick this command onto the end of our list
						theCommandRecord); // the command I'm putting into the list

    return err;
}


OSStatus 
CMUtils::AddCommandToAEDescList(	CFStringRef inCommandString,
									SInt32 inCommandID,
									Boolean putCFString, //available starting with OS 10.2
									AEDescList* ioCommandList,
									MenuItemAttributes attributes /*= 0*/,
									UInt32 modifiers /*= kMenuNoModifiers*/)
{
	if(putCFString == false)
		return AddCommandToAEDescList_Compatible( inCommandString, inCommandID, ioCommandList, attributes, modifiers );

	if( (inCommandString == NULL) || (ioCommandList == NULL) )
		return paramErr;

//	TRACE_CSTR( "CMUtils. AddCommandToAEDescList with CFString\n" );
//	TRACE_CFSTR(inCommandString);

	OSStatus err = noErr;
	
	StAEDesc theCommandRecord;//AERecord
	
	// create an apple event record for our command
	err = ::AECreateList(NULL, 0, true, theCommandRecord);
	if (err != noErr) return err;
	
/*	Apple documentation says:
   * If you provide data as typeCFStringRef, the Contextual Menu Manager will
   * automatically release the CFStringRef once the menu has been
   * displayed. If you need the CFStringRef to have a longer timetime,
   * your plugin should retain the CFStringRef before inserting it into
   * the AERecord.
*/
	//_tk_ comment
	//it is not said explicitly if Contextual Menu Manager retains the CFString.
	//However, a little bit of experimenting (and crashing) shows that
	//IT DOES NOT RETAIN the CFString, it takes onwership of the string without retaining it
	//We do not "own" the string here so we must retain it
	//to balance the release which will be done by Contextual Menu Manager

	::CFRetain(inCommandString);

	// stick the command text into the AERecord
	err = ::AEPutKeyPtr( theCommandRecord, keyContextualMenuName, typeCFStringRef, &inCommandString, sizeof(CFStringRef));
	if (err != noErr) return err;

	// stick the command ID into the AERecord
	err = ::AEPutKeyPtr( theCommandRecord, keyContextualMenuCommandID, typeSInt32, &inCommandID, sizeof (inCommandID));
	if (err != noErr) return err;

	//stick menu attributes into AERecord
	if(attributes != 0)
	{
		err = ::AEPutKeyPtr( theCommandRecord, keyContextualMenuAttributes, typeSInt32, &attributes, sizeof(attributes));
		if (err != noErr) return err;
	}

	//stick menu modifiers into AERecord
	if(modifiers != kMenuNoModifiers)
	{
		err = ::AEPutKeyPtr( theCommandRecord, keyContextualMenuModifiers, typeSInt32, &modifiers, sizeof (UInt32));
		if (err != noErr) return err;
	}
	
	// stick this record into the list of commands that we are passing back to CMM
	err = ::AEPutDesc(	ioCommandList, // the list we're putting our command into
						0, // stick this command onto the end of our list
						theCommandRecord); // the command I'm putting into the list

    return err;
}

//This method is compatible with 10.1.x 

OSStatus 
CMUtils::AddCommandToAEDescList_Compatible(	CFStringRef inCommandString,
									SInt32 inCommandID,
									AEDescList* ioCommandList,
									MenuItemAttributes attributes /*= 0*/,
									UInt32 modifiers /*= kMenuNoModifiers*/ )
{
	if( inCommandString == NULL )
		return paramErr;

//	TRACE_CSTR("CMUtils. AddCommandToAEDescList with CFString\n" );

	CFIndex uniCount = ::CFStringGetLength(inCommandString);
	const UniChar *uniString = ::CFStringGetCharactersPtr(inCommandString);
	if( uniString != NULL )
		return CMUtils::AddCommandToAEDescList(	uniString, uniCount, inCommandID, ioCommandList, attributes, modifiers );

//CFStringGetCharactersPtr failed and we must copy the string
    std::vector<UniChar> newString(uniCount);

	CFRange theRange;
	theRange.location = 0;
	theRange.length = uniCount;
	::CFStringGetCharacters( inCommandString, theRange, newString.data());

	OSStatus outErr = CMUtils::AddCommandToAEDescList(	newString.data(), uniCount, inCommandID, ioCommandList, attributes, modifiers );
	
	return outErr;
}


OSStatus
CMUtils::AddSubmenu( AEDescList* ioCommands, CFStringRef inName, AEDescList &inSubList )
{
	if( inName == NULL )
		return paramErr;

//	TRACE_CSTR("CMUtils. AddSubmenu with CFString\n" );

	CFIndex uniCount = ::CFStringGetLength(inName);
	const UniChar *uniString = ::CFStringGetCharactersPtr(inName);
	if( uniString != NULL )
		return CMUtils::AddSubmenu(	ioCommands, uniString, uniCount, inSubList );

//CFStringGetCharactersPtr failed and we must copy the string

	UniChar *newString = new UniChar[uniCount];

	CFRange theRange;
	theRange.location = 0;
	theRange.length = uniCount;
	::CFStringGetCharacters( inName, theRange, newString);

	OSStatus outErr = CMUtils::AddSubmenu( ioCommands, newString, uniCount, inSubList );
	delete [] newString;
	
	return outErr;
}

OSStatus 
CMUtils::AddSubmenu( AEDescList* ioCommands, 
					const UniChar *inName,
					UniCharCount inCount,
					AEDescList &inSubList )
{
	if( (inName == NULL) || (ioCommands == NULL) )
		return paramErr;

//	TRACE_CSTR("CMUtils. AddSubmenu with Unicode characters\n" );

	StAEDesc	theSupercommand; //AERecord

	// create an apple event record for our supercommand
	OSStatus err = ::AECreateList( NULL, 0, true, theSupercommand );
	if (err != noErr) return err;

	// stick the command text into the AERecord
	err = ::AEPutKeyPtr( theSupercommand, keyContextualMenuName /*keyAEName*/, typeUnicodeText, inName, inCount*sizeof(UniChar) );
	if (err != noErr) return err;
			
	// stick the subcommands into into the AERecord
	err = ::AEPutKeyDesc( theSupercommand, keyContextualMenuSubmenu, &inSubList );
	if (err != noErr) return err;

	// stick the supercommand into the list of commands that we are passing back to the CMM
	err = ::AEPutDesc(	ioCommands,			// the list we're putting our command into
						0,					// stick this command onto the end of our list
						theSupercommand );	// the command I'm putting into the list
	return err;
}

/*
OSStatus 
CMUtils::AppendItemsToSubmenu(AERecord *inSubmenuRec, AEDescList &inSubList)
{


}

//returns 1 to N when found

SInt32
CMUtils::FindSubmenu(AEDescList* ioCommands, CFStringRef inName)
{
	SInt32 i, itemCount = 0;
	OSStatus err = AECountItems(ioCommands, &itemCount);
	if(err != noErr)
		return 0;

	for(i = 1; i <= itemCount; i++)
	{
		AEDesc oneItem = {typeNull, NULL};
		AEKeyword theKeyword;
		err = AEGetNthDesc(inMenuItemsList, i, typeWildCard, &theKeyword, &oneItem);
		if((err == noErr) && AECheckIsRecord (&oneItem))
		{
			if( IsSubmenuWithName(&oneItem, inName) )
				return i;
		}
		AEDisposeDesc(&oneItem);
	}

}


Boolean
CMUtils::IsSubmenuWithName(const AERecord *inMenuItemRec, CFStringRef inSubmenuName)
{
	Boolean isSubmenu = false;

	if(inMenuItemRec == NULL)
		return paramErr;
	
	SInt32 recItemsCount = 0;
	OSStatus err = AECountItems(inMenuItemRec, &recItemsCount);
	if( (err == noErr) && (recItemsCount > 0) )
	{
		AEDesc oneItem = {typeNull, NULL};
		AEDesc itemName = {typeNull, NULL};
		SInt32 i;
		for(i = 1; i <= recItemsCount; i++)
		{
			Boolean releaseItem = true;
			AEKeyword theKeyword;
			err = AEGetNthDesc(inMenuItemRec, i, typeWildCard, &theKeyword, &oneItem);
			if(err == noErr)
			{
				CFIndex retainCount = 0;
				switch(theKeyword)
				{
					case keyContextualMenuName:
					{
						itemName = oneItem;
						releaseItem = false;
					}
					break;
				
					case keyContextualMenuSubmenu:
					{
						isSubmenu = true;
					}
					break;
					
					default:
					break;
				}
				
				if(releaseItem)
				{
					AEDisposeDesc(&oneItem);
				}
			}
		}
	}
	
	if(isSubmenu && (itemName.descriptorType != typeNull))
	{
		CFStringRef oneMenuItemName = CreateCFStringFromAEDesc(&itemName);
		AEDisposeDesc(&itemName);
		return ( kCFCompareEqualTo == ::CFStringCompare(oneMenuItemName, inSubmenuName, 0) );
	}
	
	return false;
}
*/

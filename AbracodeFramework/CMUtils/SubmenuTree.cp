//**************************************************************************************
// Filename:	SubmenuTree.cp
// Copyright © 2005 <YourNameHere>.  All rights reserved.
//
// Description:	
//
//**************************************************************************************
// Revision History:
// Thursday, March 10, 2005 - Original
//**************************************************************************************

#include "SubmenuTree.h"
#include "CMUtils.h"

CommandMenuItem::CommandMenuItem(CFStringRef inSubmenuPathString,
							CFStringRef inItemName,
							SInt32 inCommandID,
							MenuItemAttributes inAttributes,
							UInt32 inModifiers)
	: submenuPathString(inSubmenuPathString), itemName(inItemName), commandID(inCommandID),
		attributes(inAttributes), modifiers(inModifiers)
{
	if(submenuPathString != NULL)
		CFRetain(submenuPathString);

	if(itemName != NULL)
		CFRetain(itemName);
}

CommandMenuItem::~CommandMenuItem()
{
	if(submenuPathString != NULL)
		CFRelease(submenuPathString);

	if(itemName != NULL)
		CFRelease(itemName);
}


SubmenuItem::SubmenuItem(CFURLRef inPath, CFStringRef inName)
	: path(inPath), name(inName), /*submenuList(NULL),*/ itemList(NULL), isAppended(false), previousItem(NULL)
{
	aeItemList.descriptorType = typeNull;
	aeItemList.dataHandle = NULL;

	if(path != NULL)
		CFRetain(path);
	
	if(name != NULL)
		CFRetain(name);
}

SubmenuItem::~SubmenuItem()
{
	if(path != NULL)
		CFRelease(path);

	if(name != NULL)
		CFRelease(name);
	
	
	if(aeItemList.dataHandle != NULL)
		AEDisposeDesc( &aeItemList );

	if(itemList != NULL)
	{
		CFIndex itemCount =  ::CFArrayGetCount(itemList);
		for(CFIndex i = 0; i < itemCount; i++)
		{
			AbstractMenuItem *oneMenuObj = (AbstractMenuItem *)CFArrayGetValueAtIndex(itemList, i);
			delete oneMenuObj;
			//if( (oneMenuObj != NULL) && (oneMenuObj->IsSubmenu() == false) )//don't delete submenu items, the chain owns them
			//	delete oneMenuObj;
		}

		CFRelease(itemList);
	}
		
//	if(submenuList != NULL)
//		CFRelease(submenuList);

}

//we do not own inRootMenu but we expect it to be valid for the whole life of the SubmenuTree object

SubmenuTree::SubmenuTree(AEDescList* inRootMenu)
	: mSubmenuList(NULL)
{
	mRootItem = new SubmenuItem(NULL, CFSTR(""));//(SubmenuItem *)calloc(1, sizeof(SubmenuItem));
	mRootItem->path = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, CFSTR("/"), kCFURLPOSIXPathStyle, true);//item takes owneship
	
	//mRootItem->itemList = NULL;//lazy initialization, create array later only when actually need
	//mRootItem->itemList = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);//NULL callback. no retain and no release. objects not owned
	//mRootItem->submenuList = NULL; //lazy //CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);//NULL callback. no retain and no release. objects not owned

	if(inRootMenu != NULL)
	{
		mRootItem->aeItemList = *inRootMenu;//this is not a real list copy. it is like a reference.
	}
}

SubmenuTree::~SubmenuTree(void)
{

/* the chain does not own items now, this is a change from previous version
	SubmenuItem* currItem = mSubmenuList;
	SubmenuItem* tempItem;
	while(currItem != NULL)
	{
		tempItem = currItem;
		currItem = currItem->previousItem;
		delete tempItem;
	}
*/
	
	//we do not dispose the AE list of the root item	
	mRootItem->aeItemList.dataHandle = NULL;//prevent from releasing AEDesc
	delete mRootItem;
}

//finds or creates the submenu list
//attach on every new submenu creation
//caller does not take ownership of the list (duplicate if you need to keep it)

SubmenuItem *
SubmenuTree::FindOrAddSubmenu(CFURLRef urlRef)
{
	if(urlRef == NULL)
		return NULL;

	SubmenuItem *outItem = FindSubmenu(urlRef);
	if(outItem != NULL)
		return outItem;

//not found - create new

	SubmenuItem *newHead = new SubmenuItem(urlRef, NULL);//(SubmenuItem *)calloc(1, sizeof(SubmenuItem));
	if(newHead == NULL)
		return NULL;

	OSErr err = AECreateList( NULL, 0, false, &(newHead->aeItemList) );
	if(err != noErr)
	{
		delete newHead;
		return NULL;
	}
	
	newHead->name = CFURLCopyLastPathComponent(newHead->path);//responsible for deleting it
	
	
	//newHead->itemList = NULL; //lazy //CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);//NULL callback. no retain and no release. objects not owned	
	//newHead->submenuList = NULL; //lazy //CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);//NULL callback. no retain and no release. objects not owned

	newHead->previousItem = mSubmenuList;//attach the tail
	mSubmenuList = newHead;

	AppendSubmenu(newHead);

	return newHead;
}

SubmenuItem *
SubmenuTree::FindSubmenu(CFURLRef inPath)
{
	if(inPath == NULL)
		return NULL;

	if( (mRootItem->path != NULL) && CFEqual(mRootItem->path, inPath) )
		return mRootItem;

	SubmenuItem*currItem = mSubmenuList;
	while(currItem != NULL)
	{
		if( (currItem->path != NULL) && CFEqual(currItem->path, inPath) )
		{
			return currItem;
		}
		currItem = currItem->previousItem;
	}
	return NULL;
}

OSStatus
SubmenuTree::AddMenuItem(	CFStringRef inSubmenuPathString,
							CFStringRef inItemName,
							SInt32 inCommandID,
							MenuItemAttributes attributes,
							UInt32 modifiers)
{
	CFURLRef submenuPath = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, inSubmenuPathString, kCFURLPOSIXPathStyle, true);

	SubmenuItem *submenuItem = NULL;
	if(submenuPath != NULL)
	{
		submenuItem = FindOrAddSubmenu(submenuPath);
		CFRelease(submenuPath);
	}

	if(submenuItem == NULL)
	{
		DEBUG_CFSTR(CFSTR("Could not find submenu: "));
		DEBUG_CFSTR(submenuPath);
		return paramErr;
	}

//	DEBUG_CFSTR(CFSTR("Adding item: "));
//	DEBUG_CFSTR(inItemName);
//	DEBUG_CFSTR(CFSTR("To submenu: "));
//	DEBUG_CFSTR(submenuPath);

	CommandMenuItem *newItem = new CommandMenuItem(
										inSubmenuPathString,
										inItemName,
										inCommandID,
										attributes,
										modifiers);

	if(submenuItem->itemList == NULL)//we were lazy, now we have to work
		submenuItem->itemList = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);//NULL callback. no retain and no release. objects not owned
	CFArrayAppendValue(submenuItem->itemList, newItem);

	return noErr;

/*
	return CMUtils::AddCommandToAEDescList(
							inItemName,
							inCommandID,
							putCFString,
							&(submenuItem->itemList),
							attributes,
							modifiers);
*/
}

void
SubmenuTree::BuildSubmenuTree()
{
//first pass - find out all submenus:
/*
	SubmenuItem* currItem = mSubmenuList;
	while(currItem != NULL)
	{
		if(currItem->path != NULL)
		{
			AppendSubmenu(currItem);
		}
		currItem = currItem->previousItem;
	}
*/

//second pass - add everything to AE List, with root as a starting point
//(with a twist that we have to start adding to AE lists from deepest submenus and end at root)

	AddSubmenusToAEList(mRootItem);
}


void
SubmenuTree::AddSubmenusToAEList(SubmenuItem* currLevel)
{
	if(currLevel == NULL)
		return;
	
	//SubmenuItem *subMenu;
	AbstractMenuItem *oneMenuItem;
	OSStatus err;
	CFIndex i;

/*
	CFIndex subCount = 0;
	if(currLevel->submenuList != NULL)
		subCount = ::CFArrayGetCount(currLevel->submenuList);

	for(i = (subCount-1); i >= 0; i--)
	{
		subMenu = (SubmenuItem *)CFArrayGetValueAtIndex(currLevel->submenuList, i);
		
		//recursively add childern first and then add yourself
		//so the AEList addition starts from branches and ends at main stem
		if(subMenu != NULL)
		{
			//process submenu with children first
			AddSubmenusToAEList(subMenu);
		
			//now add the submenu
			err = CMUtils::AddSubmenu( &(currLevel->aeItemList), subMenu->name, subMenu->aeItemList );
			DEBUG_CFSTR(CFSTR("Added submenu: "));
			DEBUG_CFSTR(subMenu->name);
		}
	}
*/	
	//now add our own, non-submenu items
	CFIndex itemCount = 0;
	if(currLevel->itemList != NULL)
		itemCount = ::CFArrayGetCount(currLevel->itemList);
	
	CommandMenuItem *commandItem;
	SubmenuItem *submenuItem;

	for(i = 0; i < itemCount; i++)
	{
		oneMenuItem = (AbstractMenuItem *)CFArrayGetValueAtIndex(currLevel->itemList, i);
		if( (oneMenuItem != NULL) && oneMenuItem->IsSubmenu() )
		{
			submenuItem = (SubmenuItem *)oneMenuItem;
			//recursively process submenu with children first
			AddSubmenusToAEList(submenuItem);

			//now add the created submenu
			err = CMUtils::AddSubmenu( &(currLevel->aeItemList), submenuItem->name, submenuItem->aeItemList );
//			DEBUG_CFSTR(CFSTR("Added submenu: "));
//			DEBUG_CFSTR(submenuItem->name);
		}
		else
		{//regular menu item, add it
			commandItem = (CommandMenuItem*)oneMenuItem;
			
			err = CMUtils::AddCommandToAEDescList(
							commandItem->itemName,
							commandItem->commandID,
							&(currLevel->aeItemList),
							commandItem->attributes,
							commandItem->modifiers);
		}
	}
}


//recursive submenu attaching
void
SubmenuTree::AppendSubmenu(SubmenuItem *inSubmenu)
{
	SubmenuItem *parentItem = NULL;
	CFURLRef parentPath = NULL;

	if(inSubmenu->isAppended)
	{
		return;
	}

	if( (mRootItem->path != NULL) && CFEqual(mRootItem->path, inSubmenu->path) )
	{
		return;
	}

	//if it is empty it may be root menu. we do not add root menu to itself
	parentPath = CFURLCreateCopyDeletingLastPathComponent( kCFAllocatorDefault, inSubmenu->path );
	if(parentPath != NULL)
	{
		parentItem = FindOrAddSubmenu(parentPath);
		if( parentItem != NULL)
		{
			inSubmenu->isAppended = true;

			/*if(parentItem->submenuList == NULL)//we were lazy, now we have to work
				parentItem->submenuList = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);//NULL callback. no retain and no release. objects not owned
			CFArrayAppendValue(parentItem->submenuList, inSubmenu);
			*/

			if(parentItem->itemList == NULL)//we were lazy, now we have to work
				parentItem->itemList = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);//NULL callback. no retain and no release. objects not owned
			CFArrayAppendValue(parentItem->itemList, inSubmenu);
			
			AppendSubmenu(parentItem);
		}
		CFRelease(parentPath);
	}
}

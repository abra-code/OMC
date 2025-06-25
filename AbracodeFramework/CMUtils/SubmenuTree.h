//**************************************************************************************
// Filename:	SubmenuTree.h
// Copyright � 2005 Abracode.  All rights reserved.
//
// Description:	
//
//**************************************************************************************
// Revision History:
// Thursday, March 10, 2005 - Original
//**************************************************************************************

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <Carbon/Carbon.h> // for MenuItemAttributes

class AbstractMenuItem
{
public:
		virtual		~AbstractMenuItem() { };
		virtual bool IsSubmenu() = 0;
};

class SubmenuItem : public AbstractMenuItem
{
public:
					SubmenuItem(CFURLRef inPath, CFStringRef inName);
	virtual			~SubmenuItem();
	virtual bool	IsSubmenu() { return true; }

	AEDescList		aeItemList;
	CFURLRef		path;
	CFStringRef		name;
//	CFMutableArrayRef submenuList;//objects not owned
	CFMutableArrayRef itemList; // a list of command items or submenu items records
	Boolean			isAppended;
	class SubmenuItem *previousItem;
};

class CommandMenuItem : public AbstractMenuItem
{
public:
					CommandMenuItem(CFStringRef inSubmenuPathString,
							CFStringRef inItemName,
							SInt32 inCommandID,
							MenuItemAttributes attributes,
							UInt32 modifiers);
	virtual			~CommandMenuItem();
	virtual bool	IsSubmenu() { return false; }

	CFStringRef submenuPathString;
	CFStringRef itemName;
	SInt32 commandID;
	MenuItemAttributes attributes;
	UInt32 modifiers;
};


class SubmenuTree
{
public:
						SubmenuTree(AEDescList* inRootMenu);
	virtual				~SubmenuTree();

	SubmenuItem *		FindOrAddSubmenu(CFURLRef urlRef);
	SubmenuItem *		FindSubmenu(CFURLRef inPath);
	OSStatus			AddMenuItem(
							CFStringRef inSubmenuPathString,
							CFStringRef inItemName,
							SInt32 inCommandID,
							MenuItemAttributes attributes,
							UInt32 modifiers);

	void				BuildSubmenuTree();
	void				AppendSubmenu(SubmenuItem *inSubmenu);
	void				AddSubmenusToAEList(SubmenuItem* currLevel);

protected:
	SubmenuItem			*mSubmenuList; //flat chain of SubmenuItems for easy search. items not owned
	SubmenuItem			*mRootItem;//items owned

//cached for better performance when adding mutiple items to the same submenu
//never retained so do not release
//	SubmenuItem			mLastItem;

private:
		// Defensive programming. No copy constructor nor operator=
						SubmenuTree(const SubmenuTree&);
	SubmenuTree&		operator=(const SubmenuTree&);
};

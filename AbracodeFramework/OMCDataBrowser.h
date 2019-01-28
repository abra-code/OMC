#pragma once

#ifndef __LP64__

#include "CFObj.h"
#include "AStdArrayNew.h"
#include "AStdNew.h"
#include "SelectionIterator.h"

class OMCDataBrowser
{
public:
	typedef enum ColumnSeparatorFormat
	{
		kOMCColumnSeparatorTab,
		kOMCColumnSeparatorComma,
		kOMCColumnSeparatorSpace
	} ColumnSeparatorFormat;


	enum
	{
		kOnSelectCommandIdKey = 'sel!',
		kOnDoubleClickCommandIdKey = 'dbl!'
	};

	static OSStatus InitializeControl(ControlRef  dbControl);

	static OMCDataBrowser *	GetController(WindowRef inWindow, const ControlID &dbControlID);
	static OMCDataBrowser * GetController(ControlRef dbControl);

	OMCDataBrowser(ControlRef dbControl);
	virtual ~OMCDataBrowser();

	OSStatus			RemoveRows();
	OSStatus			AddRows(CFArrayRef inNewRows);
	OSStatus			RemoveColumns();
	OSStatus			AddColumns(CFArrayRef inNewColumns);
	void				SetColumnWidths(CFArrayRef inColumnWidths);

	CFTypeRef			CopyValue(SInt32 inRowIndex, SInt32 inColumnIndex);
	CFTypeRef			CopySelectionValue(SInt32 inColumnIndex, SelectionIterator *inIterator);

	// AStdNew<SelectionIterator> selectionIterator( dataBrowser->CreateSelectionIterator() );
	SelectionIterator *		CreateSelectionIterator(bool useReverseIterator);

private:
	static OSStatus TerminateHandler(EventHandlerCallRef inHandlerCallRef,
									EventRef inEvent,
									void *inUserData);

	static OSStatus GetClickActivationHandler(EventHandlerCallRef inHandlerCallRef,
									EventRef inEvent,
									void *inUserData);

	static OSStatus ItemDataHandler(ControlRef dbControl,
									DataBrowserItemID rowID,
									DataBrowserPropertyID columnID,
									DataBrowserItemDataRef itemData,
									Boolean changeValue);

	OSStatus		HandleItemData( DataBrowserItemID rowID,
									DataBrowserPropertyID columnID,
									DataBrowserItemDataRef itemData,
									Boolean changeValue);

	static void		ItemNotificationHandler(
									ControlRef dbControl, 
									DataBrowserItemID itemID, 
									DataBrowserItemNotification message);

	void			HandleNotification(
									DataBrowserItemID itemID, 
									DataBrowserItemNotification message);

	CFArrayRef		GetColumnArrayForRow(CFIndex inRow);
	CFTypeRef		GetValue(CFIndex inColumn, CFIndex inRow);

	CFArrayRef		SplitRowString(CFStringRef inRowString);

private:
	ControlRef					mControl;
	CFObj<CFMutableArrayRef>	mRowArray;
	ColumnSeparatorFormat		mSeparator;
	CFObj<CFArrayRef>			mColumnNames;
	CFObj<CFArrayRef>			mColumnWidths;
	OSType						mOnSelectCommandID;
	OSType						mOnDoubleClickCommandID;
};

#endif //__LP64__

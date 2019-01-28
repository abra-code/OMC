#ifndef __LP64__

#include <Carbon/Carbon.h>
#include "OMCDataBrowser.h"
#include "AStdArrayNew.h"
#include "AStdNew.h"
#include "AStdMalloc.h"
#include "CFObj.h"
#include "ACFType.h"
#include "NibDialogControl.h"

//CFTypeRef OMCDBStorageGetValue(CFArrayRef inColumnArray, CFIndex inColumn, CFIndex inRow);

/*
void OMCLoadTestData(CFMutableArrayRef columnsArray)
{
	CFIndex rowCount = 2;
	CFObj<CFMutableArrayRef> firstColumnArray( ::CFArrayCreateMutable(kCFAllocatorDefault, rowCount, &kCFTypeArrayCallBacks));
	CFObj<CFMutableArrayRef> secondColumnArray( ::CFArrayCreateMutable(kCFAllocatorDefault, rowCount, &kCFTypeArrayCallBacks));
	CFObj<CFMutableArrayRef> thirdColumnwArray( ::CFArrayCreateMutable(kCFAllocatorDefault, rowCount, &kCFTypeArrayCallBacks));
	::CFArrayAppendValue( columnsArray, (CFMutableArrayRef)firstColumnArray );
	::CFArrayAppendValue( columnsArray, (CFMutableArrayRef)secondColumnArray );
	::CFArrayAppendValue( columnsArray, (CFMutableArrayRef)thirdColumnwArray );
	
	::CFArrayAppendValue( firstColumnArray, CFSTR("col=1, row=1") );
	::CFArrayAppendValue( firstColumnArray, CFSTR("col=1, row=2") );
	
	::CFArrayAppendValue( secondColumnArray, CFSTR("col=2, row=1") );
	::CFArrayAppendValue( secondColumnArray, CFSTR("col=2, row=2") );
	
	::CFArrayAppendValue( thirdColumnwArray, CFSTR("col=3, row=1") );
	::CFArrayAppendValue( thirdColumnwArray, CFSTR("col=3, row=2") );
}
*/
#if 0
//if inColArray has no items then the first row read-in creates the column arrays
//ioNameArray is not NULL, it means the first row should be treated as column description, not data and names should be put there
OSStatus
OMCAddRowsFromStream( CFMutableArrayRef inColArray, CFReadStreamRef inStream, CFStringEncoding inEnc, CFStringRef inColSeparator, CFStringRef inRowSeparator, CFMutableArrayRef ioNameArray)
{
	if( (inColArray == NULL) || (inStream == NULL) )
		return paramErr;

	if(inEnc == kCFStringEncodingUnicode)
	{
		return OMCAddRowsFromUnicodeStream( inColArray, inStream, inColSeparator, inRowSeparator, ioNameArray );
	}

	static UInt8 colSep[32];//32 is max for separator
	CFIndex colSepLen = 0;
	bool isColSepSpace = false;
	if(inColSeparator != NULL)
	{
		CFIndex len = ::CFStringGetLength(inColSeparator);
		if(len > 32)
			len = 32;
		
		if( len > 0 )
		{
			CFIndex count = ::CFStringGetBytes( inColSeparator, CFRangeMake(0, len), inEnc, 0, false, colSep, sizeof(colSep), &colSepLen );
			if( (colSepLen == 1) && (colSep[0] == ' ') )
				isColSepSpace = true;
		}
	}
	
	if(colSepLen == 0)
	{
		colSep[0] = ' ';//default is space
		colSepLen = 1;
		isColSepSpace = true;
	}
	
	static UInt8 rowSep[32];
	CFIndex rowSepLen = 0;
	bool isRowSepNewline = false;
	if( inRowSeparator != NULL )
	{
		CFIndex len = ::CFStringGetLength(inRowSeparator);
		if(len > 32)
			len = 32;
		
		if( len > 0 )
		{
			CFIndex count = ::CFStringGetBytes( inRowSeparator, CFRangeMake(0, len), inEnc, 0, false, rowSep, sizeof(rowSep), &rowSepLen );

			if( (rowSepLen == 1) && ((rowSep[0] == 0x0A) || (rowSep[0] == 0x0D)) )
				isRowSepNewline = true;
			else if( (rowSepLen == 2) && (rowSep[0] == 0x0D) && (rowSep[1] == 0x0A) )
				isRowSepNewline = true;
		}
	}
	
	if(rowSepLen == 0)
	{
		rowSep[0] = 0x0A;//default is LF
		rowSepLen = 1;
		isRowSepNewline = true;
	}
	
	CFIndex columnCount = ::CFArrayGetCount( inColArray );
	bool createColumnArrays = (columnCount == 0);		

	CFIndex buffLenMax = 4*1024;//4K is max per cell!
	AStdMalloc<UInt8> buff(buffLenMax);
	AStdMalloc<UInt8> cell(buffLenMax);

	CFIndex bytesRead = ::CFReadStreamRead( inStream, buff, buffLenMax );

	UInt8 *cellPtr = cell;
	CFIndex cellCharCount = 0;

	bool reachedEndInSeparator = false;
	bool reachedEndInCell = false;

	while(bytesRead > 0)
	{
		UInt8 *buffPtr = buff;
		
		CFIndex i = 0;
		while( i < bytesRead )
		{
			bool storeCell = false;
			if( (buffPtr[i] != colSep[0]) && (buffPtr[i] != rowSep[0]) )
			{//not a separator for sure, put the char
				cellPtr[cellCharCount++] = buffPtr[i++];
				reachedEndInCell = (i == bytesRead);
			}
			else if(buffPtr[i] == colSep[0])
			{
				if(isColSepSpace)
				{
					do
					{
						i++;
					}
					while( (i < bytesRead) && (buffPtr[i] == colSep[0]) );//space separator may contain more than one space
					storeCell = true;
					reachedEndInSeparator = (i == bytesRead);
				}
				else if(colSepLen > 1)
				{//compare if we find a column separator match
					CFIndex j = 0;
					do
					{
						i++;
						j++;
					}
					while( (i < bytesRead) && (j < colSepLen) && (buffPtr[i] == colSep[j]) );
					if(j == colSepLen) //positive, all chars matched
					{
						storeCell = true;
					}
					else if(i == bytesRead)//we reached the end while in separator, too bad, we will need to recover on next entry
					{
						reachedEndInSeparator = true;
					}
				}
			}
			else if(buffPtr[i] == rowSep[0])
			{
				if(isRowSepNewline)
				{
				}
				else if(rowSepLen > 1)
				{
				
				}
			}
		
			if( storeCell )
			{
			
			}
		}

		bytesRead = ::CFReadStreamRead( inStream, buff, buffLenMax );
	}

	return noErr;
}

OSStatus
OMCAddRowsFromUnicodeStream( CFMutableArrayRef inColArray, CFReadStreamRef inStream, CFStringRef inColSeparator, CFStringRef inRowSeparator, CFMutableArrayRef ioNameArray)
{
	static UniChar colSep[32];//32 is max for separator
	CFIndex colSepLen = 0;
	bool isColSepSpace = false;
	if(inColSeparator != NULL)
	{
		colSepLen = ::CFStringGetLength(inColSeparator);
		if(colSepLen > 32)
			colSepLen = 32;
		if(colSepLen > 0)
		{
			::CFStringGetCharacters( inColSeparator, CFRangeMake(0, colSepLen), colSep );
			if( (colSepLen == 1) && (colSep[0] == ' ') )
				isColSepSpace = true;
		}
	}
	
	if(colSepLen == 0)
	{
		colSep[0] = ' ';//default is space
		colSepLen = 1;
		isColSepSpace = true;
	}
	
	static UniChar rowSep[32];
	CFIndex rowSepLen = 0;
	bool isRowSepNewline = false;
	if( inRowSeparator != NULL )
	{
		rowSepLen = ::CFStringGetLength(inRowSeparator);
		if(rowSepLen > 32)
			rowSepLen = 32;
		if(rowSepLen > 0)
		{
			::CFStringGetCharacters( inRowSeparator, CFRangeMake(0, rowSepLen), rowSep);

			if( (rowSepLen == 1) && ((rowSep[0] == 0x0A) || (rowSep[0] == 0x0D)) )
				isRowSepNewline = true;
			else if( (rowSepLen == 2) && (rowSep[0] == 0x0D) && (rowSep[1] == 0x0A) )
				isRowSepNewline = true;
		}
	}
	
	if(rowSepLen == 0)
	{
		rowSep[0] = 0x0A;//default is LF
		rowSepLen = 1;
		isRowSepNewline = true;
	}

	CFIndex columnCount = ::CFArrayGetCount(inColArray);
	bool createColumnArrays = (columnCount == 0);		

	CFIndex buffLenMax = 4*1024;//4K is max per cell!
	AStdMalloc<UniChar> buff(buffLenMax);
	AStdMalloc<UniChar> cell(buffLenMax);

	CFIndex bytesRead = ::CFReadStreamRead(inStream, (UInt8*)(UniChar*)buff, buffLenMax*sizeof(UniChar));

	while(bytesRead > 0)
	{
	
		bytesRead = ::CFReadStreamRead(inStream, (UInt8*)(UniChar*)buff, buffLenMax*sizeof(UniChar));
	}

	return noErr;
}

#endif //0- disabled
/*
DataBrowserItemID rowID <1 - 0xFFFFFFFF>, 0 reserved
DataBrowserPropertyID columnID <1024 - 0xFFFFFFFF>, 0-1023 reserved
*/

/*
CFMutableArrayRef
OMCDataBrowserGetColumnArray(ControlRef dbControl)
{
	UInt32 actualSize = 0;
	CFMutableArrayRef columnArray = NULL;
	OSStatus status = ::GetControlProperty( dbControl, 'omc!', 'colA', sizeof(CFMutableArrayRef), &actualSize, &columnArray );
	if( (status != noErr) || (actualSize != sizeof(CFMutableArrayRef)) )
		return NULL;
	return columnArray;
}


OSStatus
OMCDataBrowserItemDataCallback(
				ControlRef dbControl,
                DataBrowserItemID rowID,
                DataBrowserPropertyID columnID,
                DataBrowserItemDataRef itemData,
                Boolean changeValue)
{
	OSStatus status = errDataBrowserPropertyNotSupported;
	
	if( columnID == 'empt' )
	{
		status = ::SetDataBrowserItemDataText( itemData, CFSTR("Empty") );
	}
	else  if( columnID == kDataBrowserItemIsSelectableProperty )
	{
      if ( !changeValue ) // can we select it? yes
        status = SetDataBrowserItemDataBooleanValue( itemData, true );
	}
	else if( columnID == kDataBrowserItemIsActiveProperty )
    {
	    if ( ! changeValue ) // is it active? yes
        status = SetDataBrowserItemDataBooleanValue( itemData, true );
	}
	else if( columnID <= 1023 ) //reserved property
		return errDataBrowserPropertyNotSupported;

	CFMutableArrayRef columnArray = OMCDataBrowserGetColumnArray(dbControl);
	if( columnArray == NULL)
		return paramErr;

	CFStringRef newString = (CFStringRef)OMCDBStorageGetValue( columnArray, (CFIndex)(columnID-1024), (CFIndex)(rowID-1) );
	if(newString != NULL)
		status = ::SetDataBrowserItemDataText( itemData, newString );

	return status;
}

OSStatus
OMCTerminateDataBrowserControl(EventHandlerCallRef inHandlerCallRef, EventRef inEvent, void *inUserData)
{
	ControlRef dbControl = NULL;
	UInt32 actualSize = 0;
	OSStatus status = ::GetEventParameter(inEvent, kEventParamDirectObject, typeControlRef, NULL, sizeof(ControlRef), &actualSize, &dbControl);
	if( (status != noErr) || (dbControl == NULL) || (actualSize != sizeof(ControlRef)) )
		return paramErr;

	CFMutableArrayRef columnArray = NULL;
	actualSize = 0;
	status = ::GetControlProperty( dbControl, 'omc!', 'colA', sizeof(CFMutableArrayRef), &actualSize, &columnArray );
	if( (status != noErr) || (actualSize != sizeof(CFMutableArrayRef)) || (columnArray == NULL) )
		return (status == noErr) ? paramErr : status;
	::CFRelease(columnArray);
	::RemoveControlProperty(dbControl, 'omc!', 'colA');
	return noErr;
}

OSStatus OMCInitializeDataBrowserControl(ControlRef  dbControl)
{
//    const       ControlID  dbControlID  = { 'OMC!', 3 };
    OSStatus    status = noErr;
 
//    ControlRef  dbControl = NULL;
    DataBrowserCallbacks  dbCallbacks;
 
//    GetControlByID( window, &inDBControlID, &dbControl );
	if(dbControl == NULL)
		return paramErr;

	CFObj<CFMutableArrayRef> columnArray( ::CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks) );//empty array created on init	
	status = ::SetControlProperty(dbControl, 'omc!', 'colA', sizeof(CFMutableArrayRef), &columnArray);

	UInt32 columnCount = 0;
	status = ::GetDataBrowserTableViewColumnCount(dbControl, &columnCount);

	if( columnCount > 0 )
	{//nib file already includes some columns.
	//add internal storage for them
		CFObj<CFMutableArrayRef> oneRowArray( ::CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks) );
		::CFArrayAppendValue( columnArray, (CFMutableArrayRef)oneRowArray );
	}

//temp here for testing
    OMCLoadTestData(columnArray);
	CFIndex newColumnCount = 0;
	if(columnArray != NULL)
		newColumnCount = ::CFArrayGetCount(columnArray);

	//must release columnArray before killing the datbrowser control
	//set-up the control destruction notification callback:
	EventTypeSpec dbControlEvent  = { kEventClassControl, kEventControlDispose };	
	EventHandlerUPP handlerUPP = NewEventHandlerUPP(OMCTerminateDataBrowserControl);
	status = ::InstallControlEventHandler(dbControl, handlerUPP, 1, &dbControlEvent, NULL, NULL);
	if(status == noErr)
		columnArray.Detach();//success - the control takes ownership of the array from now on
	
    dbCallbacks.version = kDataBrowserLatestCallbacks;
    InitDataBrowserCallbacks( &dbCallbacks );
    dbCallbacks.u.v1.itemDataCallback = NewDataBrowserItemDataUPP( (DataBrowserItemDataProcPtr)OMCDataBrowserItemDataCallback );

    SetDataBrowserCallbacks(dbControl, &dbCallbacks);

//    SetAutomaticControlDragTrackingEnabledForWindow (window, true);
 
//when setting up columns:

	DataBrowserListViewColumnDesc oneColumnDesc;
	memset(&oneColumnDesc, 0, sizeof(oneColumnDesc) );
	oneColumnDesc.propertyDesc.propertyType = kDataBrowserTextType;
	oneColumnDesc.propertyDesc.propertyFlags = kDataBrowserDefaultPropertyFlags; // kDataBrowserPropertyIsMutable
	oneColumnDesc.headerBtnDesc.version = kDataBrowserListViewLatestHeaderDesc;
	oneColumnDesc.headerBtnDesc.minimumWidth = 20; //0;
	oneColumnDesc.headerBtnDesc.maximumWidth = 180; //0xFFFF;
	oneColumnDesc.headerBtnDesc.titleOffset = 0;
	oneColumnDesc.headerBtnDesc.titleString = NULL;
	oneColumnDesc.headerBtnDesc.initialOrder = kDataBrowserOrderIncreasing; //kDataBrowserOrderDecreasing
	oneColumnDesc.headerBtnDesc.btnFontStyle.flags = kControlUseJustMask;//no special font info, use system settings
	oneColumnDesc.headerBtnDesc.btnFontStyle.just = teCenter;
	oneColumnDesc.headerBtnDesc.btnContentInfo.contentType = kControlNoContent;

	for(CFIndex i = 0; i < (newColumnCount-columnCount); i++)
	{
		UniChar one[1];
		one[0] = 'A'+i;
		CFObj<CFStringRef> headStr( ::CFStringCreateWithCharacters( kCFAllocatorDefault, one, 1) );
		oneColumnDesc.headerBtnDesc.titleString = headStr;
		oneColumnDesc.propertyDesc.propertyID = columnCount + i + 1024;//column IDs start from 1024
		status  = ::AddDataBrowserListViewColumn(dbControl, &oneColumnDesc, kDataBrowserListViewAppendColumn );
	}

//when setting up rows:
	UInt32 rowCount = 0;
	status = ::GetDataBrowserItemCount (
					dbControl,
					kDataBrowserNoItem,
					false, //recurse,
					kDataBrowserItemNoState,
					&rowCount );

	UInt32 newItemCount = 3;//temp
	AStdArrayNew<DataBrowserItemID> newIDList(newItemCount);

	for(UInt32 i = 0; i < newItemCount; i++)
	{
		newIDList[i] = rowCount + i + 1;//row IDs start from 1
	}
	
    status = AddDataBrowserItems (dbControl,
    						kDataBrowserNoItem, //container ID
    						newItemCount, 
							newIDList, //NULL not recommended because it clears all rows
                            kDataBrowserItemNoProperty ); //The property ID of the column whose sorting order matches the sorting order
                          	//of the items array. A property ID is a four-character sequence that you assign to represent
                          	//a column in list view. Pass kDataBrowserItemNoProperty if the items array is not sorted or
                          	//if you don’t know the sorting order of your data. You’ll get the best performance from this function
                          	//if you provide a sorting order.

//	status = ::AutoSizeDataBrowserListViewColumns( dbControl );
    return status;
}


OSStatus
OMCDataBrowserAddRow( ControlRef dbControl, CFArrayRef inRowItems )
{
	CFMutableArrayRef columnArray = OMCDataBrowserGetColumnArray(dbControl);
	if( columnArray == NULL)
		return paramErr;

	return noErr;
}


OSStatus
OMCDataBrowserAddItemsToColumn( ControlRef dbControl, CFArrayRef inItems )
{
	CFMutableArrayRef columnArray = OMCDataBrowserGetColumnArray(dbControl);
	if( columnArray == NULL)
		return paramErr;

	return noErr;
}


//data physically stored in columns (vertically)
//this function gets the the item from row array (can be CFStringRef or other CFTypeRef)
//inColumnArray is a list of row arrays in column array
CFTypeRef
OMCDBStorageGetValue(CFArrayRef inColumnArray, CFIndex inColumn, CFIndex inRow)
{
	if(inColumnArray == NULL)
		return NULL;
	CFIndex columnCount = ::CFArrayGetCount(inColumnArray);
	if( (inColumn < 0) || (inColumn >= columnCount) )
		return NULL;
	CFArrayRef rowArray = (CFArrayRef)::CFArrayGetValueAtIndex(inColumnArray, inColumn);
	if(rowArray == NULL)
		return NULL;
	CFIndex rowCount = ::CFArrayGetCount(rowArray);
	if( (inRow < 0) || (inRow >= rowCount) )
		return NULL;
	return ::CFArrayGetValueAtIndex(rowArray, inRow);
}
*/

#pragma mark -

//static
OSStatus
OMCDataBrowser::InitializeControl(ControlRef dbControl)
{
	OSStatus    status = noErr;
    DataBrowserCallbacks  dbCallbacks;
	if(dbControl == NULL)
		return paramErr;
	
	OMCDataBrowser *omcController = new OMCDataBrowser(dbControl);
	status = ::SetControlProperty(dbControl, 'omc!', 'Crlr', sizeof(OMCDataBrowser *), &omcController );
	AStdNew<OMCDataBrowser> ctrlDel( omcController );

	//must delete omcController before killing the datbrowser control
	//set-up the control destruction notification callback:
	EventTypeSpec dbControlEvent  = { kEventClassControl, kEventControlDispose };	
	EventHandlerUPP handlerUPP = NewEventHandlerUPP(OMCDataBrowser::TerminateHandler);
	status = ::InstallControlEventHandler(dbControl, handlerUPP, 1, &dbControlEvent, NULL /*userData*/, NULL /*outHandlerRef*/);
	if(status == noErr)
		ctrlDel.Detach();//success - the control takes ownership of the controller from now on

	//data browser receiving a click in inactive window does not activate this window
	//install a handler to deal with this situation
	EventTypeSpec clickControlEvent  = { kEventClassControl, kEventControlGetClickActivation };	
	EventHandlerUPP subViewClickHandlerUPP = NewEventHandlerUPP(OMCDataBrowser::GetClickActivationHandler);
	status = ::InstallControlEventHandler(dbControl, subViewClickHandlerUPP, 1, &clickControlEvent, NULL /*userData*/, NULL /*outHandlerRef*/);

	status = omcController->RemoveColumns();//remove any columns that may have been added to the nib. we cannot use them because we need to assign our own IDs.

	const void * colArr[1];
	colArr[0] = (const void *)CFSTR(" ");
	CFObj<CFArrayRef> oneColumnArr( ::CFArrayCreate( kCFAllocatorDefault, colArr, 1, &kCFTypeArrayCallBacks ) );
	status = omcController->AddColumns(oneColumnArr);//one column must be there or DB will freak out and freeze
	omcController->mColumnNames.Release();//this column array is temporary, do not keep it

    dbCallbacks.version = kDataBrowserLatestCallbacks;
    InitDataBrowserCallbacks( &dbCallbacks );
    dbCallbacks.u.v1.itemDataCallback = NewDataBrowserItemDataUPP( (DataBrowserItemDataProcPtr)OMCDataBrowser::ItemDataHandler );
	dbCallbacks.u.v1.itemNotificationCallback = NewDataBrowserItemNotificationUPP( OMCDataBrowser::ItemNotificationHandler );

    SetDataBrowserCallbacks(dbControl, &dbCallbacks);

	//we always want this because otherwise we don't see a selection
	//the deafult table value in InterfaceBuilder is kDataBrowserTableViewMinimalHilite
	::SetDataBrowserTableViewHiliteStyle( dbControl, kDataBrowserTableViewFillHilite );

	DataBrowserItemID selRows[1];
	selRows[0] = 1;
	status = ::SetDataBrowserSelectedItems( dbControl, 1, selRows, kDataBrowserItemsAssign );//select first row.  don't care about the result
	
	return noErr;
}

//static
OMCDataBrowser *
OMCDataBrowser::GetController(WindowRef inWindow, const ControlID &dbControlID)
{
	if(inWindow == NULL)
		return NULL;

	ControlRef myControl = NULL;
	OSStatus err = ::GetControlByID(inWindow, &dbControlID, &myControl);

	if( (err != noErr) || (myControl == NULL) )
		return NULL;

	ControlKind controlKind = {0,0};
	err = ::GetControlKind(myControl, &controlKind);
	if( (err != noErr) || (controlKind.signature != kControlKindSignatureApple) || (controlKind.kind != kControlKindDataBrowser) )
		return NULL;

	return OMCDataBrowser::GetController(myControl);
}


//static
OMCDataBrowser *
OMCDataBrowser::GetController(ControlRef dbControl)
{
	UInt32 actualSize = 0;
	OMCDataBrowser *outController = NULL;
	OSStatus status = ::GetControlProperty( dbControl, 'omc!', 'Crlr', sizeof(OMCDataBrowser *), &actualSize, &outController );
	if( (status != noErr) || (actualSize != sizeof(OMCDataBrowser *)) )
		return NULL;
	return outController;
}

OSStatus
OMCDataBrowser::TerminateHandler(EventHandlerCallRef /*inHandlerCallRef*/, EventRef inEvent, void * /*inUserData*/)
{
	ControlRef dbControl = NULL;
	UInt32 actualSize = 0;
	OSStatus status = ::GetEventParameter(inEvent, kEventParamDirectObject, typeControlRef, NULL, sizeof(ControlRef), &actualSize, &dbControl);
	if( (status != noErr) || (dbControl == NULL) || (actualSize != sizeof(ControlRef)) )
		return paramErr;

	OMCDataBrowser *theController = OMCDataBrowser::GetController(dbControl);
	delete theController;
	::RemoveControlProperty(dbControl, 'omc!', 'Crlr');
	return noErr;
}

//data browser receiving a click in inactive window does not activate this window (so you can drag items without bringing window to front)
//this handler changes the behavior and alays switches the window to the front

OSStatus
OMCDataBrowser::GetClickActivationHandler(EventHandlerCallRef /*inHandlerCallRef*/, EventRef inEvent, void * /*inUserData*/)
{
	ClickActivationResult activationType = kActivateAndHandleClick;
	return ::SetEventParameter( inEvent, kEventParamClickActivation, typeClickActivationResult, sizeof(activationType), &activationType );
}

OSStatus
OMCDataBrowser::ItemDataHandler(
				ControlRef dbControl,
                DataBrowserItemID rowID,
                DataBrowserPropertyID columnID,
                DataBrowserItemDataRef itemData,
                Boolean changeValue)
{
	OMCDataBrowser *theController = OMCDataBrowser::GetController(dbControl);
	if( theController != NULL )
		return theController->HandleItemData(rowID, columnID, itemData, changeValue);
	return errDataBrowserPropertyNotSupported;
}

void
OMCDataBrowser::ItemNotificationHandler(
	ControlRef dbControl, 
	DataBrowserItemID itemID, 
	DataBrowserItemNotification message)
{
	OMCDataBrowser *theController = OMCDataBrowser::GetController(dbControl);
	if( theController != NULL )
		return theController->HandleNotification(itemID, message);
}

#pragma mark -

OMCDataBrowser::OMCDataBrowser(ControlRef dbControl)
	: mControl(dbControl), mSeparator(kOMCColumnSeparatorTab), mOnSelectCommandID(0), mOnDoubleClickCommandID(0)
{
	mRowArray.Adopt( ::CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks), kCFObjDontRetain );//empty array created on init

	CFObj<CFStringRef> selectionCommandID( NibDialogControl::CreateControlPropertyString(dbControl, 'OMC!', kOnSelectCommandIdKey) );
	if(selectionCommandID != NULL)
		mOnSelectCommandID = ::UTGetOSTypeFromString( selectionCommandID );
	
	
	CFObj<CFStringRef> doubleClickCommandID( NibDialogControl::CreateControlPropertyString(dbControl, 'OMC!', kOnDoubleClickCommandIdKey) );
	if(doubleClickCommandID != NULL)
		mOnDoubleClickCommandID = ::UTGetOSTypeFromString( doubleClickCommandID );
}


OMCDataBrowser::~OMCDataBrowser()
{
}

OSStatus
OMCDataBrowser::HandleItemData(
				DataBrowserItemID rowID,
                DataBrowserPropertyID columnID,
                DataBrowserItemDataRef itemData,
                Boolean changeValue)
{
	OSStatus status = errDataBrowserPropertyNotSupported;

	CFStringRef newString = (CFStringRef)GetValue( (CFIndex)(columnID-1024), (CFIndex)(rowID-1) );

	if(newString != NULL)
		status = ::SetDataBrowserItemDataText( itemData, newString );

	return status;
}

void
OMCDataBrowser::HandleNotification(	DataBrowserItemID itemID, 
									DataBrowserItemNotification message)
{
	const HICommand kNullHICommand = { 0, 0, {NULL, 0 } };

	switch(message)
	{
		case kDataBrowserSelectionSetChanged:
		{
			if(mOnSelectCommandID != 0)
			{
				HICommand hiCommand = kNullHICommand;
				hiCommand.commandID = mOnSelectCommandID;
				::ProcessHICommand(&hiCommand);
			}
		}
		break;

		case kDataBrowserItemDoubleClicked:
		{
			if(mOnDoubleClickCommandID != 0)
			{
				HICommand hiCommand = kNullHICommand;
				hiCommand.commandID = mOnDoubleClickCommandID;
				::ProcessHICommand(&hiCommand);
			}
		}
		break;
	}
}


//data physically stored in rows (horizontally)
//rows can be strings (not splitted yet)
//or rows can be arrays of items (columns)
//0-based indexes here!

CFTypeRef
OMCDataBrowser::GetValue(CFIndex inColumn, CFIndex inRow)
{
	CFArrayRef columnsOfItems = GetColumnArrayForRow(inRow);
	
	if(columnsOfItems != NULL) 
	{
		CFIndex columnCount = ::CFArrayGetCount(columnsOfItems);
		if( (inColumn < 0) || (inColumn >= columnCount) )
			return NULL;
		return ::CFArrayGetValueAtIndex(columnsOfItems, inColumn);
	}
	return NULL;
}

//0-based indexes
CFArrayRef
OMCDataBrowser::GetColumnArrayForRow(CFIndex inRow)
{
	if(mRowArray == NULL)
		return NULL;

	CFIndex rowCount = ::CFArrayGetCount(mRowArray);
	if( (inRow < 0) || (inRow >= rowCount) )
		return NULL;

	CFTypeRef oneRowRef = ::CFArrayGetValueAtIndex(mRowArray, inRow);
	if(oneRowRef == NULL)
		return NULL;

	CFTypeID rowType = ::CFGetTypeID(oneRowRef);
	if( rowType == ACFType<CFStringRef>::sTypeID )
	{//it is a string, needs splitting
		CFObj<CFArrayRef> itemsArray( SplitRowString( (CFStringRef)oneRowRef ) );
		if(itemsArray != NULL)
		{
			::CFArraySetValueAtIndex( mRowArray, inRow, (CFArrayRef)itemsArray);//replace string with array, retained
			oneRowRef = (CFArrayRef)itemsArray;
		}
	}
	
	return (CFArrayRef)oneRowRef;
}

//creates new array, owner responsible for releasing non-NULL array
CFArrayRef
OMCDataBrowser::SplitRowString(CFStringRef inRowString)
{
	CFArrayRef outRowArray = NULL;
	
	if(mSeparator == kOMCColumnSeparatorTab)
	{
		outRowArray = ::CFStringCreateArrayBySeparatingStrings( kCFAllocatorDefault, inRowString, CFSTR("\t") );	
	}
	else
	{
		printf("OMCDataBrowser::SplitRowString. splitting non tab-separated columns not supported yet\n");
	}
	
	return outRowArray;
}

OSStatus
OMCDataBrowser::RemoveRows()
{
	if( mRowArray != NULL)
		::CFArrayRemoveAllValues( mRowArray );

	if(mControl == NULL)
		return errUnknownControl;

	return ::RemoveDataBrowserItems (
				mControl,
				kDataBrowserNoItem,
				0, //numItems,
				NULL, //const DataBrowserItemID *items,
				kDataBrowserItemNoProperty );
}

OSStatus
OMCDataBrowser::AddRows(CFArrayRef inNewRows)
{
	if(inNewRows == NULL)
		return noErr;

	CFIndex newRowCount = ::CFArrayGetCount(inNewRows);
	if(newRowCount == 0)
		return noErr;

	::CFArrayAppendArray( mRowArray, inNewRows, ::CFRangeMake(0, newRowCount) );

	if(mControl == NULL)
		return errUnknownControl;

	UInt32 oldRowCount = 0;
	OSStatus status = ::GetDataBrowserItemCount (
					mControl,
					kDataBrowserNoItem,
					false, //recurse,
					kDataBrowserItemNoState,
					&oldRowCount );

	AStdArrayNew<DataBrowserItemID> newIDList(newRowCount);

	for(UInt32 i = 0; i < newRowCount; i++)
	{
		newIDList[i] = oldRowCount + i + 1;//row IDs start from 1
	}
	
	status = ::AddDataBrowserItems( mControl,
    						kDataBrowserNoItem, //container ID
    						newRowCount, 
							newIDList, //NULL not recommended because it clears all rows
                            kDataBrowserItemNoProperty ); //The property ID of the column whose sorting order matches the sorting order
                          	//of the items array. A property ID is a four-character sequence that you assign to represent
                          	//a column in list view. Pass kDataBrowserItemNoProperty if the items array is not sorted or
                          	//if you don’t know the sorting order of your data. You’ll get the best performance from this function
                          	//if you provide a sorting order.

	if(oldRowCount == 0)
	{
		//DataBrowserItemID selRows[1];
		//selRows[0] = 1;
		//(void)::SetDataBrowserSelectedItems( mControl, 1, selRows, kDataBrowserItemsAssign );//select first row.  don't care about the result
		//reveal first row and first column
		(void)::RevealDataBrowserItem( mControl, (DataBrowserItemID)1, (DataBrowserPropertyID)1024, kDataBrowserRevealOnly );
	}
	return status;
}


OSStatus
OMCDataBrowser::RemoveColumns()
{
	if(mControl == NULL)
		return errUnknownControl;

	UInt32 columnCount = 0;
	OSStatus status = ::GetDataBrowserTableViewColumnCount( mControl, &columnCount );
	
	if(columnCount == 0)
		return noErr;//nothing to remove
	
	for(CFIndex i = (columnCount - 1); i >= 0; i-- )
	{
		DataBrowserTableViewColumnID columnID = kDataBrowserItemNoProperty;
		status = ::GetDataBrowserTableViewColumnProperty( mControl, (DataBrowserTableViewColumnIndex)i, &columnID);
		if( (status == noErr) && (columnID != kDataBrowserItemNoProperty) )
		{
			status = ::RemoveDataBrowserTableViewColumn( mControl, columnID );
		}
	}
	return status;
}

OSStatus
OMCDataBrowser::AddColumns(CFArrayRef inNewColumns)
{
	if(inNewColumns == NULL)
		return noErr;

	CFIndex newColumnCount = ::CFArrayGetCount(inNewColumns);
	if(newColumnCount == 0)
		return noErr;

	mColumnNames.Adopt(inNewColumns, kCFObjRetain);

	DataBrowserListViewColumnDesc oneColumnDesc;
	memset(&oneColumnDesc, 0, sizeof(oneColumnDesc) );
	oneColumnDesc.propertyDesc.propertyType = kDataBrowserTextType;
	oneColumnDesc.propertyDesc.propertyFlags = kDataBrowserDefaultPropertyFlags; // kDataBrowserPropertyIsMutable
	oneColumnDesc.headerBtnDesc.version = kDataBrowserListViewLatestHeaderDesc;
	oneColumnDesc.headerBtnDesc.minimumWidth = 0;
	oneColumnDesc.headerBtnDesc.maximumWidth = 0xFFFF;
	oneColumnDesc.headerBtnDesc.titleOffset = 0;
	oneColumnDesc.headerBtnDesc.titleString = NULL;
	oneColumnDesc.headerBtnDesc.initialOrder = kDataBrowserOrderIncreasing; //kDataBrowserOrderDecreasing
	oneColumnDesc.headerBtnDesc.btnFontStyle.flags = kControlUseJustMask;//no special font info, use system settings
	oneColumnDesc.headerBtnDesc.btnFontStyle.just = teFlushDefault;//teCenter;
	oneColumnDesc.headerBtnDesc.btnContentInfo.contentType = kControlNoContent;

	UInt32 oldColumnCount = 0;
	OSStatus status = ::GetDataBrowserTableViewColumnCount(mControl, &oldColumnCount);

	UInt16 columnWidth = 100;
	CFStringRef hiddenColumnName = CFSTR("omc_hidden_column");
	for(CFIndex i = 0; i < newColumnCount; i++)
	{
		CFTypeRef oneColRef = ::CFArrayGetValueAtIndex(inNewColumns, i);
		CFStringRef headStr = ACFType<CFStringRef>::DynamicCast(oneColRef);
		if(headStr == NULL)
			headStr = CFSTR("");
		
		//we skip hidden columns. ids are also skipped so the propertyID will be correct for next column and will point to right item in internal array
		if( kCFCompareEqualTo != ::CFStringCompare( headStr, hiddenColumnName, 0) )
		{
			oneColumnDesc.headerBtnDesc.titleString = headStr;
			oneColumnDesc.propertyDesc.propertyID = oldColumnCount + i + 1024;//column IDs start from 1024
			status  = ::AddDataBrowserListViewColumn(mControl, &oneColumnDesc, kDataBrowserListViewAppendColumn );
			status  = ::SetDataBrowserTableViewNamedColumnWidth( mControl, oneColumnDesc.propertyDesc.propertyID, columnWidth );//init width to some reasonable value
		}
	}

	//column widths were set earlier, before column names were set
	if( (status == noErr) && (mColumnWidths != NULL) )
	{
		SetColumnWidths(mColumnWidths);
	}
	
	return status;
}

void
OMCDataBrowser::SetColumnWidths(CFArrayRef inColumnWidths)
{
	OSStatus status = noErr;
	CFIndex columnWidthCount = ::CFArrayGetCount(inColumnWidths);
	if(columnWidthCount == 0)
		return;

	mColumnWidths.Adopt(inColumnWidths, kCFObjRetain);

	if(mColumnNames == NULL) //column names not set yet, do not set widths
		return;

	CFIndex columnNameCount = ::CFArrayGetCount(mColumnNames);
	if(columnNameCount == 0)
		return;

	CFStringRef hiddenColumnName = CFSTR("omc_hidden_column");

	//limit to max number of columns already added
	if( columnWidthCount > columnNameCount )
		columnWidthCount = columnNameCount;

	for(CFIndex i = 0; i < columnWidthCount; i++)
	{
		CFTypeRef oneColRef = ::CFArrayGetValueAtIndex(mColumnNames, i);
		CFStringRef nameStr = ACFType<CFStringRef>::DynamicCast(oneColRef);
		
		//we skip hidden columns. ids are also skipped so the propertyID will be correct for next column and will point to right item in internal array
		if( (nameStr != NULL) && (kCFCompareEqualTo != ::CFStringCompare(nameStr, hiddenColumnName, 0)) )
		{
			CFStringRef oneWidthString = ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(inColumnWidths, i) );
			if(oneWidthString != NULL)
			{
				SInt32 oneWidth = ::CFStringGetIntValue( oneWidthString );
				if(oneWidth < 0)
					oneWidth = 0;
				if(oneWidth > 0xFFFF)
					oneWidth = 0xFFFF;

				status = ::SetDataBrowserTableViewNamedColumnWidth(mControl, i + 1024, oneWidth);

/*
				OSStatus SetDataBrowserListViewHeaderDesc (
				   ControlRef browser,
				   DataBrowserTableViewColumnID column,
				   DataBrowserListViewHeaderDesc *desc
				);
*/
			}
		}
	}
}

//both indexes are 1-based
//column = 0 is special value, meaning: "take all column values"
CFTypeRef
OMCDataBrowser::CopyValue(SInt32 inRowIndex, SInt32 inColumnIndex)
{
	if(mControl == NULL)
		return NULL;

	if(inColumnIndex == 0)
	{//special case - take values from all columns 
		CFArrayRef columnArr = GetColumnArrayForRow( (CFIndex)(inRowIndex-1) );
		if(columnArr == NULL)
			return NULL;
		CFIndex columnCount = ::CFArrayGetCount( columnArr );
		if(columnCount > 1)
		{
			::CFRetain(columnArr);
			return columnArr;
		}
		else if(columnCount == 1)
		{//just one column, use the first column and get 1 string
			CFStringRef selString = (CFStringRef)::CFArrayGetValueAtIndex(columnArr, 0);
			if(selString != NULL)
				::CFRetain(selString);
			return selString;
		}
		return NULL;
	}

	//one cell value
	//row ids & column ids are 1-based. we need to go down to 0-based for CFArrays
	CFStringRef selString = (CFStringRef)GetValue( (CFIndex)(inColumnIndex-1), (CFIndex)(inRowIndex-1) );
	if(selString != NULL)
		::CFRetain(selString);
	return selString;
}


//inColumnIndex is 1-based
//may return single string or array of strings for multple row selection or all columns in single row
CFTypeRef
OMCDataBrowser::CopySelectionValue(SInt32 inColumnIndex, SelectionIterator *inIterator)
{
	if(mControl == NULL)
		return NULL;

	DataBrowserItemID firstRowID = 0;

	if( inIterator != NULL )
	{//we are iterating through selected rows
		CFTypeRef outValue = NULL;
		if( SelectionIterator_IsValid(inIterator) )//caller should really check it but we have to make sure it is OK here
		{
			firstRowID = SelectionIterator_GetCurrentSelection(inIterator);
			outValue = CopyValue(firstRowID, inColumnIndex);
		}
		return outValue;
	}

	DataBrowserItemID lastRowID = 0;
	OSStatus status = ::GetDataBrowserSelectionAnchor( mControl, &firstRowID, &lastRowID );
	if(status != noErr)
		return NULL;
	
	if( (lastRowID < firstRowID) && (lastRowID != 0) )//something messed up
		firstRowID = lastRowID;

	if(firstRowID == 0)
		return NULL;
	
	//only one row selected or all collumns requested: in this case we take only first row
	if( (firstRowID == lastRowID) || (inColumnIndex <= 0) )
		return CopyValue(firstRowID, inColumnIndex);

	CFObj<CFMutableArrayRef> selectedItems( ::CFArrayCreateMutable(kCFAllocatorDefault, lastRowID-firstRowID+1, &kCFTypeArrayCallBacks));
	
	for( DataBrowserItemID currRowID = firstRowID; currRowID <= lastRowID; currRowID++)
	{
		bool isSelected = (currRowID == firstRowID) || (currRowID == lastRowID) || ::IsDataBrowserItemSelected(mControl, currRowID);
		if(isSelected)
		{
			//what if this is an array of strings, not a string?
			CFStringRef selString = (CFStringRef)GetValue((CFIndex)(inColumnIndex-1), (CFIndex)(currRowID-1));
			::CFArrayAppendValue( selectedItems, selString );//retained
		}
	}
	
	return selectedItems.Detach();
}


SelectionIterator *
OMCDataBrowser::CreateSelectionIterator(bool useReverseIterator)
{
	if(mControl == NULL)
		return NULL;

	DataBrowserItemID firstRowID = 0;
	DataBrowserItemID lastRowID = 0;
	OSStatus status = ::GetDataBrowserSelectionAnchor( mControl, &firstRowID, &lastRowID );
	if(status != noErr)
		return NULL;
	
	if( (lastRowID < firstRowID) && (lastRowID != 0) )//something messed up
		firstRowID = lastRowID;

	if(firstRowID == 0)
		return NULL;
	
	size_t selectedRowsCount = 0;
	size_t rowCount = lastRowID-firstRowID+1;//not selected rows count but the number of rows between first selected and last selected

	unsigned long *selectedRows = (unsigned long *)calloc(rowCount, sizeof(unsigned long));

	if(useReverseIterator)
	{
		for( DataBrowserItemID currRowID = lastRowID; currRowID >= firstRowID; currRowID-- )
		{
			bool isSelected = (currRowID == firstRowID) || (currRowID == lastRowID) || ::IsDataBrowserItemSelected(mControl, currRowID);
			if(isSelected)
			{
				selectedRows[selectedRowsCount] = currRowID;
				selectedRowsCount++;
			}
		}
	}
	else
	{
		for( DataBrowserItemID currRowID = firstRowID; currRowID <= lastRowID; currRowID++)
		{
			bool isSelected = (currRowID == firstRowID) || (currRowID == lastRowID) || ::IsDataBrowserItemSelected(mControl, currRowID);
			if(isSelected)
			{
				selectedRows[selectedRowsCount] = currRowID;
				selectedRowsCount++;
			}
		}
	}
	//selectedRows ownership is passed to SelectionIterator object
	return SelectionIterator_Create(selectedRows, selectedRowsCount);//pass ownership of selectedRows to SelectionIterator
}

#endif // __LP64__


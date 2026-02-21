//
//  OMCWindowController.m
//  Abracode
//
//  Created by Tomasz Kukielka on 1/20/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import "OMCWindowController.h"
#import "OMCDialog.h"
#include "OnMyCommand.h"
#include "CommandRuntimeData.h"
#include "ACFDict.h"
#include <vector>

/*
 Method argument types. (Deprecated. These constants are used internally by NSInvocation—you should not use them directly.)
 
 enum _NSObjCValueType {
 NSObjCNoType = 0,
 NSObjCVoidType = 'v',
 NSObjCCharType = 'c',
 NSObjCShortType = 's',
 NSObjCLongType = 'l',
 NSObjCLonglongType = 'q',
 NSObjCFloatType = 'f',
 NSObjCDoubleType = 'd',
 
 NSObjCBoolType = 'B',
 
 NSObjCSelectorType = ':',
 NSObjCObjectType = '@',
 NSObjCStructType = '{',
 NSObjCPointerType = '^',
 NSObjCStringType = '*',
 NSObjCArrayType = '[',
 NSObjCUnionType = '(',
 NSObjCBitfield = 'b'
 };
 
 
 argument types:
 @ = id
 : = selector
 c = signed char
 C = unsigned char
 s = signed short
 S = unsigned short
 i = signed int
 I = unsigned int, some enums too
 q = long long
 Q = unsigned long long
 f = float
 d = double
 ^@ = *id
 v = void
 ^v  = void *
 {_NSRange=II} = NSRange {unsigned int, unsigned int}
 {_NSPoint=ff} = NSPoint {float, float}
 {_NSRect={_NSPoint=ff}{_NSSize=ff}}
 r* = const char *
 r^^{_NSRect} = const NSRect **
 */

typedef enum ObjCSelectorArgumentType
{
    kObjCArgNoType = 0,
    kObjCArgVoidType = 'v',
    kObjCArgCharType = 'c',
    kObjCArgUCharType = 'C',
    kObjCArgShortType = 's',
    kObjCArgUShortType = 'S',
    kObjCArgIntType = 'i',
    kObjCArgUIntType = 'I',
    kObjCArgLongType = 'l',
    kObjCArgULongType = 'L',
    kObjCArgLonglongType = 'q',
    kObjCArgULonglongType = 'Q',
    kObjCArgFloatType = 'f',
    kObjCArgDoubleType = 'd',
    
    kObjCArgBoolType = 'B',
    
    kObjCArgSelectorType = ':',
    kObjCArgObjectType = '@',
    kObjCArgStructType = '{',
    kObjCArgPointerType = '^',
    kObjCArgStringType = '*',
    kObjCArgArrayType = '[',
    kObjCArgUnionType = '(',
    kObjCArgBitfield = 'b'
} ObjCSelectorArgumentType;

static ObjCSelectorArgumentType
FindArgumentType(const char *argTypeStr)
{
    if(argTypeStr == NULL)
        return kObjCArgNoType;
    if(argTypeStr[0] == 'r')//const - skip it
        return (ObjCSelectorArgumentType)argTypeStr[1];
    return (ObjCSelectorArgumentType)argTypeStr[0];
}

static NSMutableSet<OMCWindowController *> *
GetAllDialogControllers()
{
    static NSMutableSet<OMCWindowController *> *sAllDialogControllers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sAllDialogControllers = [[NSMutableSet alloc] init];
    });

    return sAllDialogControllers;
}

@implementation OMCWindowController

+ (instancetype)findControllerByUUID:(NSString *)uuid
{
    for(OMCWindowController *controller in GetAllDialogControllers())
    {
        CFStringRef controllerUUID = controller->mOMCDialogProxy->GetDialogUUID();
        if(controllerUUID != NULL && [uuid isEqualToString:(__bridge NSString *)controllerUUID])
            return controller;
    }
    return nil;
}

- (id)initWithOmc:(OnMyCommandCM *)inOmc commandRuntimeData:(CommandRuntimeData *)inCommandRuntimeData
{
   self = [super init];
	if(self == nil)
		return nil;

    mIsModal = true;
	mIsRunning = false;

    mPlugin.Adopt(inOmc, kARefCountRetain);
    assert(inCommandRuntimeData != nullptr);
    mCommandRuntimeData.Adopt(inCommandRuntimeData, kARefCountRetain);

	mExternBundleRef.Adopt(inOmc->GetCurrentCommandExternBundle(), kCFObjRetain);

	CommandDescription &currCommand = mPlugin->GetCurrentCommand();
	mCommandName.Adopt(currCommand.name, kCFObjRetain);

    NSMutableSet<OMCWindowController *> *allDialogControllers = GetAllDialogControllers();
    [allDialogControllers addObject:self];

    return self;
}

- (void)dispatchCommand:(NSString *)inCommandID withContext:(CFTypeRef)inContext
{
    self.lastCommandID = inCommandID;
    
    if( [self commandShouldCloseDialog] )
    {
        // our windowWillClose will be called, which calls "terminate", which executes the proper termination command
        [self.window close];
    }
    else
    {
        [self processCommandWithContext:inContext];
    }
}

- (OMCDialog *)getOMCDialog
{
	return mOMCDialogProxy;
}

- (Boolean)isModal
{
	return mIsModal;
}

- (void)run
{
#if DEBUG
	NSLog(@"[OMCWindowController run] self.window=%@", (id)self.window);
#endif
	
	if( mIsModal )
	{
		if( [self initializeDialog] )
		{
			[NSApp runModalForWindow:self.window];
		}
	}
	else
	{
		if( [self initializeDialog] )
			[self.window makeKeyAndOrderFront:self];
	}
}

- (BOOL)isOkeyed
{
	if(self.lastCommandID != nil)
	{
		if(self.endOKSubcommandID != nil)
        {
            return [self.lastCommandID isEqualToString:self.endOKSubcommandID];
        }

		return [self.lastCommandID isEqualToString:@"omc.dialog.ok"];
	}
	return false;
}

- (BOOL)isCanceled
{
	if(self.lastCommandID != nil)
	{
		if(self.endCancelSubcommandID != nil)
        {
            return [self.lastCommandID isEqualToString:self.endCancelSubcommandID];
        }

		return [self.lastCommandID isEqualToString:@"omc.dialog.cancel"];
	}
	return false;
}

- (BOOL)commandShouldCloseDialog
{
	return ([self isOkeyed] || [self isCanceled]);
}

- (BOOL)initializeDialog
{
	NSString *origCommand = self.lastCommandID;

	self.lastCommandID = @"omc.dialog.initialize";
	if(self.dialogInitSubcommandID != nil)
    {
        self.lastCommandID = self.dialogInitSubcommandID;
    }
    
	mOMCDialogProxy->StartListening();

    [self processCommandWithContext:NULL];

	self.lastCommandID = origCommand;

	if(mPlugin->GetError() != noErr)
		return NO;

	return YES;
}

- (BOOL)terminate
{
	BOOL wasOkeyed = [self isOkeyed];
	NSString *origCommand = self.lastCommandID;
	
	self.lastCommandID = wasOkeyed ? @"omc.dialog.terminate.ok" : @"omc.dialog.terminate.cancel";

	if( wasOkeyed && (self.endOKSubcommandID != nil) )
    {
        self.lastCommandID = self.endOKSubcommandID;
    }
	else if( !wasOkeyed && (self.endCancelSubcommandID != nil) )
    {
        self.lastCommandID = self.endCancelSubcommandID;
    }
    
	[self processCommandWithContext:NULL];

    self.lastCommandID = origCommand;

	return YES;
}

- (void)windowWillClose:(NSNotification *)notification
{
	if( mIsModal )
	{
		[NSApp stopModal];
	}

	[self terminate];

    NSMutableSet<OMCWindowController *> *allDialogControllers = GetAllDialogControllers();
    [allDialogControllers removeObject:self];
}

- (OSStatus)processCommandWithContext:(CFTypeRef)inContext
{
	if(mPlugin == nullptr)
    {
        return paramErr;
    }
    
	SInt32 cmdIndex = -1;
    if(OMCDialog::IsPredefinedDialogCommandID((__bridge CFStringRef)self.lastCommandID))
    {
        cmdIndex = mPlugin->FindSubcommandIndex(mCommandName, (__bridge CFStringRef)self.lastCommandID);
    }
	else
    {
        cmdIndex = mPlugin->FindCommandIndex(mCommandName, (__bridge CFStringRef)self.lastCommandID);
    }
    
	if(cmdIndex < 0)
    {
        return errAEEventNotHandled;
    }
    
	CommandDescription &currCommand = mPlugin->GetCurrentCommand();
	SelectionIterator *oldIterator = mOMCDialogProxy->GetSelectionIterator();
	SelectionIterator *currentSelectionIterator = nullptr;
	if( currCommand.multipleSelectionIteratorParams != nullptr )
		currentSelectionIterator = [self createSelectionIterator:currCommand.multipleSelectionIteratorParams];

	mOMCDialogProxy->SetSelectionIterator(currentSelectionIterator);
	
	OSStatus status = noErr;

	do
	{
		status = mPlugin->ExecuteSubcommand( cmdIndex, mCommandRuntimeData, inContext );
	}
	while( (currentSelectionIterator != nullptr) && SelectionIterator_Next(currentSelectionIterator) );

	mOMCDialogProxy->SetSelectionIterator(oldIterator);

	SelectionIterator_Release(currentSelectionIterator);
	
	return status;
}

-(void)keepItem:(id)inItem
{
	if(inItem == NULL)
		return;
	
	if(self.dialogOwnedItems == NULL)
        self.dialogOwnedItems = [[NSMutableSet alloc] init];
	
	[self.dialogOwnedItems addObject:inItem];
}

// Stub in base class, concrete sublass implements appropriate logic
- (SelectionIterator *)createSelectionIterator:(CFDictionaryRef)inIteratorParams
{
    return nil;
}

#pragma mark - setControlValues: shared implementation

- (void)setControlValues:(CFDictionaryRef)inControlDict
{
	if( inControlDict == NULL )
		return;

	CFIndex itemCount = ::CFDictionaryGetCount(inControlDict);
	if(itemCount == 0)
		return;

	ACFDict controlValues(inControlDict);

	CFDictionaryRef removeListItemsDict;
	if( controlValues.GetValue(CFSTR("REMOVE_LIST_ITEMS"), removeListItemsDict) )
	{
		itemCount = ::CFDictionaryGetCount(removeListItemsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			::CFDictionaryGetKeysAndValues(removeListItemsDict, (const void **)keyList.data(), NULL);
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if(controlID != NULL)
					[self removeAllListItemsForControlID:(__bridge NSString *)controlID];
			}
		}
	}

	CFDictionaryRef setListItemsDict;
	if( controlValues.GetValue(CFSTR("SET_LIST_ITEMS"), setListItemsDict) )
	{
		itemCount = ::CFDictionaryGetCount(setListItemsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(setListItemsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) )
					[self setListItems:theArr forControlID:(__bridge NSString *)controlID];
			}
		}
	}

	CFDictionaryRef appendListItemsDict;
	if( controlValues.GetValue(CFSTR("APPEND_LIST_ITEMS"), appendListItemsDict) )
	{
		itemCount = ::CFDictionaryGetCount(appendListItemsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(appendListItemsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) )
					[self appendListItems:theArr forControlID:(__bridge NSString *)controlID];
			}
		}
	}

	CFDictionaryRef emptyTableDict;
	if( controlValues.GetValue(CFSTR("PREPARE_TABLE_EMPTY"), emptyTableDict) )
	{
		itemCount = ::CFDictionaryGetCount(emptyTableDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			::CFDictionaryGetKeysAndValues(emptyTableDict, (const void **)keyList.data(), NULL);
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if(controlID != NULL)
					[self emptyTableForControlID:(__bridge NSString *)controlID];
			}
		}
	}

	CFDictionaryRef removeTableRowsDict;
	if( controlValues.GetValue(CFSTR("REMOVE_TABLE_ROWS"), removeTableRowsDict) )
	{
		itemCount = ::CFDictionaryGetCount(removeTableRowsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			::CFDictionaryGetKeysAndValues(removeTableRowsDict, (const void **)keyList.data(), NULL);
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if(controlID != NULL)
					[self removeTableRowsForControlID:(__bridge NSString *)controlID];
			}
		}
	}

	CFDictionaryRef setTableRowsDict;
	if( controlValues.GetValue(CFSTR("SET_TABLE_ROWS"), setTableRowsDict) )
	{
		itemCount = ::CFDictionaryGetCount(setTableRowsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(setTableRowsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) )
					[self setTableRows:theArr forControlID:(__bridge NSString *)controlID];
			}
		}
	}

	CFDictionaryRef addTableRowsDict;
	if( controlValues.GetValue(CFSTR("ADD_TABLE_ROWS"), addTableRowsDict) )
	{
		itemCount = ::CFDictionaryGetCount(addTableRowsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(addTableRowsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) )
					[self addTableRows:theArr forControlID:(__bridge NSString *)controlID];
			}
		}
	}

	CFDictionaryRef addTableColumnsDict;
	if( controlValues.GetValue(CFSTR("SET_TABLE_COLUMNS"), addTableColumnsDict) )
	{
		itemCount = ::CFDictionaryGetCount(addTableColumnsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(addTableColumnsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) )
					[self setTableColumns:theArr forControlID:(__bridge NSString *)controlID];
			}
		}
	}

	CFDictionaryRef setTableWidthsDict;
	if( controlValues.GetValue(CFSTR("SET_TABLE_WIDTHS"), setTableWidthsDict) )
	{
		itemCount = ::CFDictionaryGetCount(setTableWidthsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(setTableWidthsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) )
					[self setTableColumnWidths:theArr forControlID:(__bridge NSString *)controlID];
			}
		}
	}

	CFDictionaryRef setPropertyDict;
	if( controlValues.GetValue(CFSTR("SET_PROPERTY"), setPropertyDict) )
	{
		itemCount = ::CFDictionaryGetCount(setPropertyDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(setPropertyDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) && (::CFArrayGetCount(theArr) >= 2) )
				{
					CFStringRef propKey   = ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 0) );
					CFStringRef jsonValue = ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 1) );
					if( (propKey != NULL) && (jsonValue != NULL) )
						[self setPropertyKey:(__bridge NSString *)propKey jsonValue:(__bridge NSString *)jsonValue forControlID:(__bridge NSString *)controlID];
				}
			}
		}
	}

	{
	CFDictionaryRef valuesDict = NULL;
	if( controlValues.GetValue(CFSTR("VALUES"), valuesDict) )
	{
		itemCount = ::CFDictionaryGetCount(valuesDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(valuesDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if(controlID != NULL)
				{
					[self setControlStringValue:(__bridge NSString *)ACFType<CFStringRef>::DynamicCast( valueList[i] )
									forControlID:(__bridge NSString *)controlID];
				}
			}
		}
	}
	}

	{
	CFDictionaryRef enableDisableDict = NULL;
	if( controlValues.GetValue(CFSTR("ENABLE_DISABLE"), enableDisableDict) )
	{
		itemCount = ::CFDictionaryGetCount(enableDisableDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(enableDisableDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFBooleanRef theVal = ACFType<CFBooleanRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theVal != NULL) )
				{
					BOOL doEnable = (BOOL)::CFBooleanGetValue(theVal);
					[self setControlEnabled:doEnable forControlID:(__bridge NSString *)controlID];
				}
			}
		}
	}
	}

	{
	CFDictionaryRef showHideDict = NULL;
	if( controlValues.GetValue(CFSTR("SHOW_HIDE"), showHideDict) )
	{
		itemCount = ::CFDictionaryGetCount(showHideDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(showHideDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFBooleanRef theVal = ACFType<CFBooleanRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theVal != NULL) )
				{
					BOOL makeVisible = (BOOL)::CFBooleanGetValue(theVal);
					[self setControlVisible:makeVisible forControlID:(__bridge NSString *)controlID];
				}
			}
		}
	}
	}

	{
	CFDictionaryRef commandIdsDict = NULL;
	if( controlValues.GetValue(CFSTR("COMMAND_IDS"), commandIdsDict) )
	{
		itemCount = ::CFDictionaryGetCount(commandIdsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(commandIdsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFStringRef theVal = ACFType<CFStringRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theVal != NULL) )
					[self setCommandID:(__bridge NSString *)theVal forControlID:(__bridge NSString *)controlID];
			}
		}
	}
	}

	{
	CFDictionaryRef selectDict = NULL;
	if( controlValues.GetValue(CFSTR("SELECT"), selectDict) )
	{
		itemCount = ::CFDictionaryGetCount(selectDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			::CFDictionaryGetKeysAndValues(selectDict, (const void **)keyList.data(), NULL);
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if(controlID != NULL)
				{
					if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_window"), 0) )
					{
						[self.window makeKeyAndOrderFront:self];
					}
					else if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_application"), 0) )
					{
						NSApplication *myApp = [NSApplication sharedApplication];
						if(myApp != nil)
							[myApp activateIgnoringOtherApps:YES];
					}
					else
					{
						[self selectControlWithID:(__bridge NSString *)controlID];
					}
				}
			}
		}
	}
	}

	{
	CFDictionaryRef terminateDict = NULL;
	if( controlValues.GetValue(CFSTR("TERMINATE"), terminateDict) )
	{
		itemCount = ::CFDictionaryGetCount(terminateDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(terminateDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFBooleanRef theVal = ACFType<CFBooleanRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theVal != NULL) )
				{
					if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_window"), 0) )
					{
						Boolean terminateOK = ::CFBooleanGetValue(theVal);
						NSString *commandID;
						if(terminateOK)
						{
							commandID = self.endOKSubcommandID ?: @"omc.dialog.ok";
						}
						else
						{
							commandID = self.endCancelSubcommandID ?: @"omc.dialog.cancel";
						}

						self.lastCommandID = commandID;
						[self.window close];
						return;
					}
					else if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_application"), 0) )
					{
						NSApplication *myApp = [NSApplication sharedApplication];
						if(myApp != NULL)
						{
							[myApp terminate:self];
							return;
						}
					}
				}
			}
		}
	}
	}

	{
		CFDictionaryRef moveDict = NULL;
		if( controlValues.GetValue(CFSTR("MOVE"), moveDict) )
		{
			itemCount = ::CFDictionaryGetCount(moveDict);
			if(itemCount > 0)
			{
				std::vector<CFTypeRef> keyList(itemCount);
				std::vector<CFTypeRef> valueList(itemCount);
				::CFDictionaryGetKeysAndValues(moveDict, (const void **)keyList.data(), (const void **)valueList.data());
				for(CFIndex i = 0; i < itemCount; i++)
				{
					CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
					CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );

					if( (controlID != NULL) && (theArr != NULL) )
					{
						NSPoint newTopLeftOrigin = {0, 0};
						CFIndex theCount = ::CFArrayGetCount(theArr);
						if(theCount > 0)
						{
							CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(theArr, 0);
							CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
							if(numString != NULL)
								newTopLeftOrigin.x = ::CFStringGetIntValue(numString);
						}

						if(theCount > 1)
						{
							CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(theArr, 1);
							CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
							if(numString != NULL)
								newTopLeftOrigin.y = ::CFStringGetIntValue(numString);
						}

						if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_window"), 0) )
						{
							[self setWindowTopLeftPosition:newTopLeftOrigin];
						}
						else
						{
							[self moveControlWithID:(__bridge NSString *)controlID toPosition:newTopLeftOrigin];
						}
					}
				}
			}
		}
	}

	{
		CFDictionaryRef scrollDict = NULL;
		if( controlValues.GetValue(CFSTR("SCROLL"), scrollDict) )
		{
			itemCount = ::CFDictionaryGetCount(scrollDict);
			if(itemCount > 0)
			{
				std::vector<CFTypeRef> keyList(itemCount);
				std::vector<CFTypeRef> valueList(itemCount);
				::CFDictionaryGetKeysAndValues(scrollDict, (const void **)keyList.data(), (const void **)valueList.data());
				for(CFIndex i = 0; i < itemCount; i++)
				{
					CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
					CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );

					if( (controlID != NULL) && (theArr != NULL) )
					{
						NSPoint newTopLeftOrigin = {0, 0};
						CFIndex theCount = ::CFArrayGetCount(theArr);
						if(theCount > 0)
						{
							CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(theArr, 0);
							CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
							if(numString != NULL)
								newTopLeftOrigin.x = ::CFStringGetIntValue(numString);
						}

						if(theCount > 1)
						{
							CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(theArr, 1);
							CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
							if(numString != NULL)
								newTopLeftOrigin.y = ::CFStringGetIntValue(numString);
						}

						[self scrollControlWithID:(__bridge NSString *)controlID toPosition:newTopLeftOrigin];
					}
				}
			}
		}
	}

	{
		CFDictionaryRef resizeDict = NULL;
		if( controlValues.GetValue(CFSTR("RESIZE"), resizeDict) )
		{
			itemCount = ::CFDictionaryGetCount(resizeDict);
			if(itemCount > 0)
			{
				std::vector<CFTypeRef> keyList(itemCount);
				std::vector<CFTypeRef> valueList(itemCount);
				::CFDictionaryGetKeysAndValues(resizeDict, (const void **)keyList.data(), (const void **)valueList.data());
				for(CFIndex i = 0; i < itemCount; i++)
				{
					CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
					CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
					if( (controlID != NULL) && (theArr != NULL) )
					{
						NSSize newSize = { 0, 0 };
						CFIndex theCount = ::CFArrayGetCount(theArr);
						if(theCount > 0)
						{
							CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(theArr, 0);
							CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
							if(numString != NULL)
								newSize.width = ::CFStringGetIntValue(numString);
						}

						if(theCount > 1)
						{
							CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(theArr, 1);
							CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
							if(numString != NULL)
								newSize.height = ::CFStringGetIntValue(numString);
						}

						if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_window"), 0) )
						{
							[self.window setContentSize:newSize];
						}
						else
						{
							[self resizeControlWithID:(__bridge NSString *)controlID toSize:newSize];
						}
					}
				}
			}
		}
	}

	{
	CFDictionaryRef invokeDict;
	if( controlValues.GetValue(CFSTR("INVOKE"), invokeDict) )
	{
		itemCount = ::CFDictionaryGetCount(invokeDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(invokeDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) )
				{
					id messageTarget = nil;
					if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_window"), 0) )
					{
						messageTarget = (id)self.window;
					}
					else if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_application"), 0) )
					{
						messageTarget = (id)[NSApplication sharedApplication];
					}
					else if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_workspace"), 0) )
					{
						messageTarget = (id)[NSWorkspace sharedWorkspace];
					}

					if(messageTarget != nil)
					{
						[self invokeMessages:theArr onTarget:messageTarget];
					}
					else
					{
						[self invokeMessagesForControlID:(__bridge NSString *)controlID messages:theArr];
					}
				}
			}
		}
	}
	}
}

- (void)setWindowTopLeftPosition:(NSPoint)absolutePosition
{
	NSRect windowFrame = [self.window frame];

	NSScreen *mainScreen = [NSScreen mainScreen];
	NSRect screenRect = [mainScreen visibleFrame];

	{//absolute position
		absolutePosition.x += screenRect.origin.x;
		absolutePosition.y = screenRect.origin.y + screenRect.size.height - absolutePosition.y - windowFrame.size.height;//bottom of the window
		if( (absolutePosition.y + windowFrame.size.height) < screenRect.origin.y )
			absolutePosition.y = screenRect.origin.y - windowFrame.size.height + 20;//winodw top visible at the bottom of the screen
	}

	[self.window setFrameOrigin:absolutePosition];
}


- (void)invokeMessages:(CFArrayRef)messages onTarget:(id)target
{
    CFIndex messageCount = ::CFArrayGetCount(messages);
    for(CFIndex msgIndex = 0; msgIndex < messageCount; msgIndex++)
    {
        CFArrayRef oneObjCMessage = ACFType<CFArrayRef>::DynamicCast( ::CFArrayGetValueAtIndex(messages, msgIndex) );
        if(oneObjCMessage != NULL)
            [self sendObjCMessage:oneObjCMessage toTarget:target];
    }
}

- (void) sendObjCMessage:(CFArrayRef)oneObjCMessage toTarget:(id)messageTarget
{
    CFLocaleRef currentLocale = NULL;
    CFNumberFormatterRef numberFormatter = NULL;

    @try
    {
        //TODO:
        //check if object responds to given message
        //obtain NSMethodSignature, check argument types
        //create NSInvocation and invoke on object
        CFIndex elementCount = CFArrayGetCount(oneObjCMessage);
        if( elementCount == 0 )
            return;

        NSMutableString *methodName = [NSMutableString string];
        for(CFIndex i = 0; i < elementCount; i+=2)
        {//first obtain method name
            CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(oneObjCMessage, i);
            CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
            if(oneString != NULL)
            {
                [methodName appendString:(__bridge NSString *)oneString];
            }
        }

        SEL methodSelector = NSSelectorFromString(methodName);
        NSMethodSignature *methodSig = [messageTarget methodSignatureForSelector:methodSelector];
        if( methodSig != nil )
        {//good news - object has this method implemented
            
            //const char *returnType = [methodSig methodReturnType];
            //NSLog(@"methodReturnType=%s\n", returnType);

            NSInvocation *messageInvocation = [NSInvocation invocationWithMethodSignature:methodSig];
            if(messageInvocation != NULL)
            {
                BOOL okToAddArgument = YES;
                [messageInvocation setTarget:messageTarget];
                [messageInvocation setSelector:methodSelector];
                char stackBuff[128];//128 bytes should be enough for most structures
                NSUInteger argCount = [methodSig numberOfArguments] - 2;//count only real arguments, skip self and selector
                for(NSUInteger argIndex = 0; argIndex < argCount; argIndex++)
                {
                    const char *argTypeStr = [methodSig getArgumentTypeAtIndex:2+argIndex];
    #if DEBUG
                    NSLog(@"argument %d type=%s\n", (int)argIndex+1, argTypeStr);
    #endif
                    //set argument
                    if( (argIndex*2 + 1) < elementCount )
                    {
                        CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(oneObjCMessage, argIndex*2 + 1);
                        CFStringRef argString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
                        if(argString != NULL)
                        {
                            ObjCSelectorArgumentType argType = FindArgumentType(argTypeStr);
                            okToAddArgument = YES;
                            
                            switch(argType)
                            {
                                case kObjCArgCharType:
                                {//this is also BOOL that's why we check for YES/NO true/false
                                    char charVal = 0;
                                    if( (kCFCompareEqualTo == ::CFStringCompare( CFSTR("YES"), argString, kCFCompareCaseInsensitive)) ||
                                       (kCFCompareEqualTo == ::CFStringCompare( CFSTR("true"), argString, kCFCompareCaseInsensitive)) )
                                    {
                                        charVal = 1;
                                    }
                                    else if( (kCFCompareEqualTo == ::CFStringCompare( CFSTR("NO"), argString, kCFCompareCaseInsensitive)) ||
                                            (kCFCompareEqualTo == ::CFStringCompare( CFSTR("false"), argString, kCFCompareCaseInsensitive)) )
                                    {
                                        charVal = 0;
                                    }
                                    else
                                    {
                                        charVal = (char)CFStringGetIntValue(argString);
                                    }
                                    
                                    *(char *)stackBuff = charVal;
                                }
                                break;
                                
                                case kObjCArgUCharType:
                                {
                                    *(unsigned char *)stackBuff = (unsigned char)CFStringGetIntValue(argString);
                                }
                                break;
                                
                                case kObjCArgShortType:
                                {
                                    *(short *)stackBuff = (short)CFStringGetIntValue(argString);
                                }
                                break;
                                    
                                case kObjCArgUShortType:
                                {
                                    *(unsigned short *)stackBuff = (unsigned short)CFStringGetIntValue(argString);
                                }
                                break;

                                case kObjCArgIntType:
                                {
                                    *(int *)stackBuff = (int)CFStringGetIntValue(argString);
                                }

                                case kObjCArgLongType:
                                {
                                    *(long *)stackBuff = (long)CFStringGetIntValue(argString);
                                }
                                break;
                                    
                                case kObjCArgULongType:
                                case kObjCArgUIntType:
                                case kObjCArgLonglongType:
                                case kObjCArgULonglongType:
                                {
                                    if(currentLocale == NULL)
                                        currentLocale = CFLocaleCopyCurrent();
                                    
                                    if(numberFormatter == NULL)
                                        numberFormatter = CFNumberFormatterCreate(kCFAllocatorDefault, currentLocale, kCFNumberFormatterDecimalStyle);

                                    long long longlongVal = 0;
                                    okToAddArgument = CFNumberFormatterGetValueFromString(numberFormatter, argString, NULL, kCFNumberLongLongType, &longlongVal);
                                    if(okToAddArgument)
                                    {
                                        if(argType == kObjCArgULongType)
                                        {
                                            *(unsigned long *)stackBuff = (unsigned long)longlongVal;
                                        }
                                        else if(argType == kObjCArgUIntType)
                                        {
                                            *(unsigned int *)stackBuff = (unsigned int)longlongVal;
                                        }
                                        else if(argType == kObjCArgLonglongType)
                                        {
                                            *(long long *)stackBuff = longlongVal;
                                        }
                                        else if(argType == kObjCArgULonglongType)
                                        {
                                            *(unsigned long long *)stackBuff = (unsigned long long)longlongVal;
                                        }
                                    }
                                }
                                break;
                                
                                case kObjCArgFloatType:
                                {
                                    *(float *)stackBuff = (float)CFStringGetDoubleValue(argString);
                                }
                                break;
                                    
                                case kObjCArgDoubleType:
                                {
                                    *(double *)stackBuff = (double)CFStringGetDoubleValue(argString);
                                }
                                break;
                                
                                case kObjCArgBoolType:
                                {
                                    BOOL boolVal = NO;
                                    if( (kCFCompareEqualTo == ::CFStringCompare( CFSTR("YES"), argString, kCFCompareCaseInsensitive)) ||
                                        (kCFCompareEqualTo == ::CFStringCompare( CFSTR("true"), argString, kCFCompareCaseInsensitive)) )
                                    {
                                        boolVal = YES;
                                    }
                                    else if( (kCFCompareEqualTo == ::CFStringCompare( CFSTR("NO"), argString, kCFCompareCaseInsensitive)) ||
                                            (kCFCompareEqualTo == ::CFStringCompare( CFSTR("false"), argString, kCFCompareCaseInsensitive)) )
                                    {
                                        boolVal = NO;
                                    }
                                    else
                                    {
                                        SInt32 intVal = CFStringGetIntValue(argString);
                                        boolVal = (BOOL)intVal;
                                    }
                                    *(BOOL *)stackBuff = boolVal;
                                }
                                break;

                                case kObjCArgObjectType:
                                {//only NSString */CFStringRef supported as id/NSObject *
                                    if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("omc_nil"), argString, kCFCompareCaseInsensitive) )
                                    {
                                        *(CFTypeRef *)stackBuff = nil;
                                    }
                                    else
                                    {
                                        *(CFStringRef *)stackBuff = argString;
                                    }
                                }
                                break;
                                    
                                case kObjCArgStructType:
                                {
                                    memset(stackBuff, 0, sizeof(stackBuff));
                                    
                                    CFArrayRef numberArray = CFStringCreateArrayBySeparatingStrings( kCFAllocatorDefault, argString, CFSTR(",") );
                                    CFIndex numberCount = 0;
                                    if(numberArray != NULL)
                                        numberCount = CFArrayGetCount(numberArray);
                                    //first char is '{', next follows the structure name
                                    if(numberCount >= 2)
                                    {//all structures here require at least 2 numbers
                                        if( 0 == strncmp("_NSRange", argTypeStr+1, sizeof("_NSRange")-1) )
                                        {
                                            NSRange *theRange = (NSRange *)stackBuff;
                                            
                                            CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 0);
                                            CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
                                            if(numString != NULL)
                                                theRange->location = ::CFStringGetIntValue(numString);
                                            else
                                                okToAddArgument = NO;
                                            
                                            oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 1);
                                            numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
                                            if(numString != NULL)
                                                theRange->length =  ::CFStringGetIntValue(numString);
                                            else
                                                okToAddArgument = NO;
                                        }
                                        else if( 0 == strncmp("_NSPoint", argTypeStr+1, sizeof("_NSPoint")-1) )
                                        {
                                            NSPoint *thePoint = (NSPoint *)stackBuff;
                                            
                                            CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 0);
                                            CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
                                            if(numString != NULL)
                                                thePoint->x = (CGFloat)::CFStringGetDoubleValue(numString);
                                            else
                                                okToAddArgument = NO;
                                            
                                            oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 1);
                                            numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
                                            if(numString != NULL)
                                                thePoint->y =  (CGFloat)::CFStringGetDoubleValue(numString);
                                            else
                                                okToAddArgument = NO;
                                        }
                                        else if( 0 == strncmp("_NSSize", argTypeStr+1, sizeof("_NSSize")-1) )
                                        {
                                            NSSize *theSize = (NSSize *)stackBuff;

                                            CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 0);
                                            CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
                                            if(numString != NULL)
                                                theSize->width = (CGFloat)::CFStringGetDoubleValue(numString);
                                            else
                                                okToAddArgument = NO;
                                            
                                            oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 1);
                                            numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
                                            if(numString != NULL)
                                                theSize->height =  (CGFloat)::CFStringGetDoubleValue(numString);
                                            else
                                                okToAddArgument = NO;
                                        }
                                        else if( (numberCount >= 4) && (0 == strncmp("_NSRect", argTypeStr+1, sizeof("_NSRect")-1)) )
                                        {
                                            NSRect *theRect = (NSRect *)stackBuff;

                                            CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 0);
                                            CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
                                            if(numString != NULL)
                                                theRect->origin.x = (CGFloat)::CFStringGetDoubleValue(numString);
                                            else
                                                okToAddArgument = NO;
                                            
                                            oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 1);
                                            numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
                                            if(numString != NULL)
                                                theRect->origin.y =  (CGFloat)::CFStringGetDoubleValue(numString);
                                            else
                                                okToAddArgument = NO;

                                            oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 0);
                                            numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
                                            if(numString != NULL)
                                                theRect->size.width = (CGFloat)::CFStringGetDoubleValue(numString);
                                            else
                                                okToAddArgument = NO;
                                            
                                            oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 1);
                                            numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
                                            if(theRect != NULL)
                                                theRect->size.height =  (CGFloat)::CFStringGetDoubleValue(numString);
                                            else
                                                okToAddArgument = NO;
                                        }
                                        else
                                        {
                                            okToAddArgument = NO;
                                            NSLog(@"OMCNibWindowController sendObjCMessage: this structure type unsuppported for argument %d for \"%@\" selector", (int)argIndex+1, methodName);
                                        }
                                    }
                                    else
                                    {
                                        okToAddArgument = NO;
                                        NSLog(@"OMCNibWindowController sendObjCMessage: invalid count of members for structure argument %d for \"%@\" selector", (int)argIndex+1, methodName);
                                    }
                                    
                                }
                                break;
                                    
                                case kObjCArgPointerType:
                                case kObjCArgStringType:
                                case kObjCArgArrayType:
                                case kObjCArgUnionType:
                                case kObjCArgBitfield:
                                {
                                    if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("omc_nil"), argString, kCFCompareCaseInsensitive) )
                                    {
                                        *(CFTypeRef *)stackBuff = nil;
                                    }
                                    else
                                    {
                                        okToAddArgument = NO;
                                        NSLog(@"OMCNibWindowController sendObjCMessage: unsupported argument type for argument %d for \"%@\" selector", (int)argIndex+1, methodName);
                                    }
                                }
                                break;
                                
                                case kObjCArgNoType:
                                case kObjCArgVoidType:
                                case kObjCArgSelectorType:
                                default:
                                {
                                    okToAddArgument = NO;
                                    NSLog(@"OMCNibWindowController sendObjCMessage: invalid argument %d for \"%@\" selector", (int)argIndex+1, methodName);
                                }
                                break;
                            }
                            
                            if(okToAddArgument)
                            {
                                [messageInvocation setArgument:(void *)stackBuff atIndex:2+argIndex];
                            }
                            else
                            {
                                break;//we will not be able to process this comamnd
                            }
                        }
                    }
                    else
                    {
                        NSLog(@"OMCNibWindowController sendObjCMessage: argument count mismatch for \"%@\" selector", methodName);
                    }
                }
                
                if(okToAddArgument)
                    [messageInvocation invoke];
            }
        }
        else
        {
            NSLog(@"OMCNibWindowController sendObjCMessage: target object does not respond to \"%@\" selector", methodName);
        }
    }
    @catch (NSException *localException)
    {
        NSLog(@"OMCNibWindowController sendObjCMessage received exception while trying to invoke a custom message: %@", localException);
    }
    
    if( currentLocale != NULL )
       CFRelease(currentLocale);

    if( numberFormatter != NULL )
       CFRelease(numberFormatter);
}


#pragma mark - Abstract methods (no-op defaults)

- (void)setControlStringValue:(NSString *)inValue forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setControlStringValue:forControlID: %@", inControlID);
}
- (void)setControlEnabled:(BOOL)enabled forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setControlEnabled:%d forControlID: %@", enabled, inControlID);
}
- (void)setControlVisible:(BOOL)visible forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setControlVisible:%d forControlID: %@", visible, inControlID);
}

- (void)removeAllListItemsForControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] removeAllListItemsForControlID: %@", inControlID);
}
- (void)setListItems:(CFArrayRef)items forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setListItems:forControlID: %@", inControlID);
}
- (void)appendListItems:(CFArrayRef)items forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] appendListItems:forControlID: %@", inControlID);
}

- (void)emptyTableForControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] emptyTableForControlID: %@", inControlID);
}
- (void)removeTableRowsForControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] removeTableRowsForControlID: %@", inControlID);
}
- (void)setTableRows:(CFArrayRef)rows forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setTableRows:forControlID: %@", inControlID);
}
- (void)addTableRows:(CFArrayRef)rows forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] addTableRows:forControlID: %@", inControlID);
}
- (void)setTableColumns:(CFArrayRef)columns forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setTableColumns:forControlID: %@", inControlID);
}
- (void)setTableColumnWidths:(CFArrayRef)widths forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setTableColumnWidths:forControlID: %@", inControlID);
}

- (void)selectControlWithID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] selectControlWithID: %@", inControlID);
}
- (void)setCommandID:(NSString *)commandID forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setCommandID:%@ forControlID: %@", commandID, inControlID);
}
- (void)moveControlWithID:(NSString *)inControlID toPosition:(NSPoint)position {
    NSLog(@"[OMCWindowController stub] moveControlWithID: %@", inControlID);
}
- (void)resizeControlWithID:(NSString *)inControlID toSize:(NSSize)size {
    NSLog(@"[OMCWindowController stub] resizeControlWithID: %@", inControlID);
}
- (void)scrollControlWithID:(NSString *)inControlID toPosition:(NSPoint)position {
    NSLog(@"[OMCWindowController stub] scrollControlWithID: %@", inControlID);
}

- (void)invokeMessagesForControlID:(NSString *)inControlID messages:(CFArrayRef)messages {
    NSLog(@"[OMCWindowController stub] invokeMessagesForControlID: %@", inControlID);
}
- (void)setPropertyKey:(NSString *)propertyKey jsonValue:(NSString *)jsonValue forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setPropertyKey:%@ jsonValue:%@ forControlID: %@", propertyKey, jsonValue, inControlID);
}

@end

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
#include "OMCInvoke.h"
#include "OMCObjCInvoke.h"
#include <string>
#include <vector>

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

+ (instancetype)findControllerForKeyWindow
{
    NSWindow *keyWindow = [NSApp keyWindow];
    if(keyWindow == nil)
        return nil;

    for(OMCWindowController *controller in GetAllDialogControllers())
    {
        if(controller.window == keyWindow)
            return controller;
    }
    return nil;
}

- (id)initWithOmc:(OnMyCommand *)inOmc commandRuntimeData:(CommandRuntimeData *)inCommandRuntimeData
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
    self.currentCommandID = inCommandID;
    
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
	if(self.currentCommandID != nil)
	{
		if(self.endOKSubcommandID != nil)
        {
            return [self.currentCommandID isEqualToString:self.endOKSubcommandID];
        }

		return [self.currentCommandID isEqualToString:@"omc.dialog.ok"];
	}
	return false;
}

- (BOOL)isCanceled
{
	if(self.currentCommandID != nil)
	{
		if(self.endCancelSubcommandID != nil)
        {
            return [self.currentCommandID isEqualToString:self.endCancelSubcommandID];
        }

		return [self.currentCommandID isEqualToString:@"omc.dialog.cancel"];
	}
	return false;
}

- (BOOL)commandShouldCloseDialog
{
	return ([self isOkeyed] || [self isCanceled]);
}

- (BOOL)initializeDialog
{
	NSString *origCommand = self.currentCommandID;

	self.currentCommandID = @"omc.dialog.initialize";
	if(self.dialogInitSubcommandID != nil)
    {
        self.currentCommandID = self.dialogInitSubcommandID;
    }
    
	mOMCDialogProxy->StartListening();

    [self processCommandWithContext:NULL];

	self.currentCommandID = origCommand;

	if(mPlugin->GetError() != noErr)
		return NO;

	return YES;
}

- (BOOL)terminate
{
	BOOL wasOkeyed = [self isOkeyed];
	NSString *origCommand = self.currentCommandID;
	
	self.currentCommandID = wasOkeyed ? @"omc.dialog.terminate.ok" : @"omc.dialog.terminate.cancel";

	if( wasOkeyed && (self.endOKSubcommandID != nil) )
    {
        self.currentCommandID = self.endOKSubcommandID;
    }
	else if( !wasOkeyed && (self.endCancelSubcommandID != nil) )
    {
        self.currentCommandID = self.endCancelSubcommandID;
    }
    
	[self processCommandWithContext:NULL];

    self.currentCommandID = origCommand;

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

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    if(self.windowDidActivateSubcommandID != nil)
    {
        NSString *origCommand = self.currentCommandID;
        self.currentCommandID = self.windowDidActivateSubcommandID;
        [self processCommandWithContext:NULL];
        self.currentCommandID = origCommand;
    }
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    if(self.windowDidDeactivateSubcommandID != nil)
    {
        NSString *origCommand = self.currentCommandID;
        self.currentCommandID = self.windowDidDeactivateSubcommandID;
        [self processCommandWithContext:NULL];
        self.currentCommandID = origCommand;
    }
}

- (OSStatus)processCommandWithContext:(CFTypeRef)inContext
{
	if(mPlugin == nullptr)
    {
        return paramErr;
    }
    
	SInt32 cmdIndex = -1;
    if(OMCDialog::IsPredefinedDialogCommandID((__bridge CFStringRef)self.currentCommandID))
    {
        cmdIndex = mPlugin->FindSubcommandIndex(mCommandName, (__bridge CFStringRef)self.currentCommandID);
    }
	else
    {
        cmdIndex = mPlugin->FindCommandIndex(mCommandName, (__bridge CFStringRef)self.currentCommandID);
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

- (void)setControlContextViewID:(NSInteger)viewID viewPartID:(NSInteger)viewPartID contextString:(NSString *)contextString
{
    if(mCommandRuntimeData == nullptr)
        return;
    mCommandRuntimeData->controlContextViewID     = static_cast<CFIndex>(viewID);
    mCommandRuntimeData->controlContextViewPartID = static_cast<CFIndex>(viewPartID);
    if(contextString != nil)
        mCommandRuntimeData->controlContextJSON.Adopt((__bridge CFStringRef)contextString, kCFObjRetain);
    else
        mCommandRuntimeData->controlContextJSON = nullptr;
}

- (void)clearControlContext
{
    if(mCommandRuntimeData == nullptr)
        return;
    mCommandRuntimeData->controlContextViewID     = -1;
    mCommandRuntimeData->controlContextViewPartID = -1;
    mCommandRuntimeData->controlContextJSON       = nullptr;
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

	// Row selection is applied after the row-setting blocks above so that a single message
	// that both sets rows and selects a row populates the content first.
	CFDictionaryRef selectRowDict;
	if( controlValues.GetValue(CFSTR("SELECT_ROW"), selectRowDict) )
	{
		itemCount = ::CFDictionaryGetCount(selectRowDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(selectRowDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFStringRef indexStr = ACFType<CFStringRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (indexStr != NULL) )
					[self selectRow:[(__bridge NSString *)indexStr integerValue] forControlID:(__bridge NSString *)controlID];
			}
		}
	}

	CFDictionaryRef selectRowContentDict;
	if( controlValues.GetValue(CFSTR("SELECT_ROW_CONTENT"), selectRowContentDict) )
	{
		itemCount = ::CFDictionaryGetCount(selectRowContentDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(selectRowContentDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) && (::CFArrayGetCount(theArr) >= 1) )
				{
					CFStringRef text = ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 0) );
					NSInteger columnNumber = 0; // 0 = match any column
					if( ::CFArrayGetCount(theArr) >= 2 )
					{
						CFStringRef colStr = ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 1) );
						if( colStr != NULL )
							columnNumber = [(__bridge NSString *)colStr integerValue];
					}
					if( text != NULL )
						[self selectRowWithContent:(__bridge NSString *)text column:columnNumber forControlID:(__bridge NSString *)controlID];
				}
			}
		}
	}

	CFDictionaryRef deselectRowDict;
	if( controlValues.GetValue(CFSTR("DESELECT_ROW"), deselectRowDict) )
	{
		itemCount = ::CFDictionaryGetCount(deselectRowDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			::CFDictionaryGetKeysAndValues(deselectRowDict, (const void **)keyList.data(), NULL);
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if( controlID != NULL )
					[self deselectRowForControlID:(__bridge NSString *)controlID];
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

	CFDictionaryRef setStateDict;
	if( controlValues.GetValue(CFSTR("SET_STATE"), setStateDict) )
	{
		itemCount = ::CFDictionaryGetCount(setStateDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(setStateDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) && (::CFArrayGetCount(theArr) >= 2) )
				{
					CFStringRef stateKey = ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 0) );
					CFStringRef stateVal = ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 1) );
					if( (stateKey != NULL) && (stateVal != NULL) )
						[self setStateKey:(__bridge NSString *)stateKey stringOrJsonValue:(__bridge NSString *)stateVal forControlID:(__bridge NSString *)controlID];
				}
			}
		}
	}

	// Modal presentation (ActionUI only; Nib controller stubs log and return)
	{
	CFDictionaryRef presentModalDict = NULL;
	if( controlValues.GetValue(CFSTR("PRESENT_MODAL"), presentModalDict) )
	{
		CFArrayRef theArr = (CFArrayRef)::CFDictionaryGetValue(presentModalDict, CFSTR("omc_window"));
		if( theArr != NULL && ::CFArrayGetCount(theArr) >= 1 )
		{
			NSString *resourceNameOrPath = (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 0) );
			NSString *dismissActionID = (::CFArrayGetCount(theArr) >= 2) ? (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 1) ) : nil;
			if( resourceNameOrPath != nil )
				[self presentModalWithResourceNameOrPath:resourceNameOrPath onDismissActionID:dismissActionID];
		}
	}
	}

	{
	CFDictionaryRef dismissModalDict = NULL;
	if( controlValues.GetValue(CFSTR("DISMISS_MODAL"), dismissModalDict) )
	{
		if( dismissModalDict != NULL && ::CFDictionaryGetValue(dismissModalDict, CFSTR("omc_window")) != NULL )
			[self dismissModal];
	}
	}

	// Toast (ActionUI only)
	{
	CFDictionaryRef presentToastDict = NULL;
	if( controlValues.GetValue(CFSTR("PRESENT_TOAST"), presentToastDict) )
	{
		CFArrayRef theArr = (CFArrayRef)::CFDictionaryGetValue(presentToastDict, CFSTR("omc_window"));
		if( theArr != NULL && ::CFArrayGetCount(theArr) >= 1 )
		{
			CFIndex n = ::CFArrayGetCount(theArr);
			NSString *message = (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 0) );
			NSString *durationStr = (n >= 2) ? (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 1) ) : nil;
			NSString *actionTitle = (n >= 3) ? (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 2) ) : nil;
			NSString *actionID = (n >= 4) ? (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 3) ) : nil;
			if( message != nil )
				[self presentToastWithMessage:message duration:(durationStr != nil ? [durationStr doubleValue] : 0.0) actionTitle:actionTitle actionID:actionID];
		}
	}
	}

	{
	CFDictionaryRef dismissToastDict = NULL;
	if( controlValues.GetValue(CFSTR("DISMISS_TOAST"), dismissToastDict) )
	{
		if( dismissToastDict != NULL && ::CFDictionaryGetValue(dismissToastDict, CFSTR("omc_window")) != NULL )
			[self dismissToast];
	}
	}

	{
	CFDictionaryRef presentAlertDict = NULL;
	if( controlValues.GetValue(CFSTR("PRESENT_ALERT"), presentAlertDict) )
	{
		CFArrayRef theArr = (CFArrayRef)::CFDictionaryGetValue(presentAlertDict, CFSTR("omc_window"));
		if( theArr != NULL && ::CFArrayGetCount(theArr) >= 1 )
		{
			NSString *title = (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 0) );
			NSString *message = (::CFArrayGetCount(theArr) >= 2) ? (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 1) ) : nil;
			NSMutableArray *buttonSpecs = [NSMutableArray array];
			for( CFIndex i = 2; i < ::CFArrayGetCount(theArr); i++ )
			{
				NSString *spec = (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, i) );
				if( spec != nil )
					[buttonSpecs addObject:spec];
			}
			if( title != nil )
				[self presentAlertWithTitle:title message:message buttonSpecs:buttonSpecs];
		}
	}
	}

	{
	CFDictionaryRef presentConfirmDict = NULL;
	if( controlValues.GetValue(CFSTR("PRESENT_CONFIRMATION_DIALOG"), presentConfirmDict) )
	{
		CFArrayRef theArr = (CFArrayRef)::CFDictionaryGetValue(presentConfirmDict, CFSTR("omc_window"));
		if( theArr != NULL && ::CFArrayGetCount(theArr) >= 1 )
		{
			NSString *title = (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 0) );
			NSString *message = (::CFArrayGetCount(theArr) >= 2) ? (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 1) ) : nil;
			NSMutableArray *buttonSpecs = [NSMutableArray array];
			for( CFIndex i = 2; i < ::CFArrayGetCount(theArr); i++ )
			{
				NSString *spec = (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, i) );
				if( spec != nil )
					[buttonSpecs addObject:spec];
			}
			if( title != nil )
				[self presentConfirmationDialogWithTitle:title message:message buttonSpecs:buttonSpecs];
		}
	}
	}

	{
	CFDictionaryRef dismissDialogDict = NULL;
	if( controlValues.GetValue(CFSTR("DISMISS_DIALOG"), dismissDialogDict) )
	{
		if( dismissDialogDict != NULL && ::CFDictionaryGetValue(dismissDialogDict, CFSTR("omc_window")) != NULL )
			[self dismissDialog];
	}
	}

	// Runtime structural mutations (ActionUI only; Nib controller stubs log and return)
	{
	CFDictionaryRef insertElementDict = NULL;
	if( controlValues.GetValue(CFSTR("INSERT_ELEMENT"), insertElementDict) )
	{
		itemCount = ::CFDictionaryGetCount(insertElementDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(insertElementDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( controlID != NULL && theArr != NULL && ::CFArrayGetCount(theArr) >= 1 )
				{
					NSString *json = (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 0) );
					NSString *container = (::CFArrayGetCount(theArr) >= 2) ? (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 1) ) : nil;
					NSString *positionStr = (::CFArrayGetCount(theArr) >= 3) ? (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 2) ) : nil;
					NSInteger parentID = [(__bridge NSString *)controlID integerValue];
					if( json != nil )
						[self insertElementWithParentID:parentID json:json container:container positionString:positionStr];
				}
			}
		}
	}
	}

	{
	CFDictionaryRef insertRowDict = NULL;
	if( controlValues.GetValue(CFSTR("INSERT_ELEMENT_ROW"), insertRowDict) )
	{
		itemCount = ::CFDictionaryGetCount(insertRowDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(insertRowDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( controlID != NULL && theArr != NULL && ::CFArrayGetCount(theArr) >= 1 )
				{
					NSString *json = (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 0) );
					NSString *container = (::CFArrayGetCount(theArr) >= 2) ? (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 1) ) : nil;
					NSString *positionStr = (::CFArrayGetCount(theArr) >= 3) ? (__bridge NSString *)ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, 2) ) : nil;
					NSInteger parentID = [(__bridge NSString *)controlID integerValue];
					if( json != nil )
						[self insertElementRowWithParentID:parentID json:json container:container positionString:positionStr];
				}
			}
		}
	}
	}

	{
	CFDictionaryRef removeElementDict = NULL;
	if( controlValues.GetValue(CFSTR("REMOVE_ELEMENT"), removeElementDict) )
	{
		itemCount = ::CFDictionaryGetCount(removeElementDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(removeElementDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if( controlID != NULL )
				{
					NSInteger viewID = [(__bridge NSString *)controlID integerValue];
					[self removeElementWithViewID:viewID];
				}
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
			CFDictionaryRef contentTypesDict = NULL;
			controlValues.GetValue(CFSTR("VALUE_CONTENT_TYPES"), contentTypesDict);

			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			::CFDictionaryGetKeysAndValues(valuesDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if(controlID != NULL)
				{
					if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_window"), 0) )
					{
						CFStringRef titleStr = ACFType<CFStringRef>::DynamicCast( valueList[i] );
						if(titleStr != NULL)
							[self.window setTitle:(__bridge NSString *)titleStr];
					}
					else
					{
						NSString *contentType = nil;
						if(contentTypesDict != NULL)
						{
							CFStringRef ct = ACFType<CFStringRef>::DynamicCast(
								::CFDictionaryGetValue(contentTypesDict, controlID));
							if(ct != NULL)
								contentType = (__bridge NSString *)ct;
						}
						[self setControlStringValue:(__bridge NSString *)ACFType<CFStringRef>::DynamicCast( valueList[i] )
										forControlID:(__bridge NSString *)controlID
										contentType:contentType];
					}
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

						self.currentCommandID = commandID;
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
							[self setWindowContentSize:newSize];
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
					if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_window"), 0) )
						OMCInvokeMessages(OMCInvokeTarget::window, (__bridge void *)self.window, theArr);
					else if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_application"), 0) )
						OMCInvokeMessages(OMCInvokeTarget::application, nullptr, theArr);
					else if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_workspace"), 0) )
						OMCInvokeMessages(OMCInvokeTarget::workspace, nullptr, theArr);
					else
						[self invokeMessagesForControlID:(__bridge NSString *)controlID messages:theArr];
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

// The size a script asks for is the area the dialog's content lays out in. Subclasses whose
// content view is larger than that (a full-size content view spans the titlebar) convert here.
- (void)setWindowContentSize:(NSSize)inContentSize
{
	[self.window setContentSize:inContentSize];
}


- (void)invokeMessages:(CFArrayRef)messages onTarget:(id)target
{
    OMCSendObjCMessages(target, messages);
}


#pragma mark - Abstract methods (no-op defaults)

- (void)setControlStringValue:(NSString *)inValue forControlID:(NSString *)inControlID contentType:(NSString *)contentType {
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

- (void)selectRow:(NSInteger)rowIndex forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] selectRow:%ld forControlID: %@", (long)rowIndex, inControlID);
}
- (void)selectRowWithContent:(NSString *)text column:(NSInteger)columnNumber forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] selectRowWithContent:%@ column:%ld forControlID: %@", text, (long)columnNumber, inControlID);
}
- (void)deselectRowForControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] deselectRowForControlID: %@", inControlID);
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
- (void)setStateKey:(NSString *)stateKey stringOrJsonValue:(NSString *)value forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setStateKey:%@ value:%@ forControlID: %@", stateKey, value, inControlID);
}

- (void)presentModalWithResourceNameOrPath:(NSString *)resourceNameOrPath onDismissActionID:(NSString *)onDismissActionID {
    NSLog(@"[OMCWindowController stub] presentModalWithResourceNameOrPath: %@ — not supported by this window controller", resourceNameOrPath);
}
- (void)dismissModal {
    NSLog(@"[OMCWindowController stub] dismissModal — not supported by this window controller");
}
- (void)presentToastWithMessage:(NSString *)message duration:(NSTimeInterval)duration actionTitle:(NSString *)actionTitle actionID:(NSString *)actionID {
    NSLog(@"[OMCWindowController stub] presentToastWithMessage: %@ — not supported by this window controller", message);
}
- (void)dismissToast {
    NSLog(@"[OMCWindowController stub] dismissToast — not supported by this window controller");
}
- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message buttonSpecs:(NSArray *)buttonSpecs {
    NSLog(@"[OMCWindowController stub] presentAlertWithTitle: %@ — not supported by this window controller", title);
}
- (void)presentConfirmationDialogWithTitle:(NSString *)title message:(NSString *)message buttonSpecs:(NSArray *)buttonSpecs {
    NSLog(@"[OMCWindowController stub] presentConfirmationDialogWithTitle: %@ — not supported by this window controller", title);
}
- (void)dismissDialog {
    NSLog(@"[OMCWindowController stub] dismissDialog — not supported by this window controller");
}
- (void)insertElementWithParentID:(NSInteger)parentID json:(NSString *)json container:(NSString *)container positionString:(NSString *)positionStr {
    NSLog(@"[OMCWindowController stub] insertElementWithParentID:%ld — not supported by this window controller", (long)parentID);
}
- (void)insertElementRowWithParentID:(NSInteger)parentID json:(NSString *)json container:(NSString *)container positionString:(NSString *)positionStr {
    NSLog(@"[OMCWindowController stub] insertElementRowWithParentID:%ld — not supported by this window controller", (long)parentID);
}
- (void)removeElementWithViewID:(NSInteger)viewID {
    NSLog(@"[OMCWindowController stub] removeElementWithViewID:%ld — not supported by this window controller", (long)viewID);
}

@end

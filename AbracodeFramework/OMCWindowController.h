//
//  OMCWindowController.h
//  Abracode
//
//  Created by Tomasz Kukielka on 1/20/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "OMCControlAccessor.h"
#include "CFObj.h"
#include "ACFDict.h"
#include "ARefCounted.h"
#include "AUniquePtr.h"
#include "SelectionIterator.h"

class OnMyCommandCM;
class OMCDialog;
class CommandRuntimeData;

@interface OMCWindowController : NSObject
{
	// we compile ObjC with the flag to invoke C++ constructors and destructor
	// so we can use smart pointers as member variables

	ARefCountedObj<OnMyCommandCM>	mPlugin;
	ARefCountedObj<OMCDialog>		mOMCDialogProxy;
    ARefCountedObj<CommandRuntimeData> mCommandRuntimeData;
	CFObj<CFBundleRef>				mExternBundleRef;
	CFObj<CFArrayRef>				mCommandName;
	Boolean							mIsModal;
	Boolean							mIsRunning;
}

@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSString *dialogInitSubcommandID;
@property (nonatomic, strong) NSString *endOKSubcommandID;
@property (nonatomic, strong) NSString *endCancelSubcommandID;
@property (nonatomic, strong) NSString *lastCommandID;
@property (nonatomic, strong) NSMutableSet *dialogOwnedItems;

+ (instancetype)findControllerByUUID:(NSString *)uuid;

- (id)initWithOmc:(OnMyCommandCM *)inOmc commandRuntimeData:(CommandRuntimeData *)inCommandRuntimeData;
- (OMCDialog *)getOMCDialog;
- (Boolean)isModal;
- (void)run;
- (BOOL)isOkeyed;
- (BOOL)isCanceled;
- (BOOL)commandShouldCloseDialog;
- (BOOL)initializeDialog;
- (BOOL)terminate;
- (void)dispatchCommand:(NSString *)inCommandID withContext:(CFTypeRef)inContext;
- (OSStatus)processCommandWithContext:(CFTypeRef)inContext;
- (SelectionIterator *)createSelectionIterator:(CFDictionaryRef)inIteratorParams;
- (void)keepItem:(id)inItem;
- (void)windowWillClose:(NSNotification *)notification;

// Shared implementation - parses control dictionary and dispatches to abstract methods
- (void)setControlValues:(CFDictionaryRef)inControlDict;
- (void)setWindowTopLeftPosition:(NSPoint)absolutePosition;

- (void)invokeMessages:(CFArrayRef)messages onTarget:(id)target;
- (void)sendObjCMessage:(CFArrayRef)oneObjCMessage toTarget:(id)messageTarget;

// Abstract methods - no-op defaults, subclasses override for specific UI frameworks
- (void)setControlStringValue:(NSString *)inValue forControlID:(NSString *)inControlID;
- (void)setControlEnabled:(BOOL)enabled forControlID:(NSString *)inControlID;
- (void)setControlVisible:(BOOL)visible forControlID:(NSString *)inControlID;

- (void)removeAllListItemsForControlID:(NSString *)inControlID;
- (void)setListItems:(CFArrayRef)items forControlID:(NSString *)inControlID;
- (void)appendListItems:(CFArrayRef)items forControlID:(NSString *)inControlID;

- (void)emptyTableForControlID:(NSString *)inControlID;
- (void)removeTableRowsForControlID:(NSString *)inControlID;
- (void)setTableRows:(CFArrayRef)rows forControlID:(NSString *)inControlID;
- (void)addTableRows:(CFArrayRef)rows forControlID:(NSString *)inControlID;
- (void)setTableColumns:(CFArrayRef)columns forControlID:(NSString *)inControlID;
- (void)setTableColumnWidths:(CFArrayRef)widths forControlID:(NSString *)inControlID;

- (void)selectControlWithID:(NSString *)inControlID;
- (void)setCommandID:(NSString *)commandID forControlID:(NSString *)inControlID;
- (void)moveControlWithID:(NSString *)inControlID toPosition:(NSPoint)position;
- (void)resizeControlWithID:(NSString *)inControlID toSize:(NSSize)size;
- (void)scrollControlWithID:(NSString *)inControlID toPosition:(NSPoint)position;

- (void)invokeMessagesForControlID:(NSString *)inControlID messages:(CFArrayRef)messages;

@end

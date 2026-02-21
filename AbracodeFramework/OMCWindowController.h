//
//  OMCWindowController.h
//  Abracode
//
//  Created by Tomasz Kukielka on 1/20/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "OMCControlAccessor.h"
#import "OMCWindowControlProtocol.h"
#include "CFObj.h"
#include "ACFDict.h"
#include "ARefCounted.h"
#include "AUniquePtr.h"
#include "SelectionIterator.h"

class OnMyCommandCM;
class OMCDialog;
class CommandRuntimeData;

@interface OMCWindowController : NSObject <OMCWindowControlProtocol>
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

// OMCWindowControlProtocol — no-op defaults provided here; subclasses override for their UI framework.

@end

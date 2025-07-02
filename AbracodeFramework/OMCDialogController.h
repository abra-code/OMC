//
//  OMCDialogController.h
//  Abracode
//
//  Created by Tomasz Kukielka on 1/20/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "OMCCocoaNib.h"
#include "CFObj.h"
#include "ARefCounted.h"
#include "AUniquePtr.h"
#include "SelectionIterator.h"

class OnMyCommandCM;
class OMCCocoaDialog;

@interface OMCDialogController : NSObject <NSWindowDelegate>
{
	//we compile ObjC with the flag to invoke C++ constructors and destructor
	//so we can use smart pointers as member variables

	ARefCountedObj<OnMyCommandCM>	mPlugin;
	ARefCountedObj<OMCCocoaDialog>	mOMCDialogProxy;
	CFObj<CFBundleRef>				mExternBundleRef;
	CFObj<CFArrayRef>				mCommandName;
	CFObj<CFStringRef>				mDialogUniqueID;
	Boolean							mIsModal;
	Boolean							mIsRunning;
}

@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSString *dialogInitSubcommandID;
@property (nonatomic, strong) NSString *endOKSubcommandID;
@property (nonatomic, strong) NSString *endCancelSubcommandID;
@property (nonatomic, strong) NSString *lastCommandID;
@property (nonatomic, strong) OMCCocoaNib *omcCocoaNib;
@property (nonatomic, strong) NSMutableSet *dialogOwnedItems;

- (id)initWithOmc:(OnMyCommandCM *)inOmc;
- (Boolean)findNib:(NSString *)inNibName forBundlePath:(NSString *)inPath;
- (void)initSubview:(NSView *)inView;
- (void)resetSubview:(NSView *)inView;
- (id)findViewInParent:(NSView *)inParentView forControlID:(NSString *)inControlID;//may return NSView or NSCell
- (id)findControlOrViewWithID:(NSString *)inControlID;//may return NSView or NSCell
- (void)allControlValues:(NSMutableDictionary *)ioControlValues andProperties:(NSMutableDictionary *)ioCustomProperties withIterator:(SelectionIterator *)inSelIterator;
- (id)controlValueForID:(NSString *)inControlID forPart:(NSString *)inControlPart withIterator:(SelectionIterator *)inSelIterator outProperties:(CFDictionaryRef *)outCustomProperties; //returns string or array of strings
- (id)controlValue:(id)controlOrView forPart:(NSString *)inControlPart withIterator:(SelectionIterator *)inSelIterator;
- (void)setControlStringValue:(NSString *)inValue forControlID:(NSString *)inControlID;
- (void)setControlValues:(CFDictionaryRef)inControlDict;
- (CFDictionaryRef)copyControlProperties:(id)controlOrView;
- (void)handleAction:(id)sender;
- (void)handleDoubleClickAction:(id)sender;
- (OMCCocoaDialog *)getOMCDialog;
- (Boolean)isModal;
- (void)run;
- (BOOL)isOkeyed;
- (BOOL)isCanceled;
- (BOOL)commandShouldCloseDialog;
- (BOOL)initialize;
- (BOOL)terminate;
- (void)dispatchCommand:(NSString *)inCommandID withContext:(CFTypeRef)inContext;
- (OSStatus)processCommandWithContext:(CFTypeRef)inContext;
- (id)getContext; // context as Obj-C object (translated from AEDesc)
- (void)setWindowTopLeftPosition:(NSPoint)absolutePosition;
- (void) sendObjCMessage:(CFArrayRef)oneObjCMessage toTarget:(id)messageTarget;
- (SelectionIterator *)createSelectionIterator:(CFDictionaryRef)inIteratorParams;
- (void)keepItem:(id)inItem;

@end //OMCDialogController

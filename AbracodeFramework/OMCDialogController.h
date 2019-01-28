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
#include "AStdNew.h"
#include "SelectionIterator.h"

class OnMyCommandCM;
class OMCCocoaDialog;

@interface OMCDialogController : NSObject <NSWindowDelegate>
{
	NSWindow * mWindow;//we own it
	OMCCocoaNib *mOmcCocoaNib;

	NSString *mLastCommandID;//we own it
	NSMutableSet *mDialogOwnedItems;

	//we compile ObjC with the flag to invoke C++ constructors and destructor
	//so we can use smart pointers as member variables

	ARefCountedObj<OnMyCommandCM>	mPlugin;
	AStdNew<OMCCocoaDialog>			mOMCDialogProxy;
	CFObj<CFBundleRef>				mExternBundleRef;
	CFObj<CFArrayRef>				mCommandName;
	CFObj<CFStringRef>				mDialogUniqueID;
	CFObj<CFStringRef>				mInitSubcommandID;
	CFObj<CFStringRef>				mEndOKSubcommandID;
	CFObj<CFStringRef>				mEndCancelSubcommandID;
	Boolean							mIsModal;
	Boolean							mIsRunning;
	Boolean							mDeleteSelfOnClose;

}

- (id)initWithOmc:(OnMyCommandCM *)inOmc;
- (Boolean)findNib:(NSString *)inNibName forBundlePath:(NSString *)inPath;
//- (id)initWithWindow:(NSWindow *)inWindow;
- (void)initSubview:(NSView *)inView;
- (void)resetSubview:(NSView *)inView;
- (id)findViewInParent:(NSView *)inParentView forControlID:(NSString *)inControlID;//may return NSView or NSCell
- (id)findControlOrViewWithID:(NSString *)inControlID;//may return NSView or NSCell
- (CFTypeRef)controlValue:(NSString *)inControlID forPart:(NSInteger)inControlPart withIterator:(SelectionIterator *)inSelIterator outProperties:(CFDictionaryRef *)outCustomProperties; //returns string or array of strings
- (void)setControlStringValue:(NSString *)inValue forControlID:(NSString *)inControlID;
- (void)setControlValues:(CFDictionaryRef)inControlDict;
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
- (id)getCFContext;//cm context as CF object (translated from AEDesc)
- (void)setWindowTopLeftPosition:(NSPoint)absolutePosition;
- (void) sendObjCMessage:(CFArrayRef)oneObjCMessage toTarget:(id)messageTarget;
- (SelectionIterator *)createSelectionIterator:(CFDictionaryRef)inIteratorParams;
- (void)keepItem:(id)inItem;

@end

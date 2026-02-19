//
//  OMCNibWindowController.h
//  Abracode
//
//  Created by Tomasz Kukielka on 1/20/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "OMCCocoaNib.h"
#import "OMCWindowController.h"
#import "OMCControlAccessor.h"

class OMCNibDialog;

@interface OMCNibWindowController : OMCWindowController <NSWindowDelegate, OMCControlAccessor>
{
	// we compile ObjC with the flag to invoke C++ constructors and destructor
	// so we can use smart pointers as member variables
}

@property (nonatomic, strong) OMCCocoaNib *omcCocoaNib;

- (Boolean)findNib:(NSString *)inNibName forBundlePath:(NSString *)inPath;
- (void)initSubview:(NSView *)inView;
- (void)resetSubview:(NSView *)inView;
- (id)findViewInParent:(NSView *)inParentView forControlID:(NSString *)inControlID; // may return NSView or NSCell
- (id)findControlOrViewWithID:(NSString *)inControlID; // may return NSView or NSCell
- (void)allControlValues:(NSMutableDictionary *)ioControlValues andProperties:(NSMutableDictionary *)ioCustomProperties withIterator:(SelectionIterator *)inSelIterator;
- (id)controlValueForID:(NSString *)inControlID forPart:(NSString *)inControlPart withIterator:(SelectionIterator *)inSelIterator outProperties:(CFDictionaryRef *)outCustomProperties; // returns string or array of strings
- (id)controlValue:(id)controlOrView forPart:(NSString *)inControlPart withIterator:(SelectionIterator *)inSelIterator;
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

- (CFDictionaryRef)copyControlProperties:(id)controlOrView;
- (void)handleAction:(id)sender;
- (void)handleDoubleClickAction:(id)sender;

@end

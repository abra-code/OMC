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

class OMCNibDialog;

@interface OMCNibWindowController : OMCWindowController <NSWindowDelegate>
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
- (void)setControlValues:(CFDictionaryRef)inControlDict;
- (CFDictionaryRef)copyControlProperties:(id)controlOrView;
- (void)handleAction:(id)sender;
- (void)handleDoubleClickAction:(id)sender;
- (void)setWindowTopLeftPosition:(NSPoint)absolutePosition;
- (void) sendObjCMessage:(CFArrayRef)oneObjCMessage toTarget:(id)messageTarget;

@end

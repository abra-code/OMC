//
//  OMCWindowControlProtocol.h
//  Abracode
//
//  Protocol declaring the UI framework-specific control manipulation interface.
//  Adopted by OMCWindowController (no-op defaults), OMCNibWindowController (AppKit/Nib
//  reference implementation), and OMCActionUIWindowController (SwiftUI/ActionUI implementation).
//

#import <Cocoa/Cocoa.h>
#include "SelectionIterator.h"

@protocol OMCWindowControlProtocol <NSObject>

@required

// Control value and state
- (void)setControlStringValue:(NSString *)inValue forControlID:(NSString *)inControlID;
- (void)setControlEnabled:(BOOL)enabled forControlID:(NSString *)inControlID;
- (void)setControlVisible:(BOOL)visible forControlID:(NSString *)inControlID;

// List / popup controls
- (void)removeAllListItemsForControlID:(NSString *)inControlID;
- (void)setListItems:(CFArrayRef)items forControlID:(NSString *)inControlID;
- (void)appendListItems:(CFArrayRef)items forControlID:(NSString *)inControlID;

// Table controls
- (void)emptyTableForControlID:(NSString *)inControlID;
- (void)removeTableRowsForControlID:(NSString *)inControlID;
- (void)setTableRows:(CFArrayRef)rows forControlID:(NSString *)inControlID;
- (void)addTableRows:(CFArrayRef)rows forControlID:(NSString *)inControlID;
- (void)setTableColumns:(CFArrayRef)columns forControlID:(NSString *)inControlID;
- (void)setTableColumnWidths:(CFArrayRef)widths forControlID:(NSString *)inControlID;

// Control layout and focus
- (void)selectControlWithID:(NSString *)inControlID;
- (void)setCommandID:(NSString *)commandID forControlID:(NSString *)inControlID;
- (void)moveControlWithID:(NSString *)inControlID toPosition:(NSPoint)position;
- (void)resizeControlWithID:(NSString *)inControlID toSize:(NSSize)size;
- (void)scrollControlWithID:(NSString *)inControlID toPosition:(NSPoint)position;

// ObjC message dispatch
- (void)invokeMessagesForControlID:(NSString *)inControlID messages:(CFArrayRef)messages;

// Generic property setter (ActionUI: JSON-deserialized value; Nib: not supported)
- (void)setPropertyKey:(NSString *)propertyKey jsonValue:(NSString *)jsonValue forControlID:(NSString *)inControlID;

// State setter (ActionUI: string or JSON-deserialized value; Nib: not supported)
- (void)setStateKey:(NSString *)stateKey stringOrJsonValue:(NSString *)value forControlID:(NSString *)inControlID;

@end

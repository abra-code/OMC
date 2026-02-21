//
//  OMCActionUIWindowController.h
//  Abracode
//
//  Created by Tomasz Kukielka on 2/17/26.
//  Copyright 2026 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "OMCWindowController.h"
#import "OMCControlAccessor.h"
#import "OMCWindowControlProtocol.h"

class OMCActionUIDialog;

@interface OMCActionUIWindowController : OMCWindowController <NSWindowDelegate, OMCControlAccessor, OMCWindowControlProtocol>
{
}

@property (nonatomic, strong) NSViewController *hostingController;

// OMCControlAccessor
- (void)allControlValues:(NSMutableDictionary *)ioControlValues andProperties:(NSMutableDictionary *)ioCustomProperties withIterator:(SelectionIterator *)inSelIterator;
- (id)controlValueForID:(NSString *)inControlID forPart:(NSString *)inControlPart withIterator:(SelectionIterator *)inSelIterator outProperties:(CFDictionaryRef *)outCustomProperties;

// OMCWindowControlProtocol — ActionUI/SwiftUI implementation
// Implemented: setControlStringValue, setControlEnabled, setControlVisible,
//              removeAllListItemsForControlID, setListItems, appendListItems,
//              emptyTableForControlID, removeTableRowsForControlID,
//              setTableRows, addTableRows, setTableColumns, setTableColumnWidths
// Stub (not applicable to declarative SwiftUI layout):
//              selectControlWithID, setCommandID:forControlID,
//              moveControlWithID, resizeControlWithID, scrollControlWithID,
//              invokeMessagesForControlID

@end

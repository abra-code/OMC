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

class OMCActionUIDialog;

@interface OMCActionUIWindowController : OMCWindowController <NSWindowDelegate, OMCControlAccessor>
{
}

- (void)allControlValues:(NSMutableDictionary *)ioControlValues andProperties:(NSMutableDictionary *)ioCustomProperties withIterator:(SelectionIterator *)inSelIterator;
- (id)controlValueForID:(NSString *)inControlID forPart:(NSString *)inControlPart withIterator:(SelectionIterator *)inSelIterator outProperties:(CFDictionaryRef *)outCustomProperties;
- (void)setControlValues:(CFDictionaryRef)inControlDict;

@end

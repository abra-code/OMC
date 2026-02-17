//
//  OMCControlAccessor.h
//  Abracode
//
//  Protocol for dialog controllers that provide control value get/set functionality
//

#import <Foundation/Foundation.h>
#import "SelectionIterator.h"

@protocol OMCControlAccessor <NSObject>

@required

- (void)setControlValues:(CFDictionaryRef)inControlDict;
- (void)allControlValues:(NSMutableDictionary *)ioControlValues andProperties:(NSMutableDictionary *)ioCustomProperties withIterator:(SelectionIterator *)inSelIterator;
- (id)controlValueForID:(NSString *)inControlID forPart:(NSString *)inControlPart withIterator:(SelectionIterator *)inSelIterator outProperties:(CFDictionaryRef *)outCustomProperties;

@end

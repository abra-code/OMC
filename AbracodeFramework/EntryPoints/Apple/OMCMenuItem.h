/*
	OMCMenuItem.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCMenuItem : NSMenuItem

@property (nonatomic, strong) IBInspectable NSString * commandID;
@property (nonatomic, strong) IBInspectable NSString * mappedValue;
@property (nonatomic, strong) IBInspectable NSString * escapingMode;

@end


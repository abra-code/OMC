/*
	OMCButtonCell.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCButtonCell : NSButtonCell <NSDraggingDestination>

@property (nonatomic, strong) IBInspectable NSString * commandID;
@property (nonatomic, strong) IBInspectable NSString * mappedOnValue;
@property (nonatomic, strong) IBInspectable NSString * mappedOffValue;
@property (nonatomic, strong) IBInspectable NSString * escapingMode;

@end


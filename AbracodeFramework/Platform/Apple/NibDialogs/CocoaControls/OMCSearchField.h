/*
	OMCSearchField.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCSearchField : NSSearchField

@property (nonatomic, strong) IBInspectable NSString * commandID;
@property (nonatomic, strong) IBInspectable NSString * escapingMode;

@end

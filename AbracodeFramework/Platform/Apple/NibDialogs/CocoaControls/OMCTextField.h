/*
	OMCTextField.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCTextField : NSTextField

@property (nonatomic, strong) IBInspectable NSString * commandID;
@property (nonatomic, strong) IBInspectable NSString * escapingMode;

@end

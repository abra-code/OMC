/*
	OMCSecureTextField.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCSecureTextField : NSSecureTextField

@property (nonatomic, strong) IBInspectable NSString * commandID;
@property (nonatomic, strong) IBInspectable NSString * escapingMode;

@end

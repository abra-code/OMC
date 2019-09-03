/*
	OMCTextField.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCTextField : NSTextField
{
}

@property (nonatomic, retain) IBInspectable NSString * commandID;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

@end

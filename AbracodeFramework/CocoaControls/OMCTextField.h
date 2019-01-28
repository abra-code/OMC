/*
	OMCTextField.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCTextField : NSTextField
{
	NSString *	commandID;
	NSString *  escapingMode;
}

@property (nonatomic, retain) IBInspectable NSString * commandID;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

@end

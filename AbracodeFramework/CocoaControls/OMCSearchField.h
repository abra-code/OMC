/*
	OMCSearchField.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCSearchField : NSSearchField
{
	NSString *	commandID;
	NSString *  escapingMode;
}

@property (nonatomic, retain) IBInspectable NSString * commandID;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

@end

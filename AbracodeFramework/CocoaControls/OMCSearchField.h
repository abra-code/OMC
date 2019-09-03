/*
	OMCSearchField.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCSearchField : NSSearchField
{
}

@property (nonatomic, retain) IBInspectable NSString * commandID;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

@end

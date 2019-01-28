/*
	OMCButtonCell.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCButtonCell : NSButtonCell <NSDraggingDestination>
{
	NSString *	commandID;
	NSString *	mappedOnValue;
	NSString *	mappedOffValue;
	NSString *  escapingMode;
}

@property (nonatomic, retain) IBInspectable NSString * commandID;
@property (nonatomic, retain) IBInspectable NSString * mappedOnValue;
@property (nonatomic, retain) IBInspectable NSString * mappedOffValue;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

@end


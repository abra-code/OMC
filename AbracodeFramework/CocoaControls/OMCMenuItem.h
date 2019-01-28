/*
	OMCMenuItem.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCMenuItem : NSMenuItem
{
	NSString *	commandID;
	NSString *	mappedValue;
	NSString *  escapingMode;
}

@property (nonatomic, retain) IBInspectable NSString * commandID;
@property (nonatomic, retain) IBInspectable NSString * mappedValue;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

@end


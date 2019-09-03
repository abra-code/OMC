/*
	OMCMenuItem.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCMenuItem : NSMenuItem
{
}

@property (nonatomic, retain) IBInspectable NSString * commandID;
@property (nonatomic, retain) IBInspectable NSString * mappedValue;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

@end


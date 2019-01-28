/*
	OMCSlider.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCSlider : NSSlider
{
	NSString *	commandID;
}

@property (nonatomic, retain) IBInspectable NSString * commandID;

@end



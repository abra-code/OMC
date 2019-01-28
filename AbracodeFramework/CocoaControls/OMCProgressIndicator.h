/*
	OMCProgressIndicator.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCProgressIndicator : NSProgressIndicator
{
	NSInteger _omcTag;
}

@property(readwrite) IBInspectable NSInteger tag;

@end


/*
	OMCProgressIndicator.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCProgressIndicator : NSProgressIndicator
@property (nonatomic, readwrite) IBInspectable NSInteger tag;

@end


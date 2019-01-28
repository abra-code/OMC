/*
	OMCBox.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCBox : NSBox
{
	NSInteger _omcTag;
	BOOL	enabled;
}

//no tag in NSBox - OMC extension
@property(readwrite) IBInspectable NSInteger tag;

//NSBox does not inerit from NSView but we want the enable/disable methods working the same
- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)flag;

@end //OMCBox

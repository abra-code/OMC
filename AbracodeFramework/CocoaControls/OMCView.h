/*
	OMCView.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCView : NSView
{
	NSInteger _omcTag;
	BOOL	enabled;
}

@property(readwrite) IBInspectable NSInteger tag;

- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)flag;

//recursive enable/disable for all controls in a view
+ (void)setEnabled:(BOOL)flag inView:(id)inView;

@end //OMCView

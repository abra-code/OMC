/*
	OMCView.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCView : NSView
{
	BOOL	_enabled;
}

@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, readwrite) BOOL enabled;

//recursive enable/disable for all controls in a view
+ (void)setEnabled:(BOOL)flag inView:(id)inView;

@end //OMCView

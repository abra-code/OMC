/*
	OMCView.h
*/

#import <Cocoa/Cocoa.h>
#import "OMCActionProtocol.h"

IB_DESIGNABLE
@interface OMCView : NSView<OMCActionProtocol>

@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, assign) SEL action;
@property (nonatomic, readwrite) BOOL enabled;

//recursive enable/disable for all controls in a view
+ (void)setEnabled:(BOOL)flag inView:(id)inView;

@end //OMCView

/*
	OMCGridView.h
*/

#import <AppKit/AppKit.h>

IB_DESIGNABLE
@interface OMCGridView : NSGridView

@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, readwrite) IBInspectable BOOL enabled;

@end //OMCGridView

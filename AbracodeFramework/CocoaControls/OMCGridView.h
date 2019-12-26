/*
	OMCGridView.h
*/

#import <AppKit/AppKit.h>

IB_DESIGNABLE
@interface OMCGridView : NSGridView
{
	BOOL	_enabled;
}

@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, readwrite) IBInspectable BOOL enabled;

@end //OMCGridView

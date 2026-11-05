/*
	OMCBox.h
*/

#import <AppKit/AppKit.h>

IB_DESIGNABLE
@interface OMCBox : NSBox

@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, readwrite) IBInspectable BOOL enabled;

@end //OMCBox

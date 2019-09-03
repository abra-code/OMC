/*
	OMCBox.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCBox : NSBox
{
	BOOL	_enabled;
}

@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, readwrite) IBInspectable BOOL enabled;

@end //OMCBox

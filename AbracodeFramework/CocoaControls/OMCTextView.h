/*
	OMCTextView.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCTextView : NSTextView
{
	BOOL	_enabled;
	NSColor *_savedTextColor;//before disabling save the color
}

@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, readwrite) BOOL enabled;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;

@end

/*
	OMCTextView.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCTextView : NSTextView
{
	NSInteger	_omcTag;
	NSString *  escapingMode;
	BOOL	enabled;
	NSColor *savedTextColor;//before disabling save the color
}

@property(readwrite) IBInspectable NSInteger tag;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;

- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)flag;

@end

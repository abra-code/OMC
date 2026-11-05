/*
	OMCTextView.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCTextView : NSTextView

@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, readwrite) BOOL enabled;
@property (nonatomic, strong) NSColor *savedTextColor; //before disabling save the color

@property (nonatomic, strong) IBInspectable NSString * escapingMode;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;

@end

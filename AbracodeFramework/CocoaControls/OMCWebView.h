/*
	OMCWebView.h
*/

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

IB_DESIGNABLE
@interface OMCWebView : WebView
{
}

@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;

@end

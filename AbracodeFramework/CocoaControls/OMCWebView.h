/*
	OMCWebView.h
*/

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

/* 
   THIS CONTROL IS DEPRECATED
   USE OMCWebKitView INSTEAD
*/


IB_DESIGNABLE
@interface OMCWebView : WebView
{
}

@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;

@end

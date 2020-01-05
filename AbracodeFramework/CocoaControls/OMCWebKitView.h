/*
	OMCWebKitView.h
*/

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

// Note that OMCWebKitView inherits from NSView and not WKWebView
// When creating this control in nib file, insert "custom view", which is NSView
// Then switch to class inspector and change the name to OMCWebKitView
// When WKWebView is instantiated from nib it cannot be configured
// For some strange reason Apple chose the design that the configuration cannot be changed
// once the control is created. It effectively forces everyone to create WKWebView in code 

IB_DESIGNABLE
@interface OMCWebKitView : NSView <WKScriptMessageHandler>
{
	WKWebView *_wkWebView;
}

@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;
@property (nonatomic, retain) NSString * commandID;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;


@end

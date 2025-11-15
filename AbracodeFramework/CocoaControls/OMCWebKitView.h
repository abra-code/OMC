/*
	OMCWebKitView.h
*/

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "OMCActionProtocol.h"
#import "OMCViewSetupProtocol.h"

// Note that OMCWebKitView inherits from NSView and not WKWebView
// When creating this control in nib file, insert "custom view", which is NSView
// Then switch to class inspector and change the name to OMCWebKitView
// When WKWebView is instantiated from nib it cannot be configured
// For some strange reason Apple chose the design that the configuration cannot be changed
// once the control is created. It effectively forces everyone to create WKWebView in code 

IB_DESIGNABLE
@interface OMCWebKitView : NSView <WKScriptMessageHandler, WKUIDelegate, OMCActionProtocol, OMCViewSetupProtocol>

@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, strong) WKWebView *wkWebView;

@property (nonatomic, strong) IBInspectable NSString *escapingMode;
@property (nonatomic, strong) IBInspectable NSString *javaScriptFile;
@property (nonatomic, strong) IBInspectable NSString *URL;
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;
@property (nonatomic, strong) NSString *commandID;
@property (nonatomic, strong) NSString *elementID;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;

- (void)storeElementValuesIn:(NSMutableDictionary *)ioDict;

@end

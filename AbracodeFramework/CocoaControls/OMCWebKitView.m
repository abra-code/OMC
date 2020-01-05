/*
	OMCWebView.m
*/

#import "OMCWebKitView.h"

@implementation OMCWebKitView

@synthesize tag;
@synthesize escapingMode;
@synthesize target;
@synthesize action;
@synthesize commandID;

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
	if(self == nil)
		return nil;

	self.escapingMode = @"esc_none";

	return self;
}

- (void)dealloc
{
	self.escapingMode = nil;
	self.target = nil;
	self.action = nil;
	[_wkWebView release];
    [super dealloc];
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == nil)
		return nil;

	self.escapingMode = @"esc_none";

    return self;
}

- (void)awakeFromNib
{
	[super awakeFromNib];
	[self createWKWebKitView];
}

-(void)createWKWebKitView
{
	WKWebViewConfiguration *wkWebViewConfig = [[WKWebViewConfiguration alloc] init];
	WKUserContentController *userContentController = [[WKUserContentController alloc] init];
	wkWebViewConfig.userContentController = userContentController;

	// This adds a function window.webkit.messageHandlers.OMC.postMessage(<messageBody>) for all frames
	[userContentController addScriptMessageHandler:self name:@"OMC"];

	NSRect subFrame = {{0.0, 0.0}, self.frame.size};
	
	_wkWebView = [[WKWebView alloc] initWithFrame:subFrame configuration:wkWebViewConfig];
	[self addSubview:_wkWebView];

	[userContentController release];
	[wkWebViewConfig release];
}

// keep the WKWebView subview resizing to the frame of hosting view
- (void)resizeSubviewsWithOldSize:(NSSize)__unused oldSize
{
	NSRect subFrame = {{0.0, 0.0}, self.frame.size};
	_wkWebView.frame = subFrame;
}

// WKScriptMessageHandler protocol method:
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
	id msgBody = message.body;
	if([msgBody isKindOfClass:[NSDictionary class]])
	{
		NSDictionary<NSString*,id> *messageDict = (NSDictionary *)msgBody;
		id cmdID = [messageDict valueForKey:@"commandID"];
		if((cmdID != nil) && [cmdID isKindOfClass:[NSString class]])
		{
			// This should always be satisfied. OMCDialogController sets itself as target for all controls and views which support it
			if((self.target != nil) && (self.action != nil))
			{
				self.commandID = (NSString *)cmdID; //[OMCDialogController handleAction:] will ask for commandID to execute
				[self.target performSelector:self.action withObject:self]; // = [(OMCDialogController*)_target handleAction:self];
				self.commandID = nil;
			}
		}
	}
}

- (NSString *)stringValue
{
	NSURL *webViewURL = [_wkWebView URL];
	return webViewURL.absoluteString;
}

- (void)setStringValue:(NSString *)aString
{
	if((aString == nil) || ([aString length] == 0))
	{
		[_wkWebView loadHTMLString:@"" baseURL:nil];
		return;
	}

	NSURL *wkWebViewURL = [NSURL URLWithString:aString];
	if(wkWebViewURL.isFileURL)
	{
		NSURL *parentDirURL = [wkWebViewURL URLByDeletingLastPathComponent];
		/*WKNavigation *wkNavigation =*/ [_wkWebView loadFileURL:wkWebViewURL allowingReadAccessToURL:parentDirURL];
	}
	else
	{
		NSURLRequest *urlRequest = [NSURLRequest requestWithURL:wkWebViewURL];
		/*WKNavigation *wkNavigation =*/ [_wkWebView loadRequest:urlRequest];
	}
}

@end

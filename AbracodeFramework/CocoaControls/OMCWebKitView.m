/*
	OMCWebView.m
*/

#import "OMCWebKitView.h"
#include "OMCScriptsManager.h"

@implementation OMCWebKitView

@synthesize tag;
@synthesize escapingMode;
@synthesize javaScriptFile;
@synthesize URL;
@synthesize target;
@synthesize action;
@synthesize commandID;
@synthesize elementID;

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

	NSBundle *frameworkBundle = [NSBundle bundleForClass:self.class];
	NSURL *omcWKSupportScriptURL = [frameworkBundle URLForResource:@"OMCWebKitSupport" withExtension:@"js"];
	NSString *omcWKSupportScriptSource = [NSString stringWithContentsOfURL:omcWKSupportScriptURL encoding:NSUTF8StringEncoding error:nil];
	if(omcWKSupportScriptSource != nil)
	{
		WKUserScript *omcWKSupportScript = [[WKUserScript alloc] initWithSource:omcWKSupportScriptSource injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
		[userContentController addUserScript:omcWKSupportScript];
		[omcWKSupportScript release];
	}

	if(self.javaScriptFile != nil)
	{   // Client specified a script file name to inject
		// This should be a name of file in "Scripts" directory without an extension
		// but in case someone does add a .js extension, cut it
		NSString *scriptName = self.javaScriptFile;
		if([scriptName hasSuffix:@".js"])
			scriptName = [scriptName stringByDeletingPathExtension];

		CFBundleRef hostBundle = CFBundleGetMainBundle(); // TODO: support extern bundle for contextual menus?

		CFStringRef clientScriptPath = OMCGetScriptPath(hostBundle, (CFStringRef)scriptName);
		if(clientScriptPath != NULL)
		{
			NSString *clientScriptSource = [NSString stringWithContentsOfFile:(NSString *)clientScriptPath encoding:NSUTF8StringEncoding error:nil];
			if(clientScriptSource != nil)
			{
				WKUserScript *clientScript = [[WKUserScript alloc] initWithSource:clientScriptSource injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:NO];
				[userContentController addUserScript:clientScript];
				[clientScript release];
			}
		}
	}

	// This adds a function window.webkit.messageHandlers.OMC.postMessage(<messageBody>) for all frames
	[userContentController addScriptMessageHandler:self name:@"OMC"];

	NSRect subFrame = {{0.0, 0.0}, self.frame.size};
	
	_wkWebView = [[WKWebView alloc] initWithFrame:subFrame configuration:wkWebViewConfig];
	[self addSubview:_wkWebView];

	[userContentController release];
	[wkWebViewConfig release];
	
	if(self.URL != nil)
	{
		[self setStringValue:self.URL];
	}
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
	// This should always be satisfied. OMCDialogController sets itself as target for all controls and views which support it
	if((self.target == nil) || (self.action == nil))
		return;

	id msgBody = message.body;
	if([msgBody isKindOfClass:[NSDictionary class]])
	{
		NSDictionary<NSString*,id> *messageDict = (NSDictionary *)msgBody;
		id cmdID = [messageDict valueForKey:@"commandID"];
		if((cmdID != nil) && [cmdID isKindOfClass:[NSString class]])
		{
			id elemID = [messageDict valueForKey:@"elementID"];
			if((elemID != nil) && [elemID isKindOfClass:[NSString class]])
			{
				self.elementID = (NSString *)elemID;
			}

			self.commandID = (NSString *)cmdID; //[OMCDialogController handleAction:] will ask for commandID to execute
			[self.target performSelector:self.action withObject:self]; // = [(OMCDialogController*)_target handleAction:self];
			
			self.commandID = nil;
			self.elementID = nil;
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

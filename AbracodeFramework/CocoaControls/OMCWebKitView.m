/*
	OMCWebView.m
*/

#import "OMCWebKitView.h"
#include "OMCScriptsManager.h"

// OMC ID will be used to construct the environment variables like OMC_NIB_WEBVIEW_1_ELEMENT_MYID_VALUE
// HTML 5 element ID can be any character except whitespace
// Allowed set for OMC is uppercase characters: A-Z, digits: 0-9 and underscore: _
NSString *NormalizeOMCVariableIDFromElementID(NSString *inElementID)
{
	NSUInteger length = [inElementID length];
	if(length == 0)
		return @"";

	unichar *characters = malloc(length * sizeof(unichar));
	if(characters == NULL)
		return @"";

	[inElementID getCharacters:characters range:NSMakeRange(0, length)];

	for(NSUInteger i = 0; i < length; i++)
	{
		unichar oneChar = characters[i];
		if(oneChar >= 'a' && oneChar <= 'z')
			characters[i] = oneChar - 32; //from a -> A, z -> Z
		else if( (oneChar < '0') || (oneChar > '9' && oneChar < 'A') || (oneChar > 'Z') ) //we already handled a-z range above so don't bother again
			characters[i] = '_';
		//else it is A-Z or 0-9 so we leave unchanged
	}
	
	NSString *outString = [NSString stringWithCharacters:characters length:length];
	free(characters);

	return outString;
}

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

- (void)runOMCCommandWithWebkitMessage:(NSDictionary<NSString*,id> *)messageDict
{
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

// WKScriptMessageHandler protocol method:
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
	// This should always be satisfied. OMCDialogController sets itself as target for all controls and views which support it
	if((self.target == nil) || (self.action == nil))
		return;

	id msgBody = message.body;
	if([msgBody isKindOfClass:[NSDictionary class]])
	{
		NSDictionary<NSString*, id> *messageDict = (NSDictionary *)msgBody;

		// We are being executed in callback from WebKit
		// for safety, get out of the callback to execute the OMC command because
		// we need to call into WebKit before executing the command to obtain element values
		CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^()
		{
			[self runOMCCommandWithWebkitMessage:messageDict];
		});
	}
}

- (id)executeJavaScript:(NSString *)scriptString
{
	__block BOOL completionHandled = NO;
	__block id outResult = nil;

	@try
	{
		[_wkWebView evaluateJavaScript:scriptString completionHandler:^(id result, NSError *error)
		{
			completionHandled = YES;
			if(error == nil)
			{
				outResult = [result retain];
			}
			else
			{
				NSLog(@"evaluateJavaScript error : %@", error.localizedDescription);
			}
		}];
	}
	@catch (NSException *localException)
	{
		NSLog(@"evaluateJavaScript: triggered exception: %@", localException);
		completionHandled = YES; //if this happens, we need to make sure the loop below is not infinite
	}

	// Wait for the completion handler to be executed
	// Apple documentation says it is always executed on main thread
	// so it is posted to the CFRunLoop by WebKit
	CFRunLoopRunResult runloopResult;
	do
	{
		runloopResult = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true /*returnAfterSourceHandled*/);
	}
	while(!completionHandled);

	return [outResult autorelease];
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

- (void)storeElementValuesIn:(NSMutableDictionary *)ioDict
{
	// Obtain values from all elements of class OMC
	// OMC.getAllElementValues() is a function injected by our custom JavaScript on WKWebView creation
	id theResult = [self executeJavaScript:@"OMC.getAllElementValues();"];
	if([theResult isKindOfClass:[NSDictionary class]]) //we expect dictionary result from that function
	{
		NSDictionary<NSString*, NSString*> *elementValuesDict = (NSDictionary<NSString*, NSString*> *)theResult;
		// all element values will be exported as OMC_NIB_WEBVIEW_XXX_ELEMENT_YYY_VALUE
		// HTML element id names are normalized to a set [A-Z0-9_]
		//NSLog(@"result = %@", elementValuesDict);
		
		[elementValuesDict enumerateKeysAndObjectsUsingBlock: ^(id inKey, id inObj, BOOL *stop)
		{
			NSString *omcID = NormalizeOMCVariableIDFromElementID((NSString *)inKey);
			[ioDict setValue:inObj forKey:omcID];
		}];
	}
}

@end

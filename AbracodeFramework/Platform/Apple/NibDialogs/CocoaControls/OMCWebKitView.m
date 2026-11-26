/*
	OMCWebKitView.m
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

// Pages may run applet commands and see window.omc_env only when they come from the place the
// applet itself loaded: any local file (a remote page cannot navigate to a file address), or the
// scheme, host and port of the web address the applet set, after the server's redirects.
// A frame from another site (an advertisement, an embedded page) or a page reached through a
// link to another site is refused. The key has the form of JavaScript's location.origin, so the
// same string is checked in native code and in the injected script; "file:" stands for any file.
static NSString *OMCWebOriginKey(NSString *inScheme, NSString *inHost, NSInteger inPort)
{
	NSString *scheme = [inScheme lowercaseString];
	if([scheme isEqualToString:@"file"])
		return @"file:";

	if((scheme.length == 0) || (inHost.length == 0))
		return nil;

	NSString *host = [inHost lowercaseString];
	if([host containsString:@":"] && ![host hasPrefix:@"["])
		host = [NSString stringWithFormat:@"[%@]", host]; // IPv6 address, as location.origin writes it

	NSInteger port = inPort;
	if(([scheme isEqualToString:@"http"] && (port == 80)) || ([scheme isEqualToString:@"https"] && (port == 443)))
		port = 0;

	if(port <= 0)
		return [NSString stringWithFormat:@"%@://%@", scheme, host];
	return [NSString stringWithFormat:@"%@://%@:%ld", scheme, host, (long)port];
}

static NSString *OMCWebOriginKeyForURL(NSURL *inURL)
{
	if(inURL == nil)
		return nil;
	return OMCWebOriginKey(inURL.scheme, inURL.host, (inURL.port != nil) ? inURL.port.integerValue : 0);
}

@interface OMCWebKitView ()
@property (nonatomic, strong) WKUserContentController *userContentController;
@property (nonatomic, copy) NSDictionary *omcEnvVars;
@property (nonatomic, copy) NSString *supportScriptSource;
@property (nonatomic, copy) NSString *clientScriptSource;
@property (nonatomic, copy) NSArray<NSString *> *trustedOriginKeys; // see OMCWebOriginKey()
@property (nonatomic, strong) WKNavigation *appletNavigation; // the load started by setStringValue:, until it commits
@end

@implementation OMCWebKitView

@synthesize tag;

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
	if(self == nil)
		return nil;

	self.escapingMode = @"esc_none";

	return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == nil)
		return nil;

	self.escapingMode = @"esc_none";

    return self;
}

// called right after the nib instantiation by our dialog controller
- (void)setupWithEnvironmentVariables:(NSDictionary *)envVars
{
    [self createWKWebKitViewWithEnvVars:envVars];
}

-(void)createWKWebKitViewWithEnvVars:(NSDictionary *)envVars
{
	WKWebViewConfiguration *wkWebViewConfig = [[WKWebViewConfiguration alloc] init];
	WKUserContentController *userContentController = [[WKUserContentController alloc] init];
	wkWebViewConfig.userContentController = userContentController;
	self.userContentController = userContentController;
	self.omcEnvVars = envVars;
	self.trustedOriginKeys = @[]; // nothing is trusted until the applet loads a page

	NSBundle *frameworkBundle = [NSBundle bundleForClass:self.class];
	NSURL *omcWKSupportScriptURL = [frameworkBundle URLForResource:@"OMCWebKitSupport" withExtension:@"js"];
	self.supportScriptSource = [NSString stringWithContentsOfURL:omcWKSupportScriptURL encoding:NSUTF8StringEncoding error:nil];

	if(self.javaScriptFile != nil)
	{   // Client specified a script file name to inject
		// This should be a name of file in "Scripts" directory without an extension
		// but in case someone does add a .js extension, cut it
		NSString *scriptName = self.javaScriptFile;
		if([scriptName hasSuffix:@".js"])
			scriptName = [scriptName stringByDeletingPathExtension];

		CFBundleRef hostBundle = CFBundleGetMainBundle(); // TODO: support extern bundle for contextual menus?

        CFStringRef clientScriptPath = OMCGetScriptPath(hostBundle, (__bridge CFStringRef)scriptName);
		if(clientScriptPath != NULL)
		{
            self.clientScriptSource = [NSString stringWithContentsOfFile:(__bridge NSString *)clientScriptPath encoding:NSUTF8StringEncoding error:nil];
		}
	}

	[self installUserScripts];

	// This adds a function window.webkit.messageHandlers.OMC.postMessage(<messageBody>) for all frames.
	// Messages from pages the applet did not load are refused in didReceiveScriptMessage.
	[userContentController addScriptMessageHandler:self name:@"OMC"];

	NSRect subFrame = {{0.0, 0.0}, self.frame.size};
	self.wkWebView = [[WKWebView alloc] initWithFrame:subFrame configuration:wkWebViewConfig];
	[self addSubview:self.wkWebView];

    self.wkWebView.UIDelegate = self;
	// Only to learn where the applet's own load ends up after redirects. No policy method is
	// implemented, so WebKit's default handling of links and schemes is unchanged.
	self.wkWebView.navigationDelegate = self;

	if(self.URL != nil)
	{
		[self setStringValue:self.URL];
	}
}

// (Re)install the injected scripts. Called at creation and whenever the trusted origins change,
// because the omc_env script carries the trusted origins in its text. Scripts apply to
// documents created after this call.
- (void)installUserScripts
{
	WKUserContentController *userContentController = self.userContentController;
	if(userContentController == nil)
		return;

	[userContentController removeAllUserScripts];

	[self exportOMCEnvironmentVariables:self.omcEnvVars userContentController:userContentController];

	if(self.supportScriptSource != nil)
	{
		WKUserScript *omcWKSupportScript = [[WKUserScript alloc] initWithSource:self.supportScriptSource injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
		[userContentController addUserScript:omcWKSupportScript];
	}

	if(self.clientScriptSource != nil)
	{
		WKUserScript *clientScript = [[WKUserScript alloc] initWithSource:self.clientScriptSource injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:NO];
		[userContentController addUserScript:clientScript];
	}
}

// Set OMC env variables in window.omc_env
// JavaScript code can access the variables at runtime with code like:
// const myAppPath = window.omc_env.OMC_APP_BUNDLE_PATH
// Only documents from a trusted origin get them (see OMCWebOriginKey). The check runs at document
// start, before any script of the page.
- (void)exportOMCEnvironmentVariables:(NSDictionary *)envVars userContentController:(WKUserContentController *)userContentController
{
	if(envVars == nil)
		return;

    // Convert the dictionary to JSON
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:envVars options:0 error:&error];
    if (jsonData == nil)
    {
        NSLog(@"Error converting dictionary to JSON: %@", error);
        return;
    }
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

	NSArray<NSString *> *trustedKeys = (self.trustedOriginKeys != nil) ? self.trustedOriginKeys : @[];
	NSData *trustedJSONData = [NSJSONSerialization dataWithJSONObject:trustedKeys options:0 error:&error];
	if(trustedJSONData == nil)
	{
		NSLog(@"Error converting trusted origins to JSON: %@", error);
		return;
	}
	NSString *trustedJSONString = [[NSString alloc] initWithData:trustedJSONData encoding:NSUTF8StringEncoding];

    // JavaScript code to inject
	// A plain loop, not trusted.indexOf(): a frame's parent page from the same site can change the
	// built-in prototypes of the frame before its document starts (the window of a new, empty frame
	// is reused for the frame's first page), and a replaced indexOf would hand omc_env to any site.
	// location and its properties cannot be replaced by page script.
    NSString *jsCode = [NSString stringWithFormat:
		@"(function() {"
		 "var trusted = %@;"
		 "var key = (window.location.protocol === 'file:') ? 'file:' : window.location.origin;"
		 "for (var i = 0; i < trusted.length; i++) {"
		 "if (trusted[i] === key) { window.omc_env = %@; return; }"
		 "}"
		 "})();",
		trustedJSONString, jsonString];

    WKUserScript *userScript = [[WKUserScript alloc] initWithSource:jsCode
                                                       injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                    forMainFrameOnly:NO];

    [userContentController addUserScript:userScript];
}

- (BOOL)isTrustedFrame:(WKFrameInfo *)frameInfo
{
	WKSecurityOrigin *origin = frameInfo.securityOrigin;
	if(origin == nil)
		return NO;
	NSString *key = OMCWebOriginKey(origin.protocol, origin.host, origin.port);
	return (key != nil) && [self.trustedOriginKeys containsObject:key];
}

- (void)setTrustedOriginForAppletURL:(NSURL *)inURL
{
	NSString *key = OMCWebOriginKeyForURL(inURL);
	NSArray<NSString *> *newKeys = (key != nil) ? @[key] : @[];
	if(![newKeys isEqualToArray:self.trustedOriginKeys])
	{
		self.trustedOriginKeys = newKeys;
		[self installUserScripts];
	}
}

// keep the WKWebView subview resizing to the frame of hosting view
- (void)resizeSubviewsWithOldSize:(NSSize)__unused oldSize
{
	NSRect subFrame = {{0.0, 0.0}, self.frame.size};
	self.wkWebView.frame = subFrame;
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
		
		self.commandID = (NSString *)cmdID; //[OMCNibWindowController handleAction:] will ask for commandID to execute
		// self.action is a fixed, known selector (handleAction:), not an arbitrary one, so the
		// ARC "may cause a leak" heuristic does not apply here.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		[self.target performSelector:self.action withObject:self]; // = [(OMCNibWindowController*)_target handleAction:self];
#pragma clang diagnostic pop
		
		self.commandID = nil;
		self.elementID = nil;
	}
}

// WKScriptMessageHandler protocol method:
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
	// This should always be satisfied. OMCNibWindowController sets itself as target for all controls and views which support it
	if((self.target == nil) || (self.action == nil))
		return;

	// A page the applet did not load (another site's frame, or a site reached through a link)
	// must not run the applet's commands
	if(![self isTrustedFrame:message.frameInfo])
	{
		WKSecurityOrigin *origin = message.frameInfo.securityOrigin;
		NSLog(@"OMCWebKitView: ignored a command request from %@://%@ - only pages from where the applet loaded its page may run commands", origin.protocol, origin.host);
		return;
	}

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
		[self.wkWebView evaluateJavaScript:scriptString completionHandler:^(id result, NSError *error)
		{
			completionHandled = YES;
			if(error != nil)
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

	return outResult;
}

- (NSString *)stringValue
{
	NSURL *webViewURL = [self.wkWebView URL];
	return webViewURL.absoluteString;
}

- (void)setStringValue:(NSString *)aString
{
	if((aString == nil) || ([aString length] == 0))
	{
		self.appletNavigation = nil;
		[self setTrustedOriginForAppletURL:nil];
		[self.wkWebView loadHTMLString:@"" baseURL:nil];
		return;
	}

	// Navigation commands
	if([aString isEqualToString:@"#goBack"])
	{
		if(self.wkWebView.canGoBack)
			[self.wkWebView goBack];
		return;
	}
	if([aString isEqualToString:@"#goForward"])
	{
		if(self.wkWebView.canGoForward)
			[self.wkWebView goForward];
		return;
	}
	if([aString isEqualToString:@"#reload"])
	{
		[self.wkWebView reload];
		return;
	}
	if([aString isEqualToString:@"#stop"])
	{
		[self.wkWebView stopLoading];
		return;
	}

	NSURL *wkWebViewURL = [NSURL URLWithString:aString];
	NSURL *previousURL = [self.wkWebView URL];
	if((previousURL != nil) && (wkWebViewURL != nil) && [previousURL isEqualTo:wkWebViewURL])
		return;

	// The applet chose this address, so its origin is trusted (before the load starts, so the
	// new document gets the scripts that match it)
	[self setTrustedOriginForAppletURL:wkWebViewURL];

	if(wkWebViewURL.isFileURL)
	{
		NSURL *parentDirURL = [wkWebViewURL URLByDeletingLastPathComponent];
		self.appletNavigation = [self.wkWebView loadFileURL:wkWebViewURL allowingReadAccessToURL:parentDirURL];
	}
	else
	{
		NSURLRequest *urlRequest = [NSURLRequest requestWithURL:wkWebViewURL];
		self.appletNavigation = [self.wkWebView loadRequest:urlRequest];
	}
}

#pragma mark - WKNavigationDelegate

// The applet's own load may be redirected by its server (http to https, example.com to
// www.example.com). The address it finally commits to is trusted as well.
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation
{
	if((navigation == nil) || (navigation != self.appletNavigation))
		return;
	self.appletNavigation = nil;

	NSString *committedKey = OMCWebOriginKeyForURL(webView.URL);
	if((committedKey != nil) && ![self.trustedOriginKeys containsObject:committedKey])
	{
		self.trustedOriginKeys = [self.trustedOriginKeys arrayByAddingObject:committedKey];
		[self installUserScripts];
	}
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
	if((navigation != nil) && (navigation == self.appletNavigation))
		self.appletNavigation = nil;
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


#pragma mark - WKUIDelegate

- (void)webView:(WKWebView *)webView runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSArray<NSURL *> * _Nullable))completionHandler {
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection;
    openPanel.canChooseDirectories = parameters.allowsDirectories;
    openPanel.canChooseFiles = YES;
    
    [openPanel beginWithCompletionHandler:^(NSModalResponse result) {
        completionHandler(result == NSModalResponseOK ? openPanel.URLs : nil);
    }];
}

@end

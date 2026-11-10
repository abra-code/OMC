//
//  OMCDropletControllerTests.m
//  AbracodeTests
//
//  What the applet's controller does when the app is asked to open files, a URL, a new
//  or untitled document, or to reopen: which command runs, with which context, and what is noted
//  as recent. The controller is exported and driven directly; its command file is a test file
//  given by absolute path, and each command writes its context into a marker file.
//
//  The applet allows the open panel for a command that needs files and got none; the test command
//  turns that off (USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT), since a modal panel would wait for
//  ever here, so that choice is not exercised.
//
//  Recent documents are recorded, not written: -[NSDocumentController noteNewRecentDocumentURL:]
//  is replaced for the length of each test, because the real one adds to the user's Recent Items.
//

#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "OMCDropletController.h"

static NSMutableArray<NSURL *> *sNotedRecentURLs = nil;

static void RecordRecentDocumentURL(id self, SEL _cmd, NSURL *inURL)
{
	(void)self;
	(void)_cmd;
	if (inURL != nil)
		[sNotedRecentURLs addObject:inURL];
}

// Stands in for NSApp as the sender of application:openURLs:, to see the reply
@interface OMCAppletTestApplication : NSObject
@property (nonatomic, strong) NSMutableArray<NSNumber *> *replies;
- (void)replyToOpenOrPrint:(NSApplicationDelegateReply)inReply;
@end

@implementation OMCAppletTestApplication
- (instancetype)init
{
	self = [super init];
	if (self != nil)
		_replies = [NSMutableArray array];
	return self;
}
- (void)replyToOpenOrPrint:(NSApplicationDelegateReply)inReply
{
	[self.replies addObject:@(inReply)];
}
@end

@interface OMCDropletControllerTests : XCTestCase
@property (nonatomic, strong) NSURL *workFolder;
@property (nonatomic, assign) IMP originalNoteRecent;
@end

@implementation OMCDropletControllerTests

// NSDocumentController's init returns the shared document controller once there is one, and AppKit
// makes a plain one when another test in the same process uses it first: then every test here got
// an NSDocumentController ("unrecognized selector setCommandID:"). The applet controller is made
// before any test runs, so it is the shared one, as in an applet (OMCApplet's main.m), and each
// makeApplet gets it back with a new OMCApplet.
+ (void)load
{
	static OMCDropletController *sSharedApplet = nil;
	sSharedApplet = [[OMCDropletController alloc] init];
}

- (void)setUp
{
	[super setUp];
	NSString *name = [NSString stringWithFormat:@"OMCDropletControllerTests-%@", [NSUUID UUID].UUIDString];
	self.workFolder = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name] isDirectory:YES];
	[[NSFileManager defaultManager] createDirectoryAtURL:self.workFolder withIntermediateDirectories:YES attributes:nil error:NULL];

	sNotedRecentURLs = [NSMutableArray array];
	Method noteRecent = class_getInstanceMethod([NSDocumentController class], @selector(noteNewRecentDocumentURL:));
	self.originalNoteRecent = method_setImplementation(noteRecent, (IMP)RecordRecentDocumentURL);
}

- (void)tearDown
{
	Method noteRecent = class_getInstanceMethod([NSDocumentController class], @selector(noteNewRecentDocumentURL:));
	method_setImplementation(noteRecent, self.originalNoteRecent);
	sNotedRecentURLs = nil;
	[[NSFileManager defaultManager] removeItemAtURL:self.workFolder error:NULL];
	[super tearDown];
}

- (NSString *)markerPath
{
	return [self.workFolder.path stringByAppendingPathComponent:@"ran.txt"];
}

// The applet's commands: "main" writes "main:<its files, comma separated>", "link" (allowed for
// URLs) writes "link:<its text>", and omc.app.handle-url writes "url:<the URL>"
- (NSString *)writeCommandFile
{
	NSString *marker = [self markerPath];
	NSArray *commands = @[
		@{
			@"NAME": @"Main",
			@"COMMAND_ID": @"main",
			@"EXECUTION_MODE": @"exe_silent_popen",
			@"MULTIPLE_OBJECT_SETTINGS": @{ @"PROCESSING_MODE": @"proc_together", @"SEPARATOR": @"," },
			// It names a file, so with no files the runner would ask for them in the open panel,
			// which nobody answers in a unit test: with no files it runs with none instead
			@"USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT": @NO,
			@"COMMAND": @[[NSString stringWithFormat:@"/usr/bin/printf 'main:%%s\\n' \"$OMC_OBJ_PATH\" >> '%@'", marker]],
		},
		@{
			@"NAME": @"Link",
			@"COMMAND_ID": @"link",
			@"URL_INVOCABLE": @YES,
			@"EXECUTION_MODE": @"exe_silent_popen",
			@"COMMAND": @[[NSString stringWithFormat:@"/usr/bin/printf 'link:%%s\\n' \"$OMC_OBJ_TEXT\" >> '%@'", marker]],
		},
		@{
			@"NAME": @"Handle URL",
			@"COMMAND_ID": @"omc.app.handle-url",
			@"EXECUTION_MODE": @"exe_silent_popen",
			@"COMMAND": @[[NSString stringWithFormat:@"/usr/bin/printf 'url:%%s\\n' \"$OMC_OBJ_TEXT\" >> '%@'", marker]],
		},
	];
	NSURL *fileURL = [self.workFolder URLByAppendingPathComponent:@"Command.plist"];
	NSError *error = nil;
	BOOL written = [@{ @"VERSION": @2, @"COMMAND_LIST": commands } writeToURL:fileURL error:&error];
	XCTAssertTrue(written, @"%@", error);
	return fileURL.path;
}

- (OMCDropletController *)makeApplet
{
	OMCDropletController *applet = [[OMCDropletController alloc] init];
	applet.commandID = @"main";
	applet.commandFilePath = [self writeCommandFile];
	return applet;
}

- (NSURL *)makeFile:(NSString *)inName
{
	NSURL *fileURL = [self.workFolder URLByAppendingPathComponent:inName];
	[@"x" writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	return fileURL;
}

// Runs the run loop for the given time, then returns the marker file's lines
- (NSArray<NSString *> *)markerLinesAfter:(NSTimeInterval)inSeconds
{
	NSDate *until = [NSDate dateWithTimeIntervalSinceNow:inSeconds];
	while ([until timeIntervalSinceNow] > 0)
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
	NSString *text = [NSString stringWithContentsOfFile:[self markerPath] encoding:NSUTF8StringEncoding error:NULL];
	if (text.length == 0)
		return @[];
	return [[text stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@"\n"];
}

- (void)testUntitledLaunchRunsTheMainCommandWithNoContext
{
	OMCDropletController *applet = [self makeApplet];
	BOOL opened = [applet applicationOpenUntitledFile:NSApp];
	XCTAssertTrue(opened);
	XCTAssertEqualObjects([self markerLinesAfter:1.0], (@[ @"main:" ]));
	XCTAssertEqual(sNotedRecentURLs.count, 0u);
}

- (void)testNewAndOpenDocumentRunTheMainCommandWithNoContext
{
	OMCDropletController *applet = [self makeApplet];
	[applet newDocument:nil];
	[applet openDocument:nil];
	XCTAssertEqualObjects([self markerLinesAfter:1.0], (@[ @"main:", @"main:" ]));
}

- (void)testOpenedFilesAreGatheredIntoOneRunAndNotedAsRecent
{
	OMCDropletController *applet = [self makeApplet];
	OMCAppletTestApplication *application = [[OMCAppletTestApplication alloc] init];
	NSURL *first = [self makeFile:@"first.txt"];
	NSURL *second = [self makeFile:@"second.txt"];
	// Two calls in quick succession, as Finder sends a drop; the web URL is not a file and is left out
	[applet application:(NSApplication *)application openURLs:@[ first ]];
	[applet application:(NSApplication *)application openURLs:@[ second, [NSURL URLWithString:@"https://example.com/x"] ]];
	XCTAssertEqualObjects([self markerLinesAfter:0.1], (@[]), @"nothing runs before the files are gathered");

	NSArray<NSString *> *lines = [self markerLinesAfter:1.5];
	NSString *expected = [NSString stringWithFormat:@"main:%@,%@", first.path, second.path];
	XCTAssertEqualObjects(lines, (@[ expected ]), @"one run with both files");
	XCTAssertEqualObjects(sNotedRecentURLs, (@[ first, second ]));
	XCTAssertEqualObjects(application.replies, (@[ @(NSApplicationDelegateReplySuccess) ]));
}

- (void)testOpeningOnlyURLsThatAreNotFilesRunsNothing
{
	OMCDropletController *applet = [self makeApplet];
	OMCAppletTestApplication *application = [[OMCAppletTestApplication alloc] init];
	[applet application:(NSApplication *)application openURLs:@[ [NSURL URLWithString:@"https://example.com/x"] ]];
	XCTAssertEqualObjects([self markerLinesAfter:1.0], (@[]));
	XCTAssertEqual(application.replies.count, 0u);
	XCTAssertEqual(sNotedRecentURLs.count, 0u);
}

- (void)testOpenDocumentWithAURLRunsTheMainCommandWithItAndNotesIt
{
	OMCDropletController *applet = [self makeApplet];
	NSURL *file = [self makeFile:@"recent.txt"];
	__block BOOL completed = NO;
	[applet openDocumentWithContentsOfURL:file display:YES completionHandler:^(NSDocument *document, BOOL alreadyOpen, NSError *error) {
		XCTAssertNil(document);
		XCTAssertFalse(alreadyOpen);
		XCTAssertNil(error);
		completed = YES;
	}];
	XCTAssertTrue(completed, @"the completion handler is called at once");
	XCTAssertEqualObjects([self markerLinesAfter:1.0], (@[ [@"main:" stringByAppendingString:file.path] ]));
	XCTAssertEqualObjects(sNotedRecentURLs, (@[ file ]));
}

- (void)testOpenFilesRunsTheMainCommandWithThemAtOnce
{
	OMCDropletController *applet = [self makeApplet];
	NSURL *first = [self makeFile:@"a.txt"];
	NSURL *second = [self makeFile:@"b.txt"];
	[applet openFiles:@[ first, second ]];
	NSString *expected = [NSString stringWithFormat:@"main:%@,%@", first.path, second.path];
	XCTAssertEqualObjects([self markerLinesAfter:1.0], (@[ expected ]));
	XCTAssertEqualObjects(sNotedRecentURLs, (@[ first, second ]));
}

- (NSAppleEventDescriptor *)getURLEvent:(NSString *)inURL
{
	NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:kInternetEventClass
																			  eventID:kAEGetURL
																	 targetDescriptor:nil
																			 returnID:kAutoGenerateReturnID
																		transactionID:kAnyTransactionID];
	[event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:inURL] forKeyword:keyDirectObject];
	return event;
}

- (void)testAURLEventRunsWhatTheURLAsksFor
{
	OMCDropletController *applet = [self makeApplet];
	[applet handleGetURLEvent:[self getURLEvent:@"omc://exe?commandID=link&text=hello"] withReplyEvent:[NSAppleEventDescriptor nullDescriptor]];
	[applet handleGetURLEvent:[self getURLEvent:@"omc://other/path"] withReplyEvent:[NSAppleEventDescriptor nullDescriptor]];
	// The main command is not URL_INVOCABLE: refused
	[applet handleGetURLEvent:[self getURLEvent:@"omc://exe?commandID=main"] withReplyEvent:[NSAppleEventDescriptor nullDescriptor]];
	// The two commands run at once, so their lines can land in either order
	NSArray<NSString *> *lines = [[self markerLinesAfter:1.0] sortedArrayUsingSelector:@selector(compare:)];
	XCTAssertEqualObjects(lines, (@[ @"link:hello", @"url:omc://other/path" ]));
	XCTAssertEqual(sNotedRecentURLs.count, 0u);
}

- (void)testAURLEventWithoutAURLRunsNothing
{
	OMCDropletController *applet = [self makeApplet];
	NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:kInternetEventClass
																			  eventID:kAEGetURL
																	 targetDescriptor:nil
																			 returnID:kAutoGenerateReturnID
																		transactionID:kAnyTransactionID];
	[applet handleGetURLEvent:event withReplyEvent:[NSAppleEventDescriptor nullDescriptor]];
	XCTAssertEqualObjects([self markerLinesAfter:0.5], (@[]));
}

- (void)testReopenWithVisibleWindowsDoesNothing
{
	OMCDropletController *applet = [self makeApplet];
	XCTAssertFalse([applet applicationShouldHandleReopen:NSApp hasVisibleWindows:YES]);
	XCTAssertEqualObjects([self markerLinesAfter:0.3], (@[]));
}

@end

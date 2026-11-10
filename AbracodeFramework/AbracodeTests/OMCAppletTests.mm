//
//  OMCAppletTests.mm
//  AbracodeTests
//
//  The applet's decisions (OMCApplet.h) with recorded actions: what runs, when, with what, and
//  what is suppressed. OMCDropletControllerTests drives the macOS controller around it; this file
//  covers what that one cannot reach, such as Option held at startup.
//
//  OMCApplet is not exported from Abracode.framework, so it compiles into this bundle. Its
//  OMCMainThreadSignal (the 0.25 s gathering) is the bundle's copy compiled by
//  OMCMainThreadSignalTests.mm.
//

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#include <string>
#include <vector>

#include "../OMCApplet.cpp"

namespace
{

struct RecordedActions
{
	std::vector<std::string> calls;	// "main:<context>", "url:<url>", "recent:<path>", "opened"
	OSStatus mainStatus {noErr};
	OMCApplet *applet {nullptr};
	std::vector<bool> reopenAnswersDuringRun; // ShouldHandleReopen asked from inside the main command
	CFArrayRef urlsToOpenDuringRun {nullptr}; // the first main command opens these, then spins the run loop
	int runDepth {0};
	int deepestRun {0};
};

void RunRunLoop(NSTimeInterval inSeconds);

std::string Describe(CFTypeRef inValue)
{
	if(inValue == nullptr)
		return "";
	if(::CFGetTypeID(inValue) == ::CFURLGetTypeID())
		return std::string([[(__bridge NSURL *)inValue path] UTF8String]);
	if(::CFGetTypeID(inValue) == ::CFArrayGetTypeID())
	{
		std::string text;
		for(id item in (__bridge NSArray *)inValue)
		{
			if(!text.empty())
				text += ",";
			text += Describe((__bridge CFTypeRef)item);
		}
		return text;
	}
	return std::string([[(__bridge id)inValue description] UTF8String]);
}

OSStatus RecordMain(void *inContext, CFTypeRef inCommandContext)
{
	RecordedActions *actions = (RecordedActions *)inContext;
	actions->calls.push_back("main:" + Describe(inCommandContext));
	actions->runDepth++;
	if(actions->runDepth > actions->deepestRun)
		actions->deepestRun = actions->runDepth;
	if(actions->applet != nullptr)
		actions->reopenAnswersDuringRun.push_back(actions->applet->ShouldHandleReopen(false, 0, 0));
	if( (actions->applet != nullptr) && (actions->urlsToOpenDuringRun != nullptr) )
	{
		// A command that waits in a nested run loop (a modal dialog, WaitPass) while another drop arrives
		CFArrayRef urls = actions->urlsToOpenDuringRun;
		actions->urlsToOpenDuringRun = nullptr;
		actions->applet->OpenURLs(urls);
		RunRunLoop(0.6);
	}
	actions->runDepth--;
	return actions->mainStatus;
}

void RecordURL(void *inContext, CFStringRef inURL)
{
	((RecordedActions *)inContext)->calls.push_back("url:" + Describe(inURL));
}

void RecordRecent(void *inContext, CFURLRef inFileURL)
{
	((RecordedActions *)inContext)->calls.push_back("recent:" + Describe(inFileURL));
}

void RecordOpened(void *inContext)
{
	((RecordedActions *)inContext)->calls.push_back("opened");
}

OMCAppletActions MakeActions(RecordedActions &ioRecorded)
{
	OMCAppletActions actions;
	actions.runMainCommand = RecordMain;
	actions.runURL = RecordURL;
	actions.noteRecentDocument = RecordRecent;
	actions.didOpenGatheredFiles = RecordOpened;
	actions.context = &ioRecorded;
	return actions;
}

void RunRunLoop(NSTimeInterval inSeconds)
{
	NSDate *until = [NSDate dateWithTimeIntervalSinceNow:inSeconds];
	while([until timeIntervalSinceNow] > 0)
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}

NSArray<NSString *> *CallList(const RecordedActions &inRecorded)
{
	NSMutableArray<NSString *> *list = [NSMutableArray array];
	for(const std::string &call : inRecorded.calls)
		[list addObject:@(call.c_str())];
	return list;
}

CFArrayRef URLs(NSArray<NSURL *> *inURLs)
{
	return (__bridge CFArrayRef)inURLs;
}

} // namespace

@interface OMCAppletTests : XCTestCase
@end

@implementation OMCAppletTests

- (void)testOptionAtStartupOpensNothingUntilTheLaunchHasFinished
{
	RecordedActions recorded;
	OMCApplet applet(MakeActions(recorded));
	applet.SetStartupModifiers(kOMCModifierOption | kOMCModifierShift);
	XCTAssertFalse(applet.OpenUntitled());
	applet.OpenURLs(URLs(@[ [NSURL fileURLWithPath:@"/tmp/a.txt"] ]));
	RunRunLoop(0.5);
	XCTAssertEqualObjects(CallList(recorded), (@[]));

	// New and Open, and a URL, are not affected
	applet.RunMainCommand();
	applet.HandleURL(CFSTR("omc://x"));
	XCTAssertEqualObjects(CallList(recorded), (@[ @"main:", @"url:omc://x" ]));

	applet.DidFinishLaunching();
	XCTAssertTrue(applet.OpenUntitled());
	applet.OpenURLs(URLs(@[ [NSURL fileURLWithPath:@"/tmp/a.txt"] ]));
	RunRunLoop(0.5);
	XCTAssertEqualObjects(CallList(recorded), (@[ @"main:", @"url:omc://x", @"main:", @"recent:/tmp/a.txt", @"main:/tmp/a.txt", @"opened" ]));
}

- (void)testOtherModifiersAtStartupDoNotSuppress
{
	RecordedActions recorded;
	OMCApplet applet(MakeActions(recorded));
	applet.SetStartupModifiers(kOMCModifierShift | kOMCModifierCommand | kOMCModifierControl);
	XCTAssertTrue(applet.OpenUntitled());
	XCTAssertEqualObjects(CallList(recorded), (@[ @"main:" ]));
}

- (void)testUntitledReportsWhetherTheCommandRan
{
	RecordedActions recorded;
	recorded.mainStatus = paramErr;
	OMCApplet applet(MakeActions(recorded));
	XCTAssertFalse(applet.OpenUntitled());
	XCTAssertEqualObjects(CallList(recorded), (@[ @"main:" ]));
}

- (void)testOpenedURLsAreGatheredFilteredAndOpenedOnce
{
	RecordedActions recorded;
	OMCApplet applet(MakeActions(recorded));
	applet.OpenURLs(URLs(@[ [NSURL fileURLWithPath:@"/tmp/a.txt"] ]));
	RunRunLoop(0.1);
	applet.OpenURLs(URLs(@[ [NSURL URLWithString:@"omc://exe?commandID=x"], [NSURL fileURLWithPath:@"/tmp/b.txt"] ]));
	RunRunLoop(0.1);
	XCTAssertEqualObjects(CallList(recorded), (@[]), @"still gathering: each call restarts the 0.25 s");
	RunRunLoop(0.4);
	XCTAssertEqualObjects(CallList(recorded), (@[ @"recent:/tmp/a.txt", @"recent:/tmp/b.txt", @"main:/tmp/a.txt,/tmp/b.txt", @"opened" ]));

	// A later drop is a new run
	applet.OpenURLs(URLs(@[ [NSURL fileURLWithPath:@"/tmp/c.txt"] ]));
	RunRunLoop(0.5);
	XCTAssertEqual(recorded.calls.size(), 7u);
	XCTAssertEqualObjects(CallList(recorded).lastObject, @"opened");
}

- (void)testURLsThatAreNotFilesAreLeftToHandleURL
{
	RecordedActions recorded;
	OMCApplet applet(MakeActions(recorded));
	applet.OpenURLs(URLs(@[ [NSURL URLWithString:@"omc://exe?commandID=x"], [NSURL URLWithString:@"https://example.com/"] ]));
	applet.OpenURLs(URLs(@[]));
	applet.OpenURLs(nullptr);
	RunRunLoop(0.5);
	XCTAssertEqualObjects(CallList(recorded), (@[]));
}

- (void)testADropDuringTheGatheredRunWaitsForItToReturn
{
	// The gathering used to be a main-queue block, which does not run inside another main-queue
	// block's nested run loop: files dropped while the gathered run's command waits open after it
	RecordedActions recorded;
	OMCApplet applet(MakeActions(recorded));
	recorded.applet = &applet;
	NSArray<NSURL *> *second __attribute__((objc_precise_lifetime)) = @[ [NSURL fileURLWithPath:@"/tmp/b.txt"] ]; // urlsToOpenDuringRun does not retain it
	recorded.urlsToOpenDuringRun = URLs(second);
	applet.OpenURLs(URLs(@[ [NSURL fileURLWithPath:@"/tmp/a.txt"] ]));
	RunRunLoop(1.5);
	XCTAssertEqual(recorded.deepestRun, 1, @"no main command inside another");
	XCTAssertEqualObjects(CallList(recorded), (@[ @"recent:/tmp/a.txt", @"main:/tmp/a.txt", @"opened",
												  @"recent:/tmp/b.txt", @"main:/tmp/b.txt", @"opened" ]));
}

- (void)testANonFileCallDoesNotCancelGatheredFiles
{
	RecordedActions recorded;
	OMCApplet applet(MakeActions(recorded));
	applet.OpenURLs(URLs(@[ [NSURL fileURLWithPath:@"/tmp/a.txt"] ]));
	applet.OpenURLs(URLs(@[ [NSURL URLWithString:@"https://example.com/"] ]));
	RunRunLoop(0.5);
	XCTAssertEqualObjects(CallList(recorded), (@[ @"recent:/tmp/a.txt", @"main:/tmp/a.txt", @"opened" ]));
}

- (void)testDestroyingTheAppletCancelsGathering
{
	RecordedActions recorded;
	{
		OMCApplet applet(MakeActions(recorded));
		applet.OpenURLs(URLs(@[ [NSURL fileURLWithPath:@"/tmp/a.txt"] ]));
	}
	RunRunLoop(0.5);
	XCTAssertEqualObjects(CallList(recorded), (@[]));
}

- (void)testOpenFileAndOpenFilesNoteThenRun
{
	RecordedActions recorded;
	OMCApplet applet(MakeActions(recorded));
	applet.OpenFile((__bridge CFURLRef)[NSURL fileURLWithPath:@"/tmp/a.txt"]);
	applet.OpenFiles(URLs(@[ [NSURL fileURLWithPath:@"/tmp/b.txt"], [NSURL fileURLWithPath:@"/tmp/c.txt"] ]));
	applet.OpenFiles(nullptr);
	applet.HandleURL(nullptr);
	XCTAssertEqualObjects(CallList(recorded), (@[ @"recent:/tmp/a.txt", @"main:/tmp/a.txt",
												  @"recent:/tmp/b.txt", @"recent:/tmp/c.txt", @"main:/tmp/b.txt,/tmp/c.txt" ]));
}

- (void)testReopenRules
{
	RecordedActions recorded;
	OMCApplet applet(MakeActions(recorded));
	XCTAssertTrue(applet.ShouldHandleReopen(false, 0, 0), @"nothing open: run again");
	XCTAssertFalse(applet.ShouldHandleReopen(true, 0, 0), @"the system sees a visible window");
	XCTAssertFalse(applet.ShouldHandleReopen(false, 1, 0), @"a hosted window is open");
	XCTAssertFalse(applet.ShouldHandleReopen(false, 0, 2), @"an app window is open");
	XCTAssertFalse(applet.ShouldHandleReopen(false, 0, -1), @"not known counts as open");
	XCTAssertEqualObjects(CallList(recorded), (@[]), @"the answer runs nothing itself");
}

- (void)testNoReopenWhileACommandIsStarting
{
	RecordedActions recorded;
	OMCApplet applet(MakeActions(recorded));
	recorded.applet = &applet;
	applet.RunMainCommand();
	(void)applet.OpenUntitled();
	applet.OpenFile((__bridge CFURLRef)[NSURL fileURLWithPath:@"/tmp/a.txt"]);
	applet.OpenFiles(URLs(@[ [NSURL fileURLWithPath:@"/tmp/b.txt"] ]));
	XCTAssertEqual(recorded.reopenAnswersDuringRun.size(), 4u);
	for(bool answer : recorded.reopenAnswersDuringRun)
		XCTAssertFalse(answer);
	XCTAssertTrue(applet.ShouldHandleReopen(false, 0, 0), @"and again once the calls returned");
}

@end

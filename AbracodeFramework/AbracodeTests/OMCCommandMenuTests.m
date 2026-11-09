//
//  OMCCommandMenuTests.m
//  AbracodeTests
//
//  The app's Commands menu (OMCCommandMenu over the portable OMCMenuModel): which commands it
//  shows, under which submenus, with which titles, and which command an item runs. The menu reads
//  its command file the way the runner does, so an absolute path to a test file stands in for the
//  applet's Command.plist.
//

#import <XCTest/XCTest.h>
#import "OMCCommandMenu.h"
#import "OMCMenuItem.h"

@interface OMCCommandMenuTests : XCTestCase
@property (nonatomic, strong) NSURL *workFolder;
@end

@implementation OMCCommandMenuTests

- (void)setUp
{
	[super setUp];
	NSString *name = [NSString stringWithFormat:@"OMCCommandMenuTests-%@", [NSUUID UUID].UUIDString];
	self.workFolder = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name] isDirectory:YES];
	[[NSFileManager defaultManager] createDirectoryAtURL:self.workFolder withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
	[[NSFileManager defaultManager] removeItemAtURL:self.workFolder error:NULL];
	[super tearDown];
}

// A command that writes its marker into the work folder, so a test sees which command ran
- (NSDictionary *)command:(id)inName marker:(NSString *)inMarker extra:(NSDictionary *)inExtra
{
	NSString *markerPath = [self.workFolder.path stringByAppendingPathComponent:@"ran.txt"];
	NSMutableDictionary *command = [@{
		@"NAME": inName,
		@"EXECUTION_MODE": @"exe_silent_popen",
		@"COMMAND": @[[NSString stringWithFormat:@"/bin/echo %@ >> '%@'", inMarker, markerPath]],
	} mutableCopy];
	[command addEntriesFromDictionary:inExtra];
	return command;
}

- (NSString *)writeCommandFile:(NSArray<NSDictionary *> *)inCommands
{
	NSURL *fileURL = [self.workFolder URLByAppendingPathComponent:@"Command.plist"];
	NSDictionary *description = @{ @"VERSION": @2, @"COMMAND_LIST": inCommands };
	NSError *error = nil;
	BOOL written = [description writeToURL:fileURL error:&error];
	XCTAssertTrue(written, @"%@", error);
	return fileURL.path;
}

- (OMCCommandMenu *)menuForCommandFile:(NSString *)inPath
{
	OMCCommandMenu *menu = [[OMCCommandMenu alloc] initWithTitle:@"Commands"];
	menu.commandFilePath = inPath;
	[menu populateFromCommandFile];
	return menu;
}

// The menu as text: one line per item, nested items indented, a submenu's title followed by ">"
static void DescribeMenu(NSMenu *inMenu, NSString *inIndent, NSMutableArray<NSString *> *outLines)
{
	for (NSMenuItem *item in inMenu.itemArray)
	{
		if (item.hasSubmenu)
		{
			[outLines addObject:[NSString stringWithFormat:@"%@%@ >", inIndent, item.title]];
			DescribeMenu(item.submenu, [inIndent stringByAppendingString:@"  "], outLines);
		}
		else
		{
			[outLines addObject:[NSString stringWithFormat:@"%@%@", inIndent, item.title]];
		}
	}
}

static NSArray<NSString *> *MenuLines(NSMenu *inMenu)
{
	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	DescribeMenu(inMenu, @"", lines);
	return lines;
}

static OMCMenuItem *FindItem(NSMenu *inMenu, NSString *inTitle)
{
	for (NSMenuItem *item in inMenu.itemArray)
	{
		if (item.hasSubmenu)
		{
			OMCMenuItem *found = FindItem(item.submenu, inTitle);
			if (found != nil)
				return found;
		}
		else if ([item.title isEqualToString:inTitle] && [item isKindOfClass:[OMCMenuItem class]])
		{
			return (OMCMenuItem *)item;
		}
	}
	return nil;
}

// Runs the run loop until the marker file holds a line, or 5 seconds pass
- (NSString *)waitForMarker
{
	NSString *markerPath = [self.workFolder.path stringByAppendingPathComponent:@"ran.txt"];
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
	while ([deadline timeIntervalSinceNow] > 0)
	{
		NSString *text = [NSString stringWithContentsOfFile:markerPath encoding:NSUTF8StringEncoding error:NULL];
		if ([text hasSuffix:@"\n"])
			return [text stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
	}
	return nil;
}

- (void)testItemsSubmenusAndTitles
{
	NSString *path = [self writeCommandFile:@[
		[self command:@"Alpha" marker:@"alpha" extra:@{ @"COMMAND_ID": @"alpha.id" }],
		[self command:@"Beta" marker:@"beta" extra:@{}],
		// Same NAME as an earlier command: a subcommand, not in the menu
		[self command:@"Beta" marker:@"beta.sub" extra:@{ @"COMMAND_ID": @"beta.sub" }],
		[self command:@"Hidden" marker:@"hidden" extra:@{ @"DISABLED": @YES }],
		[self command:@"InGroup" marker:@"x" extra:@{ @"SUBMENU_NAME": @"Group" }],
		[self command:@"Nested" marker:@"x" extra:@{ @"SUBMENU_NAME": @"/Group/Inner" }],
		[self command:@"Root" marker:@"x" extra:@{ @"SUBMENU_NAME": @".." }],
		[self command:@"Dot" marker:@"x" extra:@{ @"SUBMENU_NAME": @".dot" }],
		// NAME parts are joined as written; dynamic parts are not resolved in this menu
		[self command:@[@"Part ", @"Two"] marker:@"x" extra:@{}],
		// A table that does not exist gives the name back
		[self command:@"Localized" marker:@"x" extra:@{ @"LOCALIZATION_TABLE_NAME": @"NoSuchTable" }],
		[self command:@"Grouped Again" marker:@"x" extra:@{ @"SUBMENU_NAME": @"Group/" }],
		// Kept quirk: an empty component ends the walk, so only the last submenu is made
		[self command:@"Double" marker:@"x" extra:@{ @"SUBMENU_NAME": @"/C//D" }],
		// A "." or ".." component ends the walk too (it used to recurse until the app crashed)
		[self command:@"Up" marker:@"x" extra:@{ @"SUBMENU_NAME": @"A/../B" }],
		[self command:@"Here" marker:@"x" extra:@{ @"SUBMENU_NAME": @"./E" }],
	]];
	OMCCommandMenu *menu = [self menuForCommandFile:path];

	NSArray<NSString *> *expected = @[
		@"Alpha",
		@"Beta",
		@"Group >",
		@"  InGroup",
		@"  Inner >",
		@"    Nested",
		@"  Grouped Again",
		@"Root",
		@".dot >",
		@"  Dot",
		@"Part Two",
		@"Localized",
		@"D >",
		@"  Double",
		@"B >",
		@"  Up",
		@"E >",
		@"  Here",
	];
	XCTAssertEqualObjects(MenuLines(menu), expected);

	OMCMenuItem *alpha = FindItem(menu, @"Alpha");
	XCTAssertEqualObjects(alpha.commandID, @"alpha.id");
	XCTAssertEqualObjects(alpha.representedObject, @"Alpha");
	XCTAssertEqual(alpha.target, menu);
	XCTAssertEqual(alpha.action, @selector(executeCommand:));

	OMCMenuItem *beta = FindItem(menu, @"Beta");
	XCTAssertEqualObjects(beta.commandID, @"top!", @"a command without an id of its own");
	XCTAssertEqualObjects(beta.representedObject, @"Beta");

	OMCMenuItem *nested = FindItem(menu, @"Nested");
	XCTAssertEqual(nested.target, menu, @"items in submenus target the Commands menu too");
}

- (void)testPopulatingAgainReplacesTheItems
{
	NSString *path = [self writeCommandFile:@[ [self command:@"Only" marker:@"x" extra:@{ @"SUBMENU_NAME": @"Group" }] ]];
	OMCCommandMenu *menu = [self menuForCommandFile:path];
	[menu populateFromCommandFile];
	XCTAssertEqualObjects(MenuLines(menu), (@[ @"Group >", @"  Only" ]));
}

- (void)testNoCommandFileGivesAnEmptyMenu
{
	OMCCommandMenu *menu = [[OMCCommandMenu alloc] initWithTitle:@"Commands"];
	[menu addItemWithTitle:@"Placeholder" action:NULL keyEquivalent:@""];
	menu.commandFilePath = [self.workFolder.path stringByAppendingPathComponent:@"Missing.plist"];
	[menu populateFromCommandFile];
	XCTAssertEqual(menu.numberOfItems, 0, @"the placeholder is removed and nothing is added");
}

- (void)testAnItemWithItsOwnIdRunsThatCommand
{
	NSString *path = [self writeCommandFile:@[
		[self command:@"Alpha" marker:@"alpha" extra:@{ @"COMMAND_ID": @"alpha.id" }],
		[self command:@"Other" marker:@"other" extra:@{ @"COMMAND_ID": @"other.id" }],
	]];
	OMCCommandMenu *menu = [self menuForCommandFile:path];
	OMCMenuItem *alpha = FindItem(menu, @"Alpha");
	alpha.representedObject = @"Other"; // the id wins over the name
	[menu executeCommand:alpha];
	XCTAssertEqualObjects([self waitForMarker], @"alpha");
}

- (void)testAnItemWithoutAnIdRunsTheCommandByItsName
{
	NSString *path = [self writeCommandFile:@[
		[self command:@"Alpha" marker:@"alpha" extra:@{ @"COMMAND_ID": @"alpha.id" }],
		[self command:@"Beta" marker:@"beta" extra:@{}],
	]];
	OMCCommandMenu *menu = [self menuForCommandFile:path];
	[menu executeCommand:FindItem(menu, @"Beta")];
	XCTAssertEqualObjects([self waitForMarker], @"beta", @"\"top!\" is no id of its own: the name is used");
}

- (void)testANibItemWithAnEmptyIdRunsByItsRepresentedName
{
	NSString *path = [self writeCommandFile:@[
		[self command:@"Alpha" marker:@"alpha" extra:@{ @"COMMAND_ID": @"alpha.id" }],
		[self command:@"Beta" marker:@"beta" extra:@{}],
	]];
	OMCCommandMenu *menu = [self menuForCommandFile:path];
	OMCMenuItem *item = [[OMCMenuItem alloc] initWithTitle:@"Anything" action:@selector(executeCommand:) keyEquivalent:@""];
	item.commandID = @"";
	item.representedObject = @"Beta";
	[menu executeCommand:item];
	XCTAssertEqualObjects([self waitForMarker], @"beta");
}

@end

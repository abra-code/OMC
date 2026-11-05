//
//  OMCProgressParsingTests.mm
//  AbracodeTests
//
//  Unit tests for SplitStringIntoLines in OMCProgressParsing.cpp, the portable half of PROGRESS
//  (the window half is covered by OMCProgressTests). Not exported from Abracode.framework, so the
//  source compiles into this bundle.
//

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>

#include "../OMCProgressParsing.cpp"

@interface OMCProgressParsingTests : XCTestCase
@end

@implementation OMCProgressParsingTests

// Feeds the chunks in order, as a task's output arrives, and returns every line produced.
static NSArray<NSString *> *SplitChunks(NSArray<NSString *> *chunks, NSString **outLeftOver)
{
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    CFObj<CFStringRef> leftOver;
    for(NSString *chunk in chunks)
    {
        CFObj<CFArrayRef> produced( SplitStringIntoLines((__bridge CFStringRef)chunk, leftOver) );
        if(produced != NULL)
            [lines addObjectsFromArray:(__bridge NSArray *)produced.Get()];
    }
    *outLeftOver = (__bridge NSString *)leftOver.Get();
    return lines;
}

- (void)testWholeLinesAndAPartialLine
{
    NSString *leftOver = nil;
    NSArray *lines = SplitChunks(@[@"one\ntwo\r\nthree"], &leftOver);
    XCTAssertEqualObjects(lines, (@[@"one", @"two"]));
    XCTAssertEqualObjects(leftOver, @"three");
}

- (void)testPartialLineJoinsTheNextChunk
{
    NSString *leftOver = nil;
    NSArray *lines = SplitChunks(@[@"10", @"% done\n20", @"% done\n"], &leftOver);
    XCTAssertEqualObjects(lines, (@[@"10% done", @"20% done"]));
    XCTAssertNil(leftOver);
}

// A chunk of only line breaks completes the left-over line. Before the fix it was lost (and the
// array that held it leaked), so a script printing a blank line after a status lost that status.
- (void)testChunkOfOnlyLineBreaksCompletesTheLeftOver
{
    NSString *leftOver = nil;
    NSArray *lines = SplitChunks(@[@"50% done", @"\n", @"next\n"], &leftOver);
    XCTAssertEqualObjects(lines, (@[@"50% done", @"next"]));
    XCTAssertNil(leftOver);
}

// An empty chunk (the end of output) flushes the left-over line.
- (void)testEmptyChunkFlushesTheLeftOver
{
    NSString *leftOver = nil;
    NSArray *lines = SplitChunks(@[@"last", @""], &leftOver);
    XCTAssertEqualObjects(lines, (@[@"last"]));
    XCTAssertNil(leftOver);
}

@end

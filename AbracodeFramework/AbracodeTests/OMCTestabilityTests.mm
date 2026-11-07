//
//  OMCTestabilityTests.mm
//  AbracodeTests
//
//  Which builds may serve the integration-test surface (Platform/OMCTestability.h): the rule on its
//  own, and the reading of real signatures, made here with codesign on copies of a system binary,
//  one for each way an applet can be signed.
//
//  The functions are not exported from Abracode.framework, so the macOS source compiles into this
//  bundle, as the other tests of internal code do.
//

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <mach-o/fat.h>
#include <libkern/OSByteOrder.h>
#include "OMCTestabilityApple.h"
#include "../Platform/Apple/OMCTestability.mm"

@interface OMCTestabilityTests : XCTestCase
@end

@implementation OMCTestabilityTests
{
	NSURL *mWorkDir;
}

- (void)setUp
{
	[super setUp];
	NSString *name = [NSString stringWithFormat:@"OMCTestabilityTests-%@", [[NSUUID UUID] UUIDString]];
	mWorkDir = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:name isDirectory:YES];
	NSError *error = nil;
	XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:mWorkDir withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);
}

- (void)tearDown
{
	if(mWorkDir != nil)
		[[NSFileManager defaultManager] removeItemAtURL:mWorkDir error:nil];
	[super tearDown];
}

#pragma mark - The rule

- (void)testTheRuleTable
{
	const uint32_t runtime = kSecCodeSignatureRuntime;
	const uint32_t library = kSecCodeSignatureLibraryValidation;
	const uint32_t restrictFlag = kSecCodeSignatureRestrict;
	const uint32_t adhoc = kSecCodeSignatureAdhoc;

	// Signed for local use: ad hoc or self-signed without hardening.
	XCTAssertEqual(OMCDecideTestSurfaceStatus(true, false, false, adhoc), kOMCTestSurface_Allowed);
	XCTAssertEqual(OMCDecideTestSurfaceStatus(true, false, false, 0), kOMCTestSurface_Allowed);
	// Each injection-blocking flag on its own refuses.
	XCTAssertEqual(OMCDecideTestSurfaceStatus(true, false, false, adhoc | runtime), kOMCTestSurface_Hardened);
	XCTAssertEqual(OMCDecideTestSurfaceStatus(true, false, false, adhoc | library), kOMCTestSurface_Hardened);
	XCTAssertEqual(OMCDecideTestSurfaceStatus(true, false, false, adhoc | restrictFlag), kOMCTestSurface_Hardened);
	// A debug build is allowed even when hardened.
	XCTAssertEqual(OMCDecideTestSurfaceStatus(true, false, true, runtime | library), kOMCTestSurface_Allowed);
	// A distribution certificate refuses whatever else is true.
	XCTAssertEqual(OMCDecideTestSurfaceStatus(true, true, true, 0), kOMCTestSurface_DistributionSigned);
	XCTAssertEqual(OMCDecideTestSurfaceStatus(true, true, false, runtime), kOMCTestSurface_DistributionSigned);
	// An invalid signature refuses before anything else is looked at.
	XCTAssertEqual(OMCDecideTestSurfaceStatus(false, false, true, adhoc), kOMCTestSurface_NoValidSignature);
	XCTAssertEqual(OMCDecideTestSurfaceStatus(false, true, false, 0), kOMCTestSurface_NoValidSignature);
}

- (void)testEveryStatusHasADescription
{
	const OMCTestSurfaceStatus all[] = { kOMCTestSurface_Allowed, kOMCTestSurface_NoValidSignature, kOMCTestSurface_DistributionSigned,
										kOMCTestSurface_Hardened, kOMCTestSurface_NotInThisBuild };
	for(OMCTestSurfaceStatus status : all)
	{
		const char *text = OMCGetTestSurfaceStatusDescription(status);
		XCTAssertTrue((text != nullptr) && (strlen(text) > 0));
		XCTAssertEqual(strncmp(text, (status == kOMCTestSurface_Allowed) ? "allowed" : "refused", 7), 0, @"%s", text);
	}
}

#pragma mark - Real signatures

// Runs a tool and fails the test, with its output, when it does not exit 0.
- (BOOL)run:(NSString *)inTool arguments:(NSArray<NSString *> *)inArguments
{
	NSTask *task = [[NSTask alloc] init];
	task.executableURL = [NSURL fileURLWithPath:inTool];
	task.arguments = inArguments;
	NSPipe *output = [NSPipe pipe];
	task.standardOutput = output;
	task.standardError = output;
	NSError *error = nil;
	if(![task launchAndReturnError:&error])
	{
		XCTFail(@"%@ did not start: %@", inTool, error);
		return NO;
	}
	NSData *data = [[output fileHandleForReading] readDataToEndOfFile];
	[task waitUntilExit];
	if(task.terminationStatus != 0)
	{
		NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		XCTFail(@"%@ %@ exited %d: %@", inTool, [inArguments componentsJoinedByString:@" "], task.terminationStatus, text);
		return NO;
	}
	return YES;
}

// A private copy of a system binary, so it can be re-signed. /usr/bin/true is small and on every Mac.
- (NSString *)copyOfABinaryNamed:(NSString *)inName
{
	NSString *path = [[mWorkDir URLByAppendingPathComponent:inName] path];
	NSError *error = nil;
	XCTAssertTrue([[NSFileManager defaultManager] copyItemAtPath:@"/usr/bin/true" toPath:path error:&error], @"%@", error);
	return path;
}

- (NSString *)signedCopyNamed:(NSString *)inName withArguments:(NSArray<NSString *> *)inArguments
{
	NSString *path = [self copyOfABinaryNamed:inName];
	NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObjects:@"--force", @"--sign", @"-", nil];
	[arguments addObjectsFromArray:inArguments];
	[arguments addObject:path];
	if(![self run:@"/usr/bin/codesign" arguments:arguments])
		return nil;
	return path;
}

- (NSString *)entitlementsWithGetTaskAllow
{
	NSString *path = [[mWorkDir URLByAppendingPathComponent:@"debug.entitlements"] path];
	NSDictionary *entitlements = @{ @"com.apple.security.get-task-allow": @YES };
	NSError *error = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:entitlements format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
	XCTAssertNotNil(data, @"%@", error);
	XCTAssertTrue([data writeToFile:path atomically:YES]);
	return path;
}

- (void)testAdHocWithoutHardeningIsAllowed
{
	NSString *path = [self signedCopyNamed:@"adhoc" withArguments:@[]];
	XCTAssertNotNil(path);
	XCTAssertEqual(OMCGetTestSurfaceStatusForCodeAtPath([path fileSystemRepresentation]), kOMCTestSurface_Allowed);
}

- (void)testTheHardenedRuntimeRefuses
{
	NSString *path = [self signedCopyNamed:@"runtime" withArguments:@[ @"--options", @"runtime" ]];
	XCTAssertNotNil(path);
	XCTAssertEqual(OMCGetTestSurfaceStatusForCodeAtPath([path fileSystemRepresentation]), kOMCTestSurface_Hardened);
}

- (void)testLibraryValidationAloneRefuses
{
	NSString *path = [self signedCopyNamed:@"library" withArguments:@[ @"--options", @"library" ]];
	XCTAssertNotNil(path);
	XCTAssertEqual(OMCGetTestSurfaceStatusForCodeAtPath([path fileSystemRepresentation]), kOMCTestSurface_Hardened);
}

- (void)testGetTaskAllowIsAllowedEvenWhenHardened
{
	NSString *entitlements = [self entitlementsWithGetTaskAllow];
	NSString *path = [self signedCopyNamed:@"debug" withArguments:@[ @"--options", @"runtime", @"--entitlements", entitlements ]];
	XCTAssertNotNil(path);
	XCTAssertEqual(OMCGetTestSurfaceStatusForCodeAtPath([path fileSystemRepresentation]), kOMCTestSurface_Allowed);
}

- (void)testAppleSignedCodeIsDistributionSigned
{
	// The original, signed by Apple: what an App Store or Apple-signed host would look like.
	XCTAssertEqual(OMCGetTestSurfaceStatusForCodeAtPath("/usr/bin/true"), kOMCTestSurface_DistributionSigned);
}

- (void)testUnsignedCodeRefuses
{
	NSString *path = [self signedCopyNamed:@"unsigned" withArguments:@[]];
	XCTAssertNotNil(path);
	BOOL removed = [self run:@"/usr/bin/codesign" arguments:@[ @"--remove-signature", path ]];
	XCTAssertTrue(removed);
	XCTAssertEqual(OMCGetTestSurfaceStatusForCodeAtPath([path fileSystemRepresentation]), kOMCTestSurface_NoValidSignature);
}

- (void)testAModifiedBinaryRefuses
{
	NSString *path = [self signedCopyNamed:@"modified" withArguments:@[]];
	XCTAssertNotNil(path);

	// Flip one byte in the middle of every architecture, which is either hashed code or the signature
	// itself. Every one, because a universal binary is validated for the architecture that would run
	// here; and not the middle of the file, which can be padding between architectures that nothing
	// covers. A fat header is big-endian: nfat_arch at byte 4, then 20-byte fat_arch records whose
	// offset and size are at bytes 8 and 12.
	NSMutableData *bytes = [NSMutableData dataWithContentsOfFile:path];
	XCTAssertGreaterThan(bytes.length, (NSUInteger)64);
	uint8_t *raw = (uint8_t *)bytes.mutableBytes;
	if(OSReadBigInt32(raw, 0) == FAT_MAGIC)
	{
		uint32_t count = OSReadBigInt32(raw, 4);
		XCTAssertGreaterThan(count, 0U);
		XCTAssertLessThan(8 + (size_t)count * sizeof(struct fat_arch), bytes.length);
		for(uint32_t i = 0; i < count; i++)
		{
			size_t record = 8 + (size_t)i * sizeof(struct fat_arch);
			size_t target = (size_t)OSReadBigInt32(raw, record + 8) + ((size_t)OSReadBigInt32(raw, record + 12) / 2);
			XCTAssertLessThan(target, bytes.length);
			if(target < bytes.length)
				raw[target] ^= 0xFF;
		}
	}
	else
	{
		raw[bytes.length / 2] ^= 0xFF;
	}
	XCTAssertTrue([bytes writeToFile:path atomically:NO]);
	XCTAssertEqual(OMCGetTestSurfaceStatusForCodeAtPath([path fileSystemRepresentation]), kOMCTestSurface_NoValidSignature);
}

- (void)testAMissingPathRefuses
{
	XCTAssertEqual(OMCGetTestSurfaceStatusForCodeAtPath(nullptr), kOMCTestSurface_NoValidSignature);
	XCTAssertEqual(OMCGetTestSurfaceStatusForCodeAtPath(""), kOMCTestSurface_NoValidSignature);
	NSString *missing = [[mWorkDir URLByAppendingPathComponent:@"missing"] path];
	XCTAssertEqual(OMCGetTestSurfaceStatusForCodeAtPath([missing fileSystemRepresentation]), kOMCTestSurface_NoValidSignature);
}

#pragma mark - This process

- (void)testThisProcessGetsOneAnswer
{
	// The test runner's own signature decides this, so the value itself is not pinned, only that it
	// is one of the statuses and does not change.
	OMCTestSurfaceStatus first = OMCGetTestSurfaceStatus();
	XCTAssertEqual(OMCGetTestSurfaceStatus(), first);
	XCTAssertNotEqual(first, kOMCTestSurface_NotInThisBuild, @"macOS reads the signature; only Linux leaves it out at build time");
	NSLog(@"OMCTestabilityTests: this process: %s", OMCGetTestSurfaceStatusDescription(first));
}

@end

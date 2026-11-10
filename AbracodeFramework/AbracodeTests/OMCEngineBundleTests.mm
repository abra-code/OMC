//
//  OMCEngineBundleTests.mm
//  AbracodeTests
//
//  OMCGetEngineBundle (Platform/OMCEngineBundle.h): the engine's own bundle, the one way the engine
//  finds Abracode.framework's Info.plist, localized strings and built-in documents. The macOS source
//  is compiled into the test bundle (it is not exported from Abracode.framework).
//

#import <XCTest/XCTest.h>
#include "OMCEngineBundle.h"
#include "../Platform/Apple/OMCEngineBundle.cpp"

@interface OMCEngineBundleTests : XCTestCase
@end

@implementation OMCEngineBundleTests

- (void)testTheEngineBundleIsAbracodeFramework
{
    CFBundleRef bundle = OMCGetEngineBundle();
    XCTAssertTrue(bundle != NULL);
    if (bundle == NULL)
        return;
    XCTAssertEqualObjects((__bridge NSString *)CFBundleGetIdentifier(bundle), @OMC_ENGINE_BUNDLE_IDENTIFIER);
    XCTAssertTrue(OMCGetEngineBundle() == bundle, @"found once: the same bundle on every call");

    // What the engine reads from it: the version and the private strings
    CFTypeRef version = CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleVersionKey);
    XCTAssertTrue((version != NULL) && (CFGetTypeID(version) == CFStringGetTypeID()));
    // A missing table returns the key itself, and English "Stop" is "Stop": check the table is there
    NSURL *privateStrings = CFBridgingRelease(CFBundleCopyResourceURL(bundle, CFSTR("Private"), CFSTR("strings"), NULL));
    XCTAssertNotNil(privateStrings);
    NSString *stop = CFBridgingRelease(CFCopyLocalizedStringFromTableInBundle(CFSTR("Stop"), CFSTR("Private"), bundle, ""));
    XCTAssertGreaterThan(stop.length, 0u);
}

@end

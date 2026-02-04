//
//  OMCTestCase.h
//  AbracodeTests
//

#import <XCTest/XCTest.h>

#if __has_feature(address_sanitizer)
    #define IS_ASAN_ENABLED true
    #define kDefaultExecutionTimeout 10.0
#else
    #define IS_ASAN_ENABLED false
    #define kDefaultExecutionTimeout 5.0
#endif

NS_ASSUME_NONNULL_BEGIN

@interface OMCTestCase : XCTestCase

// Subclasses override these to provide test-specific configuration
- (NSString *)testName;
- (NSDictionary *)testCommandDescription;

// Provided by base class after setup
@property (nonatomic, strong, readonly) NSURL *testPlistURL;
@property (nonatomic, strong, readonly) NSDictionary *testPlistDict;

// Helper to create temp files for testing
- (NSURL *)createTempFileWithName:(NSString *)name content:(NSString *)content;
- (void)cleanupTempFile:(NSURL *)fileURL;

@end

NS_ASSUME_NONNULL_END

//
//  OMCBundleTestHelper.h
//  AbracodeTests
//
//  Helper for managing .omc test bundles
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OMCBundleTestHelper : NSObject

/// Returns the test bundle directory containing .omc bundles
/// Looks in AbracodeTests.xctest/Contents/Resources/TestBundles/
+ (nullable NSURL *)testBundlesDirectory;

/// Return .omc builde URL in test .xctest bundle
/// @return URL to .omc  bundle in .xctest bundle resources, or nil if source not found
+ (nullable NSURL *)testBundleURL:(NSString *)bundleName;

/// Creates a minimal .omc bundle programmatically for simple tests
/// @param bundleName Name without .omc extension
/// @param commands Array of command dictionaries
/// @param scripts Dictionary mapping script filenames to content strings
+ (nullable NSURL *)createTestBundle:(NSString *)bundleName
                        withCommands:(NSArray<NSDictionary *> *)commands
                             scripts:(NSDictionary<NSString *, NSString *> *)scripts;

/// Removes a bundle from temp directory
+ (void)removeTestBundle:(NSURL *)bundleURL;

@end

NS_ASSUME_NONNULL_END

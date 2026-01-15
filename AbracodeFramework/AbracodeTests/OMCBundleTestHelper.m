//
//  OMCBundleTestHelper.m
//  AbracodeTests
//

#import "OMCBundleTestHelper.h"

@implementation OMCBundleTestHelper

+ (nullable NSURL *)testBundlesDirectory {
    // Get the test bundle itself (AbracodeTests.xctest)
    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    if (testBundle == nil) {
        NSLog(@"Failed to get test bundle");
        return nil;
    }
    
    // Look for TestBundles directory in Resources
    NSURL *resourcesURL = [testBundle resourceURL];
    NSURL *testBundlesURL = [resourcesURL URLByAppendingPathComponent:@"TestBundles"];
    
    return testBundlesURL;
}

+ (nullable NSURL *)testBundleURL:(NSString *)bundleName {
    NSURL *testBundlesDir = [self testBundlesDirectory];
    if (testBundlesDir == nil) {
        return nil;
    }
    NSString *fullBundleName = [bundleName stringByAppendingPathExtension:@"omc"];
    NSURL *omcBundleURL = [testBundlesDir URLByAppendingPathComponent:fullBundleName];

    // Check if bundle exists
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:[omcBundleURL path]];
    if (!exists) {
        return nil;
    }

    return omcBundleURL;
}

+ (nullable NSURL *)createTestBundle:(NSString *)bundleName
                        withCommands:(NSArray<NSDictionary *> *)commands
                             scripts:(NSDictionary<NSString *, NSString *> *)scripts {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Create bundle structure in temp directory
    NSString *fullBundleName = [bundleName stringByAppendingPathExtension:@"omc"];
    NSURL *bundleURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()] 
                        URLByAppendingPathComponent:fullBundleName];
    
    // Remove existing bundle
    [fm removeItemAtURL:bundleURL error:nil];
    
    // Create directory structure
    NSURL *contentsURL = [bundleURL URLByAppendingPathComponent:@"Contents"];
    NSURL *resourcesURL = [contentsURL URLByAppendingPathComponent:@"Resources"];
    NSURL *scriptsURL = [resourcesURL URLByAppendingPathComponent:@"Scripts"];
    
    NSError *error = nil;
    BOOL created = [fm createDirectoryAtURL:scriptsURL 
                withIntermediateDirectories:YES 
                                 attributes:nil 
                                      error:&error];
    if (!created) {
        NSLog(@"Failed to create bundle directories: %@", error);
        return nil;
    }
    
    // Create Command.plist
    NSDictionary *plist = @{
        @"VERSION": @2,
        @"COMMAND_LIST": commands
    };
    
    NSURL *plistURL = [resourcesURL URLByAppendingPathComponent:@"Command.plist"];
    BOOL plistWritten = [plist writeToURL:plistURL atomically:YES];
    if (!plistWritten) {
        NSLog(@"Failed to write Command.plist");
        return nil;
    }
    
    // Write script files
    for (NSString *scriptName in scripts) {
        NSString *scriptContent = scripts[scriptName];
        NSURL *scriptURL = [scriptsURL URLByAppendingPathComponent:scriptName];
        
        BOOL scriptWritten = [scriptContent writeToURL:scriptURL 
                                             atomically:YES 
                                               encoding:NSUTF8StringEncoding 
                                                  error:&error];
        if (!scriptWritten) {
            NSLog(@"Failed to write script %@: %@", scriptName, error);
            continue;
        }
    }
    
    return bundleURL;
}

+ (void)removeTestBundle:(NSURL *)bundleURL {
    [[NSFileManager defaultManager] removeItemAtURL:bundleURL error:nil];
}

@end

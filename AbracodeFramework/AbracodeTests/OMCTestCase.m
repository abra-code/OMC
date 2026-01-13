//
//  OMCTestCase.m
//  AbracodeTests
//

#import "OMCTestCase.h"

@interface OMCTestCase ()
@property (nonatomic, strong, readwrite) NSURL *testPlistURL;
@property (nonatomic, strong, readwrite) NSDictionary *testPlistDict;
@property (nonatomic, strong) NSMutableSet<NSURL *> *tempFiles;
@end

@implementation OMCTestCase

- (void)setUp {
    [super setUp];
    
    self.tempFiles = [NSMutableSet set];
    
    // Get configuration from subclass
    NSString *testName = [self testName];
    self.testPlistDict = [self testCommandDescription];
    
    // Create test plist in temp directory in subdir with testName
    NSString *tempDirPath = NSTemporaryDirectory(); // tempdir
    NSString *testDirPath = [tempDirPath stringByAppendingPathComponent:testName]; // tempdir/TestName
    NSString *plistName = [NSString stringWithFormat:@"%@.plist", testName]; // tempdir/TestName/TestName.plist
    NSString *testPlistPath = [testDirPath stringByAppendingPathComponent:plistName];
    self.testPlistURL = [NSURL fileURLWithPath:testPlistPath isDirectory:NO];
    
    // Write plist to disk
    if (self.testPlistDict != nil) {
        NSError *error = nil;
        BOOL dirCreated = [[NSFileManager defaultManager] createDirectoryAtPath:testDirPath
                                                    withIntermediateDirectories:YES
                                                                     attributes:nil
                                                                          error:&error];

        if (!dirCreated) {
                NSLog(@"Error creating directory: %@", error.localizedDescription);
        }
        [self.testPlistDict writeToURL:self.testPlistURL atomically:YES];
        NSError *writeErr = nil;
        BOOL didWrite = [self.testPlistDict writeToURL:self.testPlistURL  error: &writeErr];
        if (!didWrite) {
            NSLog(@"Error writing plist to disk: %@", writeErr.localizedDescription);
        }
        XCTAssertTrue(didWrite);
    }
}

- (void)tearDown {
    // Clean up test plist
    if (self.testPlistURL != nil) {
        [[NSFileManager defaultManager] removeItemAtURL:self.testPlistURL error:nil];
    }
    
    // Clean up any temp files created during tests
    @synchronized(self.tempFiles) {
        for (NSURL *fileURL in self.tempFiles) {
            [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
        }
        [self.tempFiles removeAllObjects];
    }
    
    [super tearDown];
}

#pragma mark - Subclass Override Points

- (NSString *)testName {
    // Default implementation - subclasses should override
    return @"Test";
}

- (NSDictionary *)testCommandDescription {
    // Default implementation - subclasses should override
    return @{
        @"VERSION": @2,
        @"COMMAND_LIST": @[]
    };
}

#pragma mark - Helper Methods

- (NSURL *)createTempFileWithName:(NSString *)name content:(NSString *)content {
    NSURL *fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    [content writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    @synchronized(self.tempFiles) {
        [self.tempFiles addObject:fileURL];
    }
    
    return fileURL;
}

- (void)cleanupTempFile:(NSURL *)fileURL {
    [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
    
    @synchronized(self.tempFiles) {
        [self.tempFiles removeObject:fileURL];
    }
}

@end

//
//  OMCTestExecutionObserver.h
//  AbracodeTests
//
//  Observer for capturing OMC task execution results in tests
//

#import <Foundation/Foundation.h>
#import "OMCObserverDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@interface OMCTestExecutionObserver : NSObject <OMCObserverDelegate>

/// Accumulated output from all task progress messages
@property (nonatomic, strong, readonly) NSString *capturedOutput;

/// Whether all tasks have finished
@property (nonatomic, assign, readonly) BOOL allTasksFinished;

/// Whether any task was canceled
@property (nonatomic, assign, readonly) BOOL taskWasCanceled;

/// Number of tasks that finished
@property (nonatomic, assign, readonly) NSInteger finishedTaskCount;

/// Waits for all tasks to finish with a timeout
/// @param timeout Maximum time to wait in seconds
/// @return YES if tasks finished, NO if timed out
- (BOOL)waitForCompletionWithTimeout:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END

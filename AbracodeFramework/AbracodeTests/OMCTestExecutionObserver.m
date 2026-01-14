//
//  OMCTestExecutionObserver.m
//  AbracodeTests
//

#import "OMCTestExecutionObserver.h"

@interface OMCTestExecutionObserver ()
@property (nonatomic, assign) OMCObserverRef observer;
@property (nonatomic, strong) NSMutableString *mutableOutput;
@property (nonatomic, assign, readwrite) BOOL allTasksFinished;
@property (nonatomic, assign, readwrite) BOOL taskWasCanceled;
@property (nonatomic, assign, readwrite) NSInteger finishedTaskCount;
@end

@implementation OMCTestExecutionObserver

- (instancetype)init {
    self = [super init];
    if (self) {
        _observer = NULL;
        _mutableOutput = [[NSMutableString alloc] init];
        _allTasksFinished = NO;
        _taskWasCanceled = NO;
        _finishedTaskCount = 0;
    }
    return self;
}

- (void)dealloc {
    OMCUnregisterObserver(_observer);
    OMCReleaseObserver(_observer);
    _observer = NULL;
}

- (NSString *)capturedOutput {
    @synchronized(self) {
        return [self.mutableOutput copy];
    }
}

- (BOOL)waitForCompletionWithTimeout:(NSTimeInterval)timeout {
    NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:timeout];
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    
    while (!self.allTasksFinished && [timeoutDate timeIntervalSinceNow] > 0) {
        BOOL ranLoop = [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        if (!ranLoop) {
            // No sources to run, check condition and wait a bit
            if (self.allTasksFinished) {
                break;
            }
            [NSThread sleepForTimeInterval:0.01];
        }
    }
    
    return self.allTasksFinished;
}

#pragma mark - OMCObserverDelegate

- (void)setObserver:(OMCObserverRef)inObserver {
    @synchronized(self) {
    	OMCRetainObserver(inObserver);
        if (_observer != inObserver) {
            OMCUnregisterObserver(_observer);
        }
        OMCReleaseObserver(_observer);
        _observer = inObserver;
    }
}

- (void)receiveObserverMessage:(OmcObserverMessage)inMessage 
                     forTaskId:(CFIndex)inTaskID 
                      withData:(CFTypeRef)inResult {
    @synchronized(self) {
        switch (inMessage) {
            case kOmcObserverTaskFinished:
                self.finishedTaskCount++;
                break;
                
            case kOmcObserverTaskProgress: {
                if (inResult != NULL) {
                    id __weak objcObject = (__bridge id)inResult;
                    if ([objcObject isKindOfClass:[NSString class]]) {
                        [self.mutableOutput appendString:(NSString *)objcObject];
                    }
                }
                break;
            }
                
            case kOmcObserverTaskCanceled:
                self.taskWasCanceled = YES;
                break;
                
            case kOmcObserverAllTasksFinished:
                self.allTasksFinished = YES;
                [self setObserver: nil]; // Clean up observer
                break;
                
            default:
                break;
        }
    }
}

@end

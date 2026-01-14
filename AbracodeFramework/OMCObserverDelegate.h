//
//  OMCObserverDelegate.h
//  Abracode
//
//  Protocol for objects that want to observe OMC task execution
//

#import <Foundation/Foundation.h>
#include "OMC.h"

NS_ASSUME_NONNULL_BEGIN

@protocol OMCObserverDelegate <NSObject>

@required
/// Called when an observer message is received from OMC task execution
/// @param inMessage Type of observer message
/// @param inTaskID Task identifier
/// @param inResult Optional result data (may be NULL)
- (void)receiveObserverMessage:(OmcObserverMessage)inMessage 
                     forTaskId:(CFIndex)inTaskID 
                      withData:(nullable CFTypeRef)inResult;

/// Called by OMCCommandExecutor to set the observer reference after creation
/// Observer takes ownership, should retain OMCObserverRef and then release it
/// @param observer The OMC observer reference to take ownership of
- (void)setObserver:(OMCObserverRef)observer;

@end

NS_ASSUME_NONNULL_END

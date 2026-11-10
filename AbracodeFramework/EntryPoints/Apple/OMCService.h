//
//  OMCService.h
//  OMCService
//
//  Created by Tomasz Kukielka on 1/20/11.
//  Copyright 2011 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "OMCObserverDelegate.h"

//responds to applicationDidFinishLaunching: but in case of OMC applet it is not the app delegate - OMCDropletController is and forwards applicationDidFinishLaunching:
//in case of standalone service OMCService is an app controller and receives the applicationDidFinishLaunching: directly
@interface OMCService : NSObject <NSApplicationDelegate>

- (void)runOMCService:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;

@end

// One Services request's command run: its observer, the text it returns and whether it has ended. Each
// request has its own, so a request that arrives while another one waits (the wait runs the run loop)
// does not share the other's observer or text. Used by runOMCService:, and by tests.
@interface OMCServiceRequest : NSObject <OMCObserverDelegate>
{
	OMCObserverRef	mObserver;
	BOOL mAllTasksFinished; // the command's "all tasks finished" arrived (it may arrive during OMCExecuteCommand)
}

@property (nonatomic, strong, readonly) NSMutableString *resultString; // nil when the request returns no text

- (instancetype)initReturningText:(BOOL)inReturnsText;

// Makes this request's observer and adds it to the executor (before OMCExecuteCommand)
- (void)observeExecutor:(OMCExecutorRef)inExecutor;

// Runs the run loop until the command's "all tasks finished" has arrived, at once if it already has
// (a synchronous command sends it inside OMCExecuteCommand)
- (void)waitForAllTasksFinished;

// OMCObserverDelegate:
- (void)receiveObserverMessage:(OmcObserverMessage)inMessage forTaskId:(CFIndex)inTaskID withData:(CFTypeRef)inResult;
- (void)setObserver:(OMCObserverRef)observer;

@end

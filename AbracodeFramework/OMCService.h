//
//  OMCService.h
//  OMCService
//
//  Created by Tomasz Kukielka on 1/20/11.
//  Copyright 2011 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include "OMC.h"


//responds to applicationDidFinishLaunching: but in case of OMC droplet it is not the app delegate - OMCDropletController is and forwards applicationDidFinishLaunching:
//in case of standalone service OMCService is an app controller and receives the applicationDidFinishLaunching: directly
@interface OMCService : NSObject <NSApplicationDelegate>
{
	OMCObserverRef	mObserver;
	BOOL mRunLoopStarted;
}

@property (nonatomic, strong) NSMutableString *resultString;

- (void)runOMCService:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
- (void)receiveObserverMessage:(OmcObserverMessage)inMessage forTaskId:(CFIndex)inTaskID withData:(CFTypeRef)inResult;


@end

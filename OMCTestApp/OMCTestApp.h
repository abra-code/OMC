//
//  OMCTestApp.h
//  OMCTestApp
//
//  Created by Tomasz Kukielka on 1/2/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include <Abracode/OMC.h>

@interface OMCTestAppController : NSObject
{
	OMCObserverRef	mObserver;
}

- (IBAction)executeExampleCommand:(id)sender;
- (IBAction)executeCommandWithFileContext:(id)sender;
- (IBAction)executeCommandWithText:(id)sender;
- (IBAction)executeExternalBundle:(id)sender;
- (IBAction)executeCommandWithObserver:(id)sender;

- (void)receiveObserverMessage:(OmcObserverMessage)inMessage forTaskId:(CFIndex)inTaskID withData:(CFTypeRef)inResult;

@end

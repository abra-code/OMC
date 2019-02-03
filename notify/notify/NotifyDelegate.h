//
//  NotifyDelegate.h
//  notify
//
//  Created by Tomasz Kukielka on 5/17/14.
//  Copyright (c) 2014 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NotifyDelegate : NSObject<NSApplicationDelegate, NSUserNotificationCenterDelegate>

+(NotifyDelegate *)sharedDelegate;

@end

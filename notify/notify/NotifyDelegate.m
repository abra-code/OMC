//
//  NotifyDelegate.m
//  notify
//
//  Created by Tomasz Kukielka on 5/17/14.
//  Copyright (c) 2014 Abracode. All rights reserved.
//

#import "NotifyDelegate.h"

@implementation NotifyDelegate

+(NotifyDelegate *)sharedDelegate
{
	static NotifyDelegate *sSharedDelegate = nil;
	if(sSharedDelegate == nil)
	{
		sSharedDelegate = [[NotifyDelegate alloc] init];
		NSUserNotificationCenter *defaultUserNotificationCenter = [NSUserNotificationCenter defaultUserNotificationCenter];
		defaultUserNotificationCenter.delegate = sSharedDelegate;
	}
	return sSharedDelegate;
}

- (void)dealloc
{
	NSUserNotificationCenter *defaultUserNotificationCenter = [NSUserNotificationCenter defaultUserNotificationCenter];
	defaultUserNotificationCenter.delegate = nil;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	NSUserNotification *activatedNotification = [aNotification.userInfo objectForKey:NSApplicationLaunchUserNotificationKey];
	if(activatedNotification != nil)
	{
		NSUserNotificationCenter *userNotificationCenter = [NSUserNotificationCenter defaultUserNotificationCenter];
		[self userNotificationCenter:userNotificationCenter didActivateNotification:activatedNotification];
	}
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
    return YES;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)notification
{
	[[NSApplication sharedApplication] terminate:self];
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
#pragma unused(center)
	if(notification.userInfo != nil)
	{
		// NSString *userInfoString = [notification.userInfo objectForKey:@"OMC_NOTIFICATION_USER_INFO"];
		// NSWorkspace *sharedWorkspace = [NSWorkspace sharedWorkspace];
	}

	NSUserNotificationCenter *defaultUserNotificationCenter = [NSUserNotificationCenter defaultUserNotificationCenter];
	[defaultUserNotificationCenter removeDeliveredNotification:notification];
}

@end

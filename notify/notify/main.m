//
//  main.m
//  notify
//
//  Created by Tomasz Kukielka on 5/17/14.
//  Copyright (c) 2014 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "NotifyDelegate.h"

void print_help();


static inline void NotifyUser(const char *inTitle, const char *inSubtitle, const char *inInfo, const char *inButton, const char *inUserInfo, const char *inSoundStr)
{
	@autoreleasepool
	{
		NSUserNotification *newNotification = [[[NSUserNotification alloc] init] autorelease];
		if(inTitle != nil)
			newNotification.title = [NSString stringWithUTF8String:inTitle];
		
		if(inSubtitle != nil)
			newNotification.subtitle = [NSString stringWithUTF8String:inSubtitle];

		if(inInfo != nil)
			newNotification.informativeText = [NSString stringWithUTF8String:inInfo];

		if(inButton != nil)
		{
			newNotification.hasActionButton = YES;
			newNotification.actionButtonTitle = [NSString stringWithUTF8String:inButton];
		}
		else
		{
			newNotification.hasActionButton = NO;
		}
		
		if(inSoundStr != nil)
		{
			if(strcmp(inSoundStr, "default") == 0)
				newNotification.soundName = NSUserNotificationDefaultSoundName;
			else
				newNotification.soundName = [NSString stringWithUTF8String:inSoundStr];
		}

		if(inUserInfo != nil)
		{
			NSString * userInfoStr = [NSString stringWithUTF8String:inUserInfo];
			newNotification.userInfo = [NSDictionary dictionaryWithObject:userInfoStr forKey:@"OMC_NOTIFICATION_USER_INFO"];
		}

		NSUserNotificationCenter *userNotificationCenter = [NSUserNotificationCenter defaultUserNotificationCenter];
		[userNotificationCenter deliverNotification:newNotification];
	}
}

int main(int argc, const char * argv[])
{
	int paramIndex = 1;
	int messageStrIndex = argc-1;//the last one is supposed to be the message string, so check params first
	
	if( (argc == 1) || ((argc > 1) && ((strcmp(argv[1], "--help") == 0) || (strcmp(argv[1], "-h") == 0)) ) )
	{
		print_help();
		return -1;
	}


	const char *titleStr = nil;
	const char *subtitleStr = nil;
	const char *messageStr = nil;
	const char *buttonStr = nil;
	const char *userInfoStr = nil;
	const char *soundStr = nil;

	while(paramIndex < messageStrIndex )//read key+value pairs of params
	{
		const char *param = argv[paramIndex++];
		if( (strcmp(param, "-t") == 0) || (strcmp(param, "--title") == 0) )
		{
			titleStr = argv[paramIndex++];
		}
		else if( (strcmp(param, "-s") == 0) || (strcmp(param, "--subtitle") == 0) )
		{
			subtitleStr = argv[paramIndex++];
		}
		else if( (strcmp(param, "-b") == 0) || (strcmp(param, "--button") == 0) )
		{
			buttonStr = argv[paramIndex++];
		}
		else if( (strcmp(param, "-u") == 0) || (strcmp(param, "--user-info") == 0) )
		{
			userInfoStr = argv[paramIndex++];
		}
		else if( (strcmp(param, "-d") == 0) || (strcmp(param, "--sound") == 0) )
		{
			soundStr = argv[paramIndex++];
		}
		else
		{
			fprintf(stderr, "Usage: notify [params] \"Notification Message\"\nType notify --help for more information\n\n");
			return -1;
		}
	}

	if(paramIndex == messageStrIndex)
	{
		messageStr = argv[paramIndex];
	}

	if(messageStr == nil)
	{
		fprintf(stderr, "Usage: notify [params] \"Notification Message\"\nType notify --help for more information\n\n");
		return -1;
	}

	@autoreleasepool
	{
		//this instantiates and registeres our delegate with NSUserNotificationCenter
		NotifyDelegate * delegate = [NotifyDelegate sharedDelegate];
		(void)delegate;
	}

	NotifyUser(titleStr, subtitleStr, messageStr, buttonStr, userInfoStr, soundStr);

	return NSApplicationMain(argc,  (const char **) argv);
}


void print_help()
{
	fprintf(stdout, "\nNAME\n");
	fprintf(stdout, "\tnotify - send user notification\n\n");

	fprintf(stdout, "SYNOPSIS\n");
	fprintf(stdout, "\tnotify [options] \"Notification Message\"\n\n");
	fprintf(stdout, "DESCRIPTION\n");
	fprintf(stdout, "\tnotify sends user notification\n");
	
	fprintf(stdout, "OPTIONS\n");

	fprintf(stdout, "\t-h,--help\n");
	fprintf(stdout, "\t\tPrint this help and exit\n");

	fprintf(stdout, "\t-t,--title\n");
	fprintf(stdout, "\t\tNotification title string. \"notify\" is default if not specified\n");

	fprintf(stdout, "\t-s,--subtitle\n");
	fprintf(stdout, "\t\tSubtitle string\n");

	fprintf(stdout, "\t-d,--sound\n");
	fprintf(stdout, "\t\tSound name. Use \"default\" or any system sound name:\n");
	fprintf(stdout, "\t\tBasso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink\n");

	fprintf(stdout, "\t-b,--button\n");
	fprintf(stdout, "\t\tButton string\n");

	fprintf(stdout, "\t-u,--user-info\n");
	fprintf(stdout, "\t\tUser info string\n");

	fprintf(stdout, "EXAMPLES\n");
	fprintf(stdout, "\tnotify -t \"My Title\" -s \"My Subtitle\" \"My Notification\"\n");
	
}


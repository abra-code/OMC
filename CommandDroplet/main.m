//
//  main.m
//  CommandDroplet
//
//  Created by Tomasz Kukielka on 6/7/08.
//  Copyright Abracode Inc 2008. All rights reserved.
//

#import <Cocoa/Cocoa.h>

UInt32 GetAbracodeFrameworkVersion(void);

#define MINIMUM_OMC_VERSION 20000

int main(int argc, char *argv[])
{
	if(GetAbracodeFrameworkVersion() >= MINIMUM_OMC_VERSION)
	{
		return NSApplicationMain(argc,  (const char **) argv);
	}
	return 1;
}

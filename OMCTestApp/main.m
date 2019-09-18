//
//  main.m
//  OMCTestApp
//
//  Copyright Abracode 2008. All rights reserved.
//

#import <Cocoa/Cocoa.h>

UInt32 GetAbracodeFrameworkVersion(void);

#define MINIMUM_OMC_VERSION 20000

int main(int argc, char *argv[])
{
	if(GetAbracodeFrameworkVersion() < MINIMUM_OMC_VERSION)
		return 1;

    return NSApplicationMain(argc,  (const char **) argv);
}

//
//  OMCSingleCommand.m
//  Abracode
//
//  Created by Tomasz Kukielka on 4/5/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import "OMCSingleCommand.h"
#import "OMCCommandExecutor.h"

@implementation OMCSingleCommand

@synthesize commandFilePath = _commandFilePath;

- (id)init
{
    self = [super init];
	if(self == nil)
		return nil;

	self.commandFilePath = @"Command.plist";

    return self;
}

- (void)dealloc
{
    self.commandID = nil;
    self.commandFilePath = nil;
	[super dealloc];
}

- (void)setCommandFilePath:(NSString *)inPath
{
	if((inPath != nil) && ([inPath length] > 0))
	{
		[inPath retain];
		[_commandFilePath release];
		_commandFilePath = inPath;
	}
	else
	{
		[_commandFilePath release];
		_commandFilePath = [@"Command.plist" retain];
	}
}

- (void)execute:(id)sender
{
	NSString *myCommandID = self.commandID;
	if( (sender != NULL) && [sender respondsToSelector:@selector(commandID)] )
	{
		myCommandID = [sender commandID];
	}

	/*OSStatus err = */[OMCCommandExecutor runCommand:myCommandID forCommandFile:self.commandFilePath withContext:NULL useNavDialog:YES delegate:self];
}


@end

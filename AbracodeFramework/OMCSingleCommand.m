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

- (id)init
{
    self = [super init];
	if(self == nil)
		return nil;

	_commandFilePath = @"Command.plist";

    return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super init];
	if(self == nil)
		return nil;

    _commandFilePath = @"Command.plist";

    return self;
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
}

- (void)setCommandFilePath:(NSString *)inPath
{
	if((inPath != nil) && ([inPath length] > 0))
	{
		_commandFilePath = inPath;
	}
	else
	{
		_commandFilePath = @"Command.plist";
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

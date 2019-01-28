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
	if(self == NULL)
		return NULL;
	commandID = NULL;
	commandFilePath = @"Command.plist";
	[commandFilePath retain];
    return self;
}

- (void)dealloc
{
    [commandID release];
    [commandFilePath release];
	[super dealloc];
}

- (NSString *)commandID
{
	return commandID;
}

- (void)setCommandID:(NSString *)string
{
	[string retain];
	[commandID release];
	commandID = string;
}


- (NSString *)commandFilePath
{
	return commandFilePath;
}

- (void)setCommandFilePath:(NSString *)inPath
{
	if(inPath != NULL)
	{
		if([inPath length] == 0)
		{
			inPath = NULL;
		}
	}

	if(inPath != NULL)
	{
		[inPath retain];
		[commandFilePath release];
		commandFilePath = inPath;
	}
	else
	{
		[commandFilePath release];
		commandFilePath = @"Command.plist";
		[commandFilePath retain];
	}
}

//legacy encoder/decoder support - custom control data no longer serialized into nibs
//custom properties get set later on nib load by calling proprty setters

- (id)initWithCoder:(NSCoder *)coder
{
   self = [super init];
	if(self == NULL)
		return NULL;

    if( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed decoding"];
	
	commandID = [[coder decodeObjectForKey:@"omcCommandID"] retain];

	NSString *myFilePath = [coder decodeObjectForKey:@"omcCommandFilePath"];
	[self setCommandFilePath:myFilePath];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    if ( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed encoding"];

	if(commandID != NULL)
		[coder encodeObject:commandID forKey:@"omcCommandID"];
	
	if( (commandFilePath != NULL) && ![commandFilePath isEqualToString:@"Command.plist"] )
	{
		[coder encodeObject:commandFilePath forKey:@"omcCommandFilePath"];
	}
}

- (void)execute:(id)sender
{
	NSString *myCommandID = commandID;
	if( (sender != NULL) && [sender respondsToSelector:@selector(commandID)] )
	{
		myCommandID = [sender commandID];
	}

	/*OSStatus err = */[OMCCommandExecutor runCommand:myCommandID forCommandFile:commandFilePath withContext:NULL useNavDialog:YES delegate:self];
}


@end

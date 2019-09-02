/*
	OMCButtonCell.m
*/

#import "OMCButtonCell.h"
#import <AppKit/AppKit.h>

@implementation OMCButtonCell

@synthesize commandID, mappedOnValue, mappedOffValue, escapingMode;

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;
	commandID = NULL;
	mappedOnValue = NULL;
	mappedOffValue = NULL;
	escapingMode = @"esc_none";
	[escapingMode retain];

	return self;
}

- (void)dealloc
{
    [commandID release];
    [mappedOnValue release];
    [mappedOffValue release];	
 	[escapingMode release];
	[super dealloc];
}

//a subclass of NSCell must implement copying

- (id)copyWithZone:(NSZone *)zone
{
	OMCButtonCell *objCopy = [super copyWithZone:zone];

	[objCopy->commandID retain];
	[objCopy->mappedOnValue retain];
	[objCopy->mappedOffValue retain];
	[objCopy->escapingMode retain];

	return objCopy;
}

//overriding NSControl methods to include mapped values

- (NSString *)stringValue
{
	int intValue = [self intValue];
	if( (intValue > 0) && (mappedOnValue != NULL) )
		return mappedOnValue;
	else if( (intValue == 0) && (mappedOffValue != NULL) )
		return mappedOffValue;
		
	return [super stringValue];
}

- (void)setStringValue:(NSString *)aString
{
	if(aString == NULL)
		return;
		
	if( (mappedOnValue != NULL) && [mappedOnValue isEqualToString:aString] )
	{
		[self setIntValue:1];
	}
	else if( (mappedOffValue != NULL) && [mappedOffValue isEqualToString:aString] )
	{
		[self setIntValue:0];
	}
	else
	{
		[super setStringValue:aString];
	}
}

@end

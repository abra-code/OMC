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

//legacy encoder/decoder support - custom control data no longer serialized into nibs
//custom properties get set later on nib load by calling proprty setters

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == NULL)
		return NULL;

    if( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed decoding"];

	commandID = [[coder decodeObjectForKey:@"omcCommandID"] retain];
	mappedOnValue = [[coder decodeObjectForKey:@"omcMappedOnValue"] retain];
	mappedOffValue = [[coder decodeObjectForKey:@"omcMappedOffValue"] retain];
	escapingMode = [[coder decodeObjectForKey:@"omcEscapingMode"] retain];
	if(escapingMode == NULL)
	{
		escapingMode = @"esc_none";//use default if key not present
		[escapingMode retain];
	}

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    if( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed encoding"];

	if(commandID != NULL)
		[coder encodeObject:commandID forKey:@"omcCommandID"];

	if(mappedOnValue != NULL)
		[coder encodeObject:mappedOnValue forKey:@"omcMappedOnValue"];

	if(mappedOffValue != NULL)
		[coder encodeObject:mappedOffValue forKey:@"omcMappedOffValue"];

	if(escapingMode == NULL)
	{
		escapingMode = @"esc_none";
		[escapingMode retain];
	}

	[coder encodeObject:escapingMode forKey:@"omcEscapingMode"];
}

@end

/*
	OMCMenuItem.m
*/

#import "OMCMenuItem.h"

@implementation OMCMenuItem

@synthesize commandID, mappedValue, escapingMode;

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;

	commandID = NULL;
	mappedValue = NULL;
	escapingMode = @"esc_none";
	[escapingMode retain];
	return self;
}

- (id)initWithTitle:(NSString *)itemName action:(SEL)anAction keyEquivalent:(NSString *)charCode
{
	
	self = [super initWithTitle:itemName action:anAction keyEquivalent:charCode];
	if(self == NULL)
		return NULL;

	commandID = NULL;
	mappedValue = NULL;
	escapingMode = @"esc_none";
	[escapingMode retain];
	return self;
}

- (void)dealloc
{
    [commandID release];
    [mappedValue release];
	[escapingMode release];
    [super dealloc];
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
	mappedValue = [[coder decodeObjectForKey:@"omcMappedValue"] retain];
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

	if(mappedValue != NULL)
		[coder encodeObject:mappedValue forKey:@"omcMappedValue"];

	if(escapingMode == NULL)
	{
		escapingMode = @"esc_none";
		[escapingMode retain];
	}
	
	[coder encodeObject:escapingMode forKey:@"omcEscapingMode"];

}

@end

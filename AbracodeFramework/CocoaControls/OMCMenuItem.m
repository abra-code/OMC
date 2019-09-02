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

@end

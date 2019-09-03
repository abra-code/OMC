/*
	OMCMenuItem.m
*/

#import "OMCMenuItem.h"

@implementation OMCMenuItem

@synthesize commandID;
@synthesize mappedValue;
@synthesize escapingMode;

- (id)init
{
    self = [super init];
	if(self == nil)
		return nil;

	self.escapingMode = @"esc_none";

	return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == nil)
		return nil;

	self.escapingMode = @"esc_none";

    return self;
}

- (id)initWithTitle:(NSString *)itemName action:(SEL)anAction keyEquivalent:(NSString *)charCode
{
	self = [super initWithTitle:itemName action:anAction keyEquivalent:charCode];
	if(self == nil)
		return nil;

	self.escapingMode = @"esc_none";

	return self;
}

- (void)dealloc
{
    self.commandID = nil;
    self.mappedValue = nil;
	self.escapingMode = nil;
    [super dealloc];
}

@end

/*
	OMCMenuItem.m
*/

#import "OMCMenuItem.h"

@implementation OMCMenuItem

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

@end

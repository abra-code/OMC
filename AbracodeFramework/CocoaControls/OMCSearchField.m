/*
	OMCSearchField.m
*/

#import "OMCSearchField.h"

@implementation OMCSearchField

@synthesize commandID;
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

- (void)dealloc
{
    self.commandID = nil;
	self.escapingMode = nil;
    [super dealloc];
}

@end

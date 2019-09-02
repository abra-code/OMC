/*
	OMCSearchField.m
*/

#import "OMCSearchField.h"

@implementation OMCSearchField

@synthesize commandID, escapingMode;


- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;
	commandID = NULL;
 	self.escapingMode = @"esc_none";
	return self;
}

- (void)dealloc
{
    [commandID release];
	[escapingMode release];
    [super dealloc];
}

@end

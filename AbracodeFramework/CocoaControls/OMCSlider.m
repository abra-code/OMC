/*
	OMCSlider.m
*/

#import "OMCSlider.h"

@implementation OMCSlider

@synthesize commandID;

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;
	commandID = NULL;
    return self;
}

- (void)dealloc
{
    [commandID release];
    [super dealloc];
}

@end

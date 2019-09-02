/*
	OMCProgressIndicator.m
*/

#import "OMCProgressIndicator.h"

@implementation OMCProgressIndicator

@synthesize tag = _omcTag;

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;
	_omcTag = 0;
    return self;
}

- (void)dealloc
{
    [super dealloc];
}

@end

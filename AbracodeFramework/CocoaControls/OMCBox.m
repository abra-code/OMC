/*
	OMCBox.m
*/

#import "OMCBox.h"
#import "OMCView.h"

@implementation OMCBox

@synthesize tag = _omcTag;

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;
	_omcTag = 0;
	enabled = YES;
	return self;
}

- (void)dealloc
{
    [super dealloc];
}

- (BOOL)isEnabled
{
	return enabled;
}

- (void)setEnabled:(BOOL)flag
{
	if(enabled != flag)
	{
		enabled = flag;
		[OMCView setEnabled:enabled inView:self];
	}
}

@end

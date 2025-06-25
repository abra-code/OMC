/*
	OMCGridView.m
*/

#import "OMCGridView.h"
#import "OMCView.h"

@implementation OMCGridView

@synthesize tag;

- (id)init
{
    self = [super init];
	if(self == nil)
		return nil;

	_enabled = YES;

	return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == nil)
		return nil;

	_enabled = YES;

    return self;
}

- (void)setEnabled:(BOOL)flag
{
	if(_enabled != flag)
	{
		_enabled = flag;
		[OMCView setEnabled:_enabled inView:self];
	}
}

@end

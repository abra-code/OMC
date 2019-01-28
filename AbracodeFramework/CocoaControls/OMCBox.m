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

//legacy encoder/decoder support - custom control data no longer serialized into nibs
//custom properties get set later on nib load by calling proprty setters

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == NULL)
		return NULL;

    if( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed decoding"];
	
	_omcTag = [coder decodeIntForKey:@"omcTag"];
	enabled = YES;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    if ( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed encoding"];

	[coder encodeInt:_omcTag forKey:@"omcTag"];
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

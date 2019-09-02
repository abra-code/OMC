/*
	OMCIKImageView.m
*/

#import "OMCIKImageView.h"

@implementation OMCIKImageView

@synthesize tag = _omcTag, escapingMode;

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;
    _omcTag = 0;
	escapingMode = @"esc_none";
	[escapingMode retain];
	return self;
}

- (void)dealloc
{
	[escapingMode release];
    [super dealloc];
}

- (NSString *)stringValue
{
	return NULL;//todo. most likely we will need to hold member variable
}

- (void)setStringValue:(NSString *)aString
{
	NSURL *imageURL = [NSURL fileURLWithPath:aString];
	if(imageURL == NULL)
		return;

	[self setImageWithURL:imageURL];
}


@end

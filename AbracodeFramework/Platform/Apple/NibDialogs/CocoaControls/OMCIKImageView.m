/*
	OMCIKImageView.m
*/

#import "OMCIKImageView.h"

@implementation OMCIKImageView

@synthesize tag;

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

- (NSString *)stringValue
{
	return nil;//todo. most likely we will need to hold member variable
}

- (void)setStringValue:(NSString *)aString
{
	NSURL *imageURL = [NSURL fileURLWithPath:aString];
	if(imageURL == nil)
		return;

	[self setImageWithURL:imageURL];
}


@end

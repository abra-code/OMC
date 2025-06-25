/*
	OMCWebView.m
*/

#import "OMCWebView.h"

@implementation OMCWebView

@synthesize tag;

- (id)init
{
    self = [super init];
	if(self == nil)
		return nil;

	self.escapingMode = @"esc_none";

	return self;
}

//legacy encoder/decoder support - custom control data no longer serialized into nibs
//custom properties get set later on nib load by calling property setters

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
	return [self mainFrameURL];
}

- (void)setStringValue:(NSString *)aString
{
	[self setMainFrameURL:aString];
}

@end

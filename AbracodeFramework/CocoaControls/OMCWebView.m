/*
	OMCWebView.m
*/

#import "OMCWebView.h"

@implementation OMCWebView

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
	return [self mainFrameURL];
}

- (void)setStringValue:(NSString *)aString
{
	[self setMainFrameURL:aString];
}

@end

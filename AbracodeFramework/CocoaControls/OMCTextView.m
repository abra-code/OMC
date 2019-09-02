/*
	OMCTextView.m
*/

#import "OMCTextView.h"
#import "OMCView.h"

@implementation OMCTextView

@synthesize tag = _omcTag, escapingMode;

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;
    _omcTag = 0;
	escapingMode = @"esc_none";
	[escapingMode retain];
	enabled = YES;
	savedTextColor = NULL;
	return self;
}

- (void)dealloc
{
	[escapingMode release];
	if(savedTextColor != NULL)
		[savedTextColor release];
    [super dealloc];
}

- (NSString *)stringValue
{
	return [self string];
}

- (void)setStringValue:(NSString *)aString
{
	[self setString:aString];
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
		[self setSelectable: enabled];
		[self setEditable: enabled];
		if(enabled)
		{
			if(savedTextColor != NULL)
			{
				[self setTextColor:savedTextColor];
				[savedTextColor release];
				savedTextColor = NULL;
			}
			else
				[self setTextColor: [NSColor controlTextColor]];
		}
		else
		{
			if(savedTextColor != NULL)
				[savedTextColor release];
			savedTextColor = [self textColor];
			[savedTextColor retain];
			[self setTextColor: [NSColor disabledControlTextColor]];
		}
	}
}

@end

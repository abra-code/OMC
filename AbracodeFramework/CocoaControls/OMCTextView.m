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
	escapingMode = [[coder decodeObjectForKey:@"omcEscapingMode"] retain];
	if(escapingMode == NULL)
	{
		escapingMode = @"esc_none";//use default if key not present
		[escapingMode retain];
	}
	enabled = YES;
	savedTextColor = NULL;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    if ( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed encoding"];

	[coder encodeInt:_omcTag forKey:@"omcTag"];

	if(escapingMode == NULL)
	{
		escapingMode = @"esc_none";
		[escapingMode retain];
	}
	
	[coder encodeObject:escapingMode forKey:@"omcEscapingMode"];
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

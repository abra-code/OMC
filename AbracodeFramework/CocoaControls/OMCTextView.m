/*
	OMCTextView.m
*/

#import "OMCTextView.h"
#import "OMCView.h"

@implementation OMCTextView

@synthesize tag;
@synthesize escapingMode;
@synthesize enabled = _enabled;

- (id)init
{
    self = [super init];
	if(self == nil)
		return nil;

	self.escapingMode = @"esc_none";
	_enabled = YES;

	return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == nil)
		return nil;

	self.escapingMode = @"esc_none";
	_enabled = YES;

    return self;
}

- (void)dealloc
{
	self.escapingMode = nil;
	[_savedTextColor release];
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

- (void)setEnabled:(BOOL)flag
{
	if(_enabled != flag)
	{
		_enabled = flag;
		[self setSelectable:_enabled];
		[self setEditable:_enabled];
		if(_enabled)
		{
			if(_savedTextColor != nil)
			{
				[self setTextColor:_savedTextColor];
				[_savedTextColor release];
				_savedTextColor = nil;
			}
			else
				[self setTextColor: [NSColor controlTextColor]];
		}
		else
		{
			[_savedTextColor release];
			_savedTextColor = [[self textColor] retain];
			[self setTextColor: [NSColor disabledControlTextColor]];
		}
	}
}

@end

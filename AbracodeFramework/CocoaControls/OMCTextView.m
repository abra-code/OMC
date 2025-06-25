/*
	OMCTextView.m
*/

#import "OMCTextView.h"
#import "OMCView.h"

@implementation OMCTextView

@synthesize tag;

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
			if(self.savedTextColor != nil)
			{
				[self setTextColor:self.savedTextColor];
                self.savedTextColor = nil;
			}
			else
				[self setTextColor:[NSColor controlTextColor]];
		}
		else
		{
			self.savedTextColor = [self textColor];
			[self setTextColor:[NSColor disabledControlTextColor]];
		}
	}
}

@end

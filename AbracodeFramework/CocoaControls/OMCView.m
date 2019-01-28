/*
	OMCView.m
*/

#import "OMCView.h"
#import "OMCTextView.h"
#include "DebugSettings.h"

@implementation OMCView

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

//recursive enable/disable for all controls in a view
+ (void)setEnabled:(BOOL)flag inView:(id)inView
{
	//checking if inView responds to setEnabled: selector and calling it would result in infinite loop for OMCView
	//we check for classes that we know that respond to that selector instead

	if([inView isKindOfClass:[NSControl class] ])
	{
		NSControl *theControl = (NSControl *)inView;
		[theControl setEnabled:flag];
	}
	else if([inView isKindOfClass:[OMCTextView class] ]) //regular NSTextView does not support enable/disable but our subclass does
	{
		OMCTextView *textView = (OMCTextView *)inView;
		[textView setEnabled:flag];
	}
	else if([inView isKindOfClass:[NSTabView class] ])
	{//search tabs view recursively
		NSArray *tabViewsArray = [(NSTabView*)inView tabViewItems];
		if(tabViewsArray != NULL)
		{
			NSUInteger tabCount = [tabViewsArray count];
			NSUInteger tabIndex;
			for(tabIndex=0; tabIndex < tabCount; tabIndex++)
			{
				id oneTab = [tabViewsArray objectAtIndex:tabIndex];
				if( (oneTab != NULL) && [oneTab isKindOfClass:[NSTabViewItem class]] )
				{
					id viewObject = [(NSTabViewItem*)oneTab view];
					if( (viewObject != NULL) && [viewObject isKindOfClass:[NSView class]] )
					{
						[OMCView setEnabled:flag inView:viewObject];
					}
				}
			}
		}
	}
	else if( [inView isKindOfClass:[NSView class] ] )
	{
		//search subviews recursively
		NSArray *subViewsArray = [inView subviews];
		if(subViewsArray != NULL)
		{
			int subIndex;
			int subCount = [subViewsArray count];
			for(subIndex = 0; subIndex < subCount; subIndex++)
			{
				id viewObject = [subViewsArray objectAtIndex:subIndex];
				if( (viewObject != NULL) && [viewObject isKindOfClass:[NSView class]] )
				{
					[OMCView setEnabled:flag inView:viewObject];
				}
			}
		}
	}
	else
	{
		DEBUG_CSTR("Unknown element type passed to OMCView setEnabled:inView:\n");
	}
}

@end

/*
	OMCView.m
*/

#import "OMCView.h"
#import "OMCTextView.h"
#include "DebugSettings.h"

@implementation OMCView

@synthesize tag;

- (id)init
{
    self = [super init];
 	if(self == nil)
		return nil;

	_enabled = YES;
	return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == nil)
		return nil;

	_enabled = YES;

    return self;
}

- (void)setEnabled:(BOOL)flag
{
	if(_enabled != flag)
	{
		_enabled = flag;
		[OMCView setEnabled:_enabled inView:self];
	}
}

//recursive enable/disable for all controls in a view
+ (void)setEnabled:(BOOL)flag inView:(NSView *)inView
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
        for(NSTabViewItem *oneTab in ((NSTabView*)inView).tabViewItems)
        {
            NSView *tabView = [oneTab view];
            if(tabView != nil)
            {
                [OMCView setEnabled:flag inView:tabView];
            }
        }
	}
	else if(inView != nil)
	{
		//search subviews recursively
        for(NSView *subView in inView.subviews)
        {
            [OMCView setEnabled:flag inView:subView];
        }
	}
}

@end

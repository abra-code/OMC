//
//  OMCInputDialogController.m
//  Abracode
//
//  Created by Tomasz Kukielka on 8/25/09.
//  Copyright 2009-2010 Abracode. All rights reserved.
//

#import "OMCInputDialogController.h"

enum
{
	kOMCInputDialogOKButtonTag = 1,
	kOMCInputDialogCancelButtonTag = 2,
};

@implementation OMCInputDialogController

- (id)initWithWindowNibName:(NSString *)windowNibName	// self is the owner
{
	self = [super initWithWindowNibName:windowNibName];
	if( self != NULL )
	{
		mIsCanceled = YES;
		mMenuItems = NULL;
	}
	return self;
}

- (void)dealloc
{
/*  
	do not call [self window] in dealloc. Our refcount is 0 now and this will try to:
	- load the window
	- revive the controller and retain

	NSWindow *myWindow = [self window];
	
	if(myWindow != NULL)
		[myWindow close];
*/
	[mMenuItems release];

	[super dealloc];
}

//setup
- (void)setMenuItems:(NSArray*)inMenuItems//array of NAME & VALUE mappings
{
	if (mPopupButton != NULL)
		[mPopupButton removeAllItems];
	else if(mComboBox != NULL)
		[mComboBox removeAllItems];

	if(mMenuItems != NULL)
		[mMenuItems release];

	mMenuItems = inMenuItems;
	
	if( mMenuItems == NULL )
		return;

	[mMenuItems retain];

	NSUInteger i;
	NSUInteger itemCount = [mMenuItems count];
	for(i = 0; i < itemCount; i++)
	{
		NSDictionary *dictItem = NULL;
		id oneItem = [mMenuItems objectAtIndex:i];
		if( [oneItem isKindOfClass:[NSDictionary class]] )
		{
			dictItem = (NSDictionary *)oneItem;
			oneItem = [dictItem objectForKey:@"NAME"];
			if( [oneItem isKindOfClass:[NSString class]] )
			{
				if (mPopupButton != NULL)
					[mPopupButton addItemWithTitle:(NSString *)oneItem];
				else if(mComboBox != NULL)
					[mComboBox addItemWithObjectValue:(NSString *)oneItem];
			}
		}
	}
}

- (void)setWindowTitle:(NSString*)inTitle
{
	NSWindow *myWindow = [self window];
	if( (inTitle != NULL) && (myWindow != NULL) )
		[myWindow setTitle:inTitle];
}

- (void)setMessageText:(NSString*)inText
{
	if(inText == NULL)
		inText = @"";
	[mMessageText setStringValue:inText];
}

- (void)setOKButtonTitle:(NSString *)inTitle
{
	if(inTitle != NULL)
		[mOKButton setTitle:inTitle];
}

- (void)setCancelButtonTitle:(NSString *)inTitle;
{
	if(inTitle != NULL)
		[mCancelButton setTitle:inTitle];
}

//returns YES if OK-okeyd
- (BOOL)runModalDialog
{
	NSWindow *myWindow = [self window];
	if(myWindow == NULL)
		return NO;

	[self layoutControls];
	[myWindow makeKeyAndOrderFront:self];

	[NSApp runModalForWindow: myWindow];

	return !mIsCanceled;
}


- (IBAction)closeWindow:(id)sender
{
	int buttonTag = [sender tag];
	if(buttonTag == kOMCInputDialogOKButtonTag)
		mIsCanceled = NO;
	else 
		mIsCanceled = YES;

	[[self window] close];
}

- (void)windowWillClose:(NSNotification *)notification
{
	[NSApp stopModal];
}

-(void)layoutControls
{
	NSWindow *myWindow = [self window];
	NSView *contentView = [myWindow contentView];
	NSRect windowsBounds = [contentView bounds];
	NSSize newWindowSize = windowsBounds.size;

	NSView *controlView = NULL;
	if(mEditField != NULL)
		controlView = mEditField;
	else if(mPasswordField != NULL)
		controlView = mPasswordField;
	else if(mPopupButton != NULL)
		controlView = mPopupButton;
	else if(mComboBox != NULL)
		controlView = mComboBox;

//	NSRect cellDrawingRect = [[mOKButton cell] drawingRectForBounds:[mOKButton bounds]];
//	NSSize cellSize = [[mOKButton cell] cellSize];

	//maybe call sizeToFit and then add 16 pix on each side
	//[mOKButton sizeToFit];
	//[mCancelButton sizeToFit];

	NSRect newOKFrame = [mOKButton frame];
	NSRect constrains = newOKFrame;
	constrains.origin.x = constrains.origin.y = 0.0;
	constrains.size.width = 500.0;
	NSSize cellSize2 = [[mOKButton cell] cellSizeForBounds:constrains];
	newOKFrame.size = cellSize2;
	newOKFrame.size.width += 28.0;//14 pix on each side
	
	NSRect newCancelFrame = [mCancelButton frame];
	constrains = newCancelFrame;
	constrains.origin.x = constrains.origin.y = 0.0;
	constrains.size.width = 500.0;
	cellSize2 = [[mCancelButton cell] cellSizeForBounds:constrains];
	newCancelFrame.size = cellSize2;
	newCancelFrame.size.width += 28.0;//14 pix on each side

	[mMessageText sizeToFit];
	NSRect textViewFrame = [mMessageText frame];

	NSRect controlViewFrame = NSMakeRect(0, 0, 0, 0);
	if(controlView != NULL)
		controlViewFrame = [controlView frame];
	
	const CGFloat kVertSpacing = 20.0;
	const CGFloat kHorizSpacing = 16.0;
	const CGFloat kButtonSpacing = 8.0;

	newWindowSize.height = kVertSpacing + textViewFrame.size.height +
							kVertSpacing + controlViewFrame.size.height +
							kVertSpacing + newOKFrame.size.height + kVertSpacing;
	[myWindow setContentSize:newWindowSize];
	
	textViewFrame.origin.y = kVertSpacing + controlViewFrame.size.height + kVertSpacing + newOKFrame.size.height + kVertSpacing;
	[mMessageText setFrame:textViewFrame];

	CGFloat availableWidth = newWindowSize.width - 2*kHorizSpacing - kButtonSpacing;
	if( (newCancelFrame.size.width + newOKFrame.size.width) > availableWidth )
	{
		//shorten the wider guy
		CGFloat halfWidth = availableWidth/2.0;
		if( (newCancelFrame.size.width > halfWidth) && (newOKFrame.size.width < halfWidth) )//Cancel bigger than half but OK smaller
		{
			newCancelFrame.size.width = availableWidth - newOKFrame.size.width;
		}
		else if( (newOKFrame.size.width > halfWidth) && (newCancelFrame.size.width < halfWidth) ) //OK bigger than half but Cancel smaller
		{
			newOKFrame.size.width = availableWidth - newCancelFrame.size.width;
		}
		else //both bigger? divide equally
		{
			newOKFrame.size.width = halfWidth;
			newCancelFrame.size.width = halfWidth;
		}
	}

	newOKFrame.origin.x =  newWindowSize.width - (kHorizSpacing + newOKFrame.size.width);
	newOKFrame.origin.y = kVertSpacing;
	[mOKButton setFrame:newOKFrame];
	
	newCancelFrame.origin.x = newOKFrame.origin.x - (kButtonSpacing + newCancelFrame.size.width);
	newCancelFrame.origin.y = kVertSpacing;
	[mCancelButton setFrame:newCancelFrame];
}

- (NSString *)getChoiceString
{
	NSString *choiceString = NULL;
	if(mEditField != NULL)
		choiceString = [mEditField stringValue];
	else if(mPasswordField != NULL)
		choiceString = [mPasswordField stringValue];
	else if(mPopupButton != NULL)
		choiceString = [mPopupButton titleOfSelectedItem];
	else if(mComboBox != NULL)
		choiceString = [mComboBox stringValue];

	if( (choiceString != NULL) && (mMenuItems != NULL) )
	{
		//find mapping if mapped menu
		NSUInteger i;		
		NSUInteger itemCount = [mMenuItems count];
		for(i = 0; i < itemCount; i++)
		{
			NSDictionary *dictItem = NULL;
			id oneItem = [mMenuItems objectAtIndex:i];
			if( [oneItem isKindOfClass:[NSDictionary class]] )
			{
				dictItem = (NSDictionary *)oneItem;
				oneItem = [dictItem objectForKey:@"NAME"];
				if( [oneItem isKindOfClass:[NSString class]] )
				{
					NSString *stringItem = (NSString*)oneItem;
					if( [stringItem isEqualToString:choiceString] )
					{
						oneItem = [dictItem objectForKey:@"VALUE"];
						if( (oneItem != NULL) && [oneItem isKindOfClass:[NSString class]] )
						{
							choiceString = (NSString *)oneItem;
							break;
						}
					}
				}
			}
		}
	}

	return choiceString;
}

- (void)setDefaultChoiceString:(NSString *)inString;
{
	if(inString == NULL)
		inString = @"";

	if(mEditField != NULL)
		[mEditField setStringValue:inString];
	else if(mPasswordField != NULL)
		[mPasswordField setStringValue:inString];
	else if(mPopupButton != NULL)
	{
		NSInteger itemIndex = [mPopupButton indexOfItemWithTitle:inString];
		if( itemIndex < 0 )
			itemIndex = 0;
		[mPopupButton selectItemAtIndex:itemIndex];
	}
	else if(mComboBox != NULL)
		[mComboBox setStringValue:inString];
}


@end

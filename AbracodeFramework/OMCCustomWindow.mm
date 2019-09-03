//
//  OMCCustomWindow.m
//  Abracode
//
//  Created by Tomasz Kukielka on 5/24/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#import "OMCCustomWindow.h"
#import "OMCWindow.h"
#include "OutputWindowHandler.h"

@implementation OMCCustomWindow

- (id)initWithSettings:(const OutputWindowSettings *)inSettings
{
	NSImage *windowImage = NULL;
	NSSize imgSize = NSMakeSize(inSettings->width, inSettings->height);
	if( (CGImageRef)inSettings->backgroundImage != NULL)
	{
		NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc] initWithCGImage:(CGImageRef)inSettings->backgroundImage];
		[bitmapRep autorelease];
		windowImage = [[NSImage alloc] initWithSize:imgSize];
		[windowImage addRepresentation:bitmapRep];
		[windowImage autorelease];
		imgSize = [windowImage size];
	}

	NSRect windowRect = NSMakeRect(0, 0, imgSize.width, imgSize.height);

	self = [super initWithContentRect:windowRect styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
	if(self == nil)
		return nil;

	textBox = inSettings->textBox;//top-left relative
	closeBox = inSettings->closeBox; //top-left relative
	resizeBox = inSettings->resizeBox;//bottom-right relative

	[self setBackgroundColor:[NSColor clearColor]];
	
	if(windowImage != NULL)
	{
		NSImageView *imgView = [[NSImageView alloc] initWithFrame:windowRect];
		[imgView setImage:windowImage];
		[imgView setAllowsCutCopyPaste:NO];
		[imgView setEditable:NO];
		[imgView setRefusesFirstResponder:YES];
		//[imgView setAlphaValue:inSettings->alpha];
		[self setContentView:imgView];
		[imgView release];
	}

	useFadeIn = NO;
	useFadeOut = NO;
	_fadeOutAnimation = NULL;

	return self;
}

- (void)setFadeIn:(BOOL)inFadeIn
{
	useFadeIn = inFadeIn;
}

- (void)setFadeOut:(BOOL)inFadeOut
{
	useFadeOut = inFadeOut;
}

- (void)makeKeyAndOrderFront:(id)sender
{
#if _DEBUG_
	NSLog(@"OMCCustomWindow makeKeyAndOrderFront");
#endif
	if(useFadeIn)
	{
		useFadeIn = NO;//do not reenter and next makeKeyAndOrderFront will not repeat the animation
		NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:self, NSViewAnimationTargetKey,
							  NSViewAnimationFadeInEffect, NSViewAnimationEffectKey,
							  nil];
		
		NSViewAnimation *fadeInAnimation = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:dict]];
		[fadeInAnimation setAnimationBlockingMode:NSAnimationNonblocking];
		//		[fadeInAnimation setDelegate:self];
		//[self setAlphaValue: 0.0];
		[fadeInAnimation startAnimation];
		[fadeInAnimation release];
	}
	
	[super makeKeyAndOrderFront:sender];
	[OMCWindow addWindow];
}


//NSAnimation delegate method

- (void)animationDidStop:(NSAnimation*)animation
{
    [self animationDidEnd:animation];
}

-(void)animationDidEnd:(NSAnimation *)animation
{
	//NSLog(@"OMCCustomWindow animationDidEnd");
	if(animation == _fadeOutAnimation)
	{
		[_fadeOutAnimation release];
		_fadeOutAnimation = NULL;
		[super orderOut:self];
	}
}

- (void)orderOut:(id)sender
{
	//NSLog(@"OMCCustomWindow orderOut");
	if(useFadeOut)
	{
		useFadeOut = NO;//no reenter
		NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:self, NSViewAnimationTargetKey,
							  NSViewAnimationFadeOutEffect, NSViewAnimationEffectKey,
							  nil];
		
		_fadeOutAnimation = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:dict]];
		[_fadeOutAnimation setAnimationBlockingMode:NSAnimationNonblocking];
		[_fadeOutAnimation setDelegate:self];
		[_fadeOutAnimation startAnimation];
	}
	else
	{
		[super orderOut:sender];
	}
	[OMCWindow removeWindow];
}


- (BOOL)performKeyEquivalent:(NSEvent *)theEvent
{
	NSUInteger modifFlags = [theEvent modifierFlags];
	if( (modifFlags & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagCommand)
	{
		NSString *eventChar = [theEvent charactersIgnoringModifiers];
		if([eventChar isEqualToString: @"w"])
		{
			[self orderOut:self];
			return YES;
		}
	}
	return NO;
}

// Custom windows that use the NSBorderlessWindowMask can't become key by default.  Therefore, controls in such windows
// won't ever be enabled by default.  Thus, we override this method to change that.
- (BOOL) canBecomeKeyWindow
{
    return YES;
}

//Once the user starts dragging the mouse, we move the window with it. We do this because the window has no title
//bar for the user to drag (so we have to implement dragging ourselves)
- (void)mouseDragged:(NSEvent *)theEvent
{
   NSPoint currentLocation;
   NSPoint newOrigin;
   NSRect  screenFrame = [[NSScreen mainScreen] frame];
   NSRect  windowFrame = [self frame];

   //grab the current global mouse location; we could just as easily get the mouse location 
   //in the same way as we do in -mouseDown:
    currentLocation = [self convertPointToScreen:[self mouseLocationOutsideOfEventStream]];
    newOrigin.x = currentLocation.x - initialLocation.x;
    newOrigin.y = currentLocation.y - initialLocation.y;
    
	if( dragResizing )
	{
		//the delta in window size
		NSRect newFrame = windowFrame;
		newFrame.size.width += newOrigin.x;
		newFrame.size.height += newOrigin.y;
		newFrame.origin.y -= newOrigin.y;

		[self setFrame:newFrame display:YES];

		initialLocation = currentLocation;//new previous location
	}
	else
	{//drag moving
		// Don't let window get dragged up under the menu bar
		if( (newOrigin.y+windowFrame.size.height) > (screenFrame.origin.y+screenFrame.size.height) )
		{
			newOrigin.y=screenFrame.origin.y + (screenFrame.size.height-windowFrame.size.height);
		}
		
		//go ahead and move the window to the new location
		[self setFrameOrigin:newOrigin];
	}
}

//We start tracking the a drag operation here when the user first clicks the mouse,
//to establish the initial location.
- (void)mouseDown:(NSEvent *)theEvent
{    
    NSRect  windowFrame = [self frame];
	dragResizing = NO;

	NSPoint locationInWindow = [theEvent locationInWindow];
	CGFloat topY = (windowFrame.size.height - locationInWindow.y);//y coordinate as top-relative value

	CGFloat leftOrigX = windowFrame.size.width - resizeBox.origin.x - resizeBox.size.width;//right-relative to left-relative
	if( !CGRectIsEmpty(resizeBox) && 
		(locationInWindow.x >= leftOrigX) && (locationInWindow.x <= (leftOrigX+resizeBox.size.width)) &&
		(locationInWindow.y >= resizeBox.origin.y) && (locationInWindow.y <= (resizeBox.origin.y+resizeBox.size.height)) )//both bottom-relative
	{//check for and start resizing
		dragResizing = YES;
	}
	else if( CGRectIsEmpty(closeBox) || //empty close box = whole area is closing
		((locationInWindow.x >= closeBox.origin.x) && (locationInWindow.x <= (closeBox.origin.x+closeBox.size.width)) &&
		 (topY >= closeBox.origin.y) && (topY <= (closeBox.origin.y+closeBox.size.height)) ) )
	{//close the window
		[self orderOut:self];
		return;
	}
	
	//drag moving:

	//grab the mouse location in global coordinates
	initialLocation = [self convertPointToScreen:locationInWindow];
   
	if(!dragResizing)
	{//remebers origin relative offset of our click in window
		initialLocation.x -= windowFrame.origin.x;
		initialLocation.y -= windowFrame.origin.y;
	}
}


@end

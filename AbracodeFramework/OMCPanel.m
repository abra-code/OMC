//
//  OMCPanel.m
//  Abracode
//
//  Created by Tomasz Kukielka on 5/25/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#import "OMCPanel.h"
#import "OMCWindow.h"

@implementation OMCPanel

- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)aStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag
{
	//NSLog(@"OMCPanel initWithContentRect 1");
	
	self = [super initWithContentRect:contentRect styleMask:aStyle backing:bufferingType defer:flag];
	if(self == nil)
		return nil;

	useFadeIn = NO;
	useFadeOut = NO;

	return self;
}

- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)aStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag screen:(NSScreen *)screen
{
	//NSLog(@"OMCPanel initWithContentRect 2");
	
	self = [super initWithContentRect:contentRect styleMask:aStyle backing:bufferingType defer:flag screen:screen];
	if(self == nil)
		return nil;
	useFadeIn = NO;
	useFadeOut = NO;

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
	NSLog(@"OMCPanel makeKeyAndOrderFront");
#endif

	if(useFadeIn)
	{
		NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:self, NSViewAnimationTargetKey,
							  NSViewAnimationFadeInEffect, NSViewAnimationEffectKey,
							  nil];
		
		NSViewAnimation *fadeInAnimation = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:dict]];
		[fadeInAnimation setAnimationBlockingMode:NSAnimationNonblocking];
		//		[fadeInAnimation setDelegate:self];
		[self setAlphaValue: 0.0];
		[fadeInAnimation startAnimation];
	}
	
	[super makeKeyAndOrderFront:sender];
	[OMCWindow addWindow];
}

/*
- (void)orderFront:(id)sender
{
#if _DEBUG_
	NSLog(@"OMCPanel orderFront");
#endif
	if(useFadeIn)
	{
		NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:self, NSViewAnimationTargetKey,
							  NSViewAnimationFadeInEffect, NSViewAnimationEffectKey,
							  nil];
		
		NSViewAnimation *fadeInAnimation = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:dict]];
		[fadeInAnimation setAnimationBlockingMode:NSAnimationNonblocking];
		//		[fadeInAnimation setDelegate:self];
		[self setAlphaValue: 0.0];
		[fadeInAnimation startAnimation];
		[fadeInAnimation release];
	}
	
	[super orderFront:sender];	
}
*/

//NSAnimation delegate method

- (void)animationDidStop:(NSAnimation*)animation
{
    [self animationDidEnd:animation];
}

-(void)animationDidEnd:(NSAnimation *)animation
{
	//NSLog(@"OMCPanel animationDidEnd");
	if(animation == self.fadeOutAnimation)
	{
		self.fadeOutAnimation = nil;
		[super orderOut:self];
	}
}

- (void)orderOut:(id)sender
{
	//NSLog(@"OMCPanel orderOut");
	if(useFadeOut)
	{
		NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:self, NSViewAnimationTargetKey,
							  NSViewAnimationFadeOutEffect, NSViewAnimationEffectKey,
							  nil];
		
		self.fadeOutAnimation = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:dict]];
		[self.fadeOutAnimation setAnimationBlockingMode:NSAnimationNonblocking];
		[self.fadeOutAnimation setDelegate:self];
		[self.fadeOutAnimation startAnimation];
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

@end

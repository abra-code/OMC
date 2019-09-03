//
//  OMCWindow.m
//  Abracode
//
//  Created by Tomasz Kukielka on 5/24/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#import "OMCWindow.h"
#include <Carbon/Carbon.h>

static int sWindowCount = 0;

@implementation OMCWindow

- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)aStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag
{
	//NSLog(@"OMCWindow initWithContentRect 1");
	
	self = [super initWithContentRect:contentRect styleMask:aStyle backing:bufferingType defer:flag];
	if(self == nil)
		return nil;

	useFadeIn = NO;
	useFadeOut = NO;
	_fadeOutAnimation = nil;

	return self;
}

- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)aStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag screen:(NSScreen *)screen
{
	//NSLog(@"OMCWindow initWithContentRect 2");

	self = [super initWithContentRect:contentRect styleMask:aStyle backing:bufferingType defer:flag screen:screen];
	if(self == nil)
		return nil;

	useFadeIn = NO;
	useFadeOut = NO;
	_fadeOutAnimation = nil;
	
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
	NSLog(@"OMCWindow makeKeyAndOrderFront");
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
	//NSLog(@"OMCWindow animationDidEnd");
	if(animation == _fadeOutAnimation)
	{
		[_fadeOutAnimation release];
		_fadeOutAnimation = NULL;
		[super orderOut:self];
	}
}

- (void)orderOut:(id)sender
{
	//NSLog(@"OMCWindow orderOut");
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


+(void)addWindow
{
	sWindowCount++;
}

+(void)removeWindow
{
	sWindowCount--;
}

+(int)getWindowCount
{
	return sWindowCount;
}


@end

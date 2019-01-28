//
//  OMCCustomWindow.h
//  Abracode
//
//  Created by Tomasz Kukielka on 5/24/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//


#import <Cocoa/Cocoa.h>

struct OutputWindowSettings;


@interface OMCCustomWindow : NSWindow <NSAnimationDelegate>
{
	BOOL useFadeIn;
	BOOL useFadeOut;
	
	NSViewAnimation *_fadeOutAnimation;//temporary object present at closing, not owned

	CGRect		textBox;//top-left relative
	CGRect		closeBox; //top-left relative
	CGRect		resizeBox;//bottom-right relative

	NSPoint initialLocation;
	BOOL	dragResizing;
}

-(id)initWithSettings:(const OutputWindowSettings *)inSettings;
-(void)setFadeIn:(BOOL)inFadeIn;
-(void)setFadeOut:(BOOL)inFadeOut;

@end

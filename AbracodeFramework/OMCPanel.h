//
//  OMCPanel.h
//  Abracode
//
//  Created by Tomasz Kukielka on 5/25/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface OMCPanel : NSPanel <NSAnimationDelegate>
{
	BOOL useFadeIn;
	BOOL useFadeOut;
}

@property (strong) NSViewAnimation *fadeOutAnimation;

-(void)setFadeIn:(BOOL)inFadeIn;
-(void)setFadeOut:(BOOL)inFadeOut;

@end

//
//  OMCWindow.h
//  Abracode
//
//  Created by Tomasz Kukielka on 5/24/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface OMCWindow : NSWindow <NSAnimationDelegate>
{
	BOOL useFadeIn;
	BOOL useFadeOut;
}

@property (strong) NSViewAnimation *fadeOutAnimation;

-(void)setFadeIn:(BOOL)inFadeIn;
-(void)setFadeOut:(BOOL)inFadeOut;

+(void)addWindow;
+(void)removeWindow;
+(int)getWindowCount;

@end

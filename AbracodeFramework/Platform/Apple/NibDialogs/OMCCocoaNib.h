//
//  OMCCocoaNib.h
//  Abracode
//
//  Created by Tomasz Kukielka on 1/17/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface OMCCocoaNib : NSObject

@property (nonatomic, strong) NSArray *topLevelNibObjects;

- (id)initWithNib:(NSNib *)inNib;
- (id)initWithNibNamed:(NSString *)inNibName bundle:(NSBundle *)inBundle;

- (NSWindow *)getFirstWindow;

@end

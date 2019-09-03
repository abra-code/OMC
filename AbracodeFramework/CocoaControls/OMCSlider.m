/*
	OMCSlider.m
*/

#import "OMCSlider.h"

@implementation OMCSlider

@synthesize commandID;

- (void)dealloc
{
    self.commandID = nil;
    [super dealloc];
}

@end

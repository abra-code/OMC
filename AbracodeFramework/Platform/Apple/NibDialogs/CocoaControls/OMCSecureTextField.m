/*
	OMCSecureTextField.m
*/

#import "OMCSecureTextField.h"

@implementation OMCSecureTextField

- (id)init
{
    self = [super init];
	if(self == nil)
		return nil;

 	self.escapingMode = @"esc_none";

	return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == nil)
		return nil;

	self.escapingMode = @"esc_none";

    return self;
}

@end

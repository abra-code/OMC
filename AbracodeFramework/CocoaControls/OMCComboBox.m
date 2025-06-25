/*
	OMCComboBox.m
*/

#import "OMCComboBox.h"

@implementation OMCComboBox

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

/*
- (BOOL)prepareForDragOperation:(id < NSDraggingInfo >)sender
{
	BOOL isAccepted = [super prepareForDragOperation:sender];
	if(isAccepted)
		NSLog(@"Drag accepted by OMCTextField = 0x%x", (void *)self);
	else
		NSLog(@"Drag rejected by OMCTextField = 0x%x", (void *)self);

	return isAccepted;
}
*/

//do not execute the action if the value string has not changed since last execution
-(BOOL)shouldExecuteAction
{
	BOOL shouldExecute = YES;
	NSString *newValue = [self stringValue];
	if( self.lastValue != nil )
	{
		shouldExecute = ![self.lastValue isEqualToString:newValue];
	}
	
    self.lastValue = newValue;
	
	return shouldExecute;
}

@end

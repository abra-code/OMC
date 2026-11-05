/*
	OMCTextField.m
*/

#import "OMCTextField.h"

@implementation OMCTextField

- (id)init
{
    self = [super init];
	if(self == nil)
		return nil;

 	self.escapingMode = @"esc_none";

	return self;
}

//legacy encoder/decoder support - custom control data no longer serialized into nibs
//custom properties get set later on nib load by calling proprty setters

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

@end

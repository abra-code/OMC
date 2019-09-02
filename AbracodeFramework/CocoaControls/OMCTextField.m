/*
	OMCTextField.m
*/

#import "OMCTextField.h"

@implementation OMCTextField

@synthesize commandID, escapingMode;

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;
	commandID = NULL;
 	self.escapingMode = @"esc_none";
	return self;
}

- (void)dealloc
{
    [commandID release];
	[escapingMode release];
    [super dealloc];
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

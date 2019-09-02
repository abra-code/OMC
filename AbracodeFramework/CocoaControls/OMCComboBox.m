/*
	OMCComboBox.m
*/

#import "OMCComboBox.h"

@implementation OMCComboBox

@synthesize commandID, escapingMode;

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;
	commandID = NULL;
 	self.escapingMode = @"esc_none";
	_lastValue = NULL;
	return self;
}

- (void)dealloc
{
    [commandID release];
	[escapingMode release];
	[_lastValue release];
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

//do not execute the action if the value string has not changed since last execution
-(BOOL)shouldExecuteAction
{
	BOOL shouldExecute = YES;
	NSString *newValue = [self stringValue];
	if( _lastValue != NULL )
	{
		shouldExecute = ![_lastValue isEqualToString:newValue];
		[_lastValue release];
	}
	
	_lastValue = [newValue retain];
	
	return shouldExecute;
}

@end

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

//legacy encoder/decoder support - custom control data no longer serialized into nibs
//custom properties get set later on nib load by calling proprty setters

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == NULL)
		return NULL;

    if( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed decoding"];

	self.commandID = [coder decodeObjectForKey:@"omcCommandID"];
	self.escapingMode = [coder decodeObjectForKey:@"omcEscapingMode"];
	if(escapingMode == NULL)
		self.escapingMode = @"esc_none";//use default if key not present

	_lastValue = NULL;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    if( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed encoding"];

	if(commandID != NULL)
		[coder encodeObject:commandID forKey:@"omcCommandID"];

	if(escapingMode == NULL)
		self.escapingMode = @"esc_none";
	
	[coder encodeObject:escapingMode forKey:@"omcEscapingMode"];
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

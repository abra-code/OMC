/*
	OMCSecureTextField.m
*/

#import "OMCSecureTextField.h"

@implementation OMCSecureTextField

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

@end

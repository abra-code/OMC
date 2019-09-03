/*
	OMCButtonCell.m
*/

#import "OMCButtonCell.h"
#import <AppKit/AppKit.h>

@implementation OMCButtonCell

@synthesize commandID;
@synthesize mappedOnValue;
@synthesize mappedOffValue;
@synthesize escapingMode;

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

- (void)dealloc
{
    self.commandID = nil;
    self.mappedOnValue = nil;
    self.mappedOffValue = nil;
 	self.escapingMode = nil;
	[super dealloc];
}

//a subclass of NSCell must implement copying

- (id)copyWithZone:(NSZone *)zone
{
	OMCButtonCell *objCopy = [super copyWithZone:zone];

	[objCopy.commandID retain];
	[objCopy.mappedOnValue retain];
	[objCopy.mappedOffValue retain];
	[objCopy.escapingMode retain];

	return objCopy;
}

//overriding NSControl methods to include mapped values

- (NSString *)stringValue
{
	int intValue = [self intValue];
	if( (intValue > 0) && (self.mappedOnValue != nil) )
		return self.mappedOnValue;
	else if( (intValue == 0) && (mappedOffValue != nil) )
		return self.mappedOffValue;
		
	return [super stringValue];
}

- (void)setStringValue:(NSString *)aString
{
	if(aString == nil)
		return;
		
	if([self.mappedOnValue isEqualToString:aString])
	{
		[self setIntValue:1];
	}
	else if([self.mappedOffValue isEqualToString:aString])
	{
		[self setIntValue:0];
	}
	else
	{
		[super setStringValue:aString];
	}
}

@end

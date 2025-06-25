/*
	OMCButtonCell.m
*/

#import "OMCButtonCell.h"
#import <AppKit/AppKit.h>

@implementation OMCButtonCell

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

//a subclass of NSCell must implement copying

- (id)copyWithZone:(NSZone *)zone
{
	OMCButtonCell *objCopy = [super copyWithZone:zone];

    objCopy->_commandID = [_commandID copyWithZone:zone];
    objCopy->_mappedOnValue = [_mappedOnValue copyWithZone:zone];
    objCopy->_mappedOffValue = [_mappedOffValue copyWithZone:zone];
    objCopy->_escapingMode = [_escapingMode copyWithZone:zone];

	return objCopy;
}

//overriding NSControl methods to include mapped values

- (NSString *)stringValue
{
	int intValue = [self intValue];
	if( (intValue > 0) && (self.mappedOnValue != nil) )
		return self.mappedOnValue;
	else if( (intValue == 0) && (self.mappedOffValue != nil) )
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

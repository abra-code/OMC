/*
	OMCTableView.m
*/

#import "OMCTableView.h"

@implementation OMCTableView

@synthesize selectionCommandID;
@synthesize doubleClickCommandID;
@synthesize combinedSelectionPrefix;
@synthesize combinedSelectionSuffix;
@synthesize combinedSelectionSeparator;
@synthesize multipleColumnPrefix;
@synthesize multipleColumnSuffix;
@synthesize multipleColumnSeparator;
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

- (NSString *)stringValue
{		
	return [super stringValue];
}

- (void)setStringValue:(NSString *)aString
{
	if(aString == nil)
		return;
		
	[super setStringValue:aString];
}

@end

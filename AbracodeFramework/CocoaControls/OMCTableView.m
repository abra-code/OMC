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

- (void)dealloc
{
    self.selectionCommandID = nil;
	self.doubleClickCommandID = nil;
	self.combinedSelectionPrefix = nil;
	self.combinedSelectionSuffix = nil;
	self.combinedSelectionSeparator = nil;
	self.multipleColumnPrefix = nil;
	self.multipleColumnSuffix = nil;
	self.multipleColumnSeparator = nil;
	self.escapingMode = nil;

    [super dealloc];
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

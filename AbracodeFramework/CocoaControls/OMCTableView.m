/*
	OMCTableView.m
*/

#import "OMCTableView.h"

@implementation OMCTableView

//let the compiler implement setter and getter methods:
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
	if(self == NULL)
		return NULL;
	selectionCommandID = NULL;
	doubleClickCommandID = NULL;
	combinedSelectionPrefix = NULL;
	combinedSelectionSuffix = NULL;
	combinedSelectionSeparator = NULL;
	multipleColumnPrefix = NULL;
	multipleColumnSuffix = NULL;
	multipleColumnSeparator = NULL;
	escapingMode = @"esc_none";
	[escapingMode retain];
    return self;
}

- (void)dealloc
{
    [selectionCommandID release];
	[doubleClickCommandID release];
	[combinedSelectionPrefix release];
	[combinedSelectionSuffix release];
	[combinedSelectionSeparator release];
	[multipleColumnPrefix release];
	[multipleColumnSuffix release];
	[multipleColumnSeparator release];
	[escapingMode release];
    [super dealloc];
}


- (NSString *)stringValue
{		
	return [super stringValue];
}


- (void)setStringValue:(NSString *)aString
{
	if(aString == NULL)
		return;
		
	[super setStringValue:aString];
}

@end

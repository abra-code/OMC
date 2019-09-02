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

//legacy encoder/decoder support - custom control data no longer serialized into nibs
//custom properties get set later on nib load by calling proprty setters

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == NULL)
		return NULL;

    if( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed decoding"];

	[self setSelectionCommandID: [coder decodeObjectForKey:@"omcSelectionCommandID"]];
	[self setDoubleClickCommandID: [coder decodeObjectForKey:@"omcDoubleClickCommandID"]];
	[self setCombinedSelectionPrefix: [coder decodeObjectForKey:@"omcCombinedSelectionPrefix"]]; 
	[self setCombinedSelectionSuffix: [coder decodeObjectForKey:@"omcCombinedSelectionSuffix"]];
	[self setCombinedSelectionSeparator: [coder decodeObjectForKey:@"omcCombinedSelectionSeparator"]];
	[self setMultipleColumnPrefix: [coder decodeObjectForKey:@"omcMultipleColumnPrefix"]];
	[self setMultipleColumnSuffix: [coder decodeObjectForKey:@"omcMultipleColumnSuffix"]];
	[self setMultipleColumnSeparator: [coder decodeObjectForKey:@"omcMultipleColumnSeparator"]];

	NSString *newEscapingMode = [coder decodeObjectForKey:@"omcEscapingMode"];
	if(newEscapingMode == NULL)
		newEscapingMode = @"esc_none";//use default if key not present
	[self setEscapingMode:newEscapingMode];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    if( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed encoding"];

	if(selectionCommandID != NULL)
		[coder encodeObject:selectionCommandID forKey:@"omcSelectionCommandID"];

	if(doubleClickCommandID != NULL)
		[coder encodeObject:doubleClickCommandID forKey:@"omcDoubleClickCommandID"];

	if(combinedSelectionPrefix != NULL)
		[coder encodeObject:combinedSelectionPrefix forKey:@"omcCombinedSelectionPrefix"];

	if(combinedSelectionSuffix != NULL)
		[coder encodeObject:combinedSelectionSuffix forKey:@"omcCombinedSelectionSuffix"];

	if(combinedSelectionSeparator != NULL)
		[coder encodeObject:combinedSelectionSeparator forKey:@"omcCombinedSelectionSeparator"];

	if(multipleColumnPrefix != NULL)
		[coder encodeObject:multipleColumnPrefix forKey:@"omcMultipleColumnPrefix"];

	if(multipleColumnSuffix != NULL)
		[coder encodeObject:multipleColumnSuffix forKey:@"omcMultipleColumnSuffix"];

	if(multipleColumnSeparator != NULL)
		[coder encodeObject:multipleColumnSeparator forKey:@"omcMultipleColumnSeparator"];

	if(escapingMode == NULL)
		[self setEscapingMode:@"esc_none"];
	
	[coder encodeObject:escapingMode forKey:@"omcEscapingMode"];
}

@end

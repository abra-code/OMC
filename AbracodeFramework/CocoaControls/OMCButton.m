/*
	OMCButton.m
*/

#import "OMCButton.h"

@implementation OMCButton

@synthesize commandID, mappedOnValue, mappedOffValue, escapingMode, acceptFileDrop, acceptTextDrop, droppedItems;

- (id)init
{
    self = [super init];
	if(self == nil)
		return nil;

	commandID = nil;
	mappedOnValue = nil;
	mappedOffValue = nil;
	escapingMode = @"esc_none";
	[escapingMode retain];
	
	acceptFileDrop = NO;
	acceptTextDrop = NO;
	droppedItems = nil;

    return self;
}

- (void)dealloc
{
    [commandID release];
    [mappedOnValue release];
    [mappedOffValue release];
	[escapingMode release];
	[droppedItems release];
    [super dealloc];
}

//overriding NSControl methods to include mapped values
- (NSString *)stringValue
{
	int intValue = [self intValue];
	if( (intValue > 0) && (mappedOnValue != NULL) )
		return mappedOnValue;
	else if( (intValue == 0) && (mappedOffValue != NULL) )
		return mappedOffValue;
		
	return [super stringValue];
}


- (void)setStringValue:(NSString *)aString
{
	if(aString == NULL)
		return;
		
	if( (mappedOnValue != NULL) && [mappedOnValue isEqualToString:aString] )
	{
		[self setIntValue:1];
	}
	else if( (mappedOffValue != NULL) && [mappedOffValue isEqualToString:aString] )
	{
		[self setIntValue:0];
	}
	else
	{
		[super setStringValue:aString];
	}
}

//legacy encoder/decoder support - custom control data no longer serialized into nibs
//custom properties get set later on nib load by calling proprty setters

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == nil)
		return nil;

    if( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed decoding"];

	commandID = [[coder decodeObjectForKey:@"omcCommandID"] retain];
	mappedOnValue = [[coder decodeObjectForKey:@"omcMappedOnValue"] retain];
	mappedOffValue = [[coder decodeObjectForKey:@"omcMappedOffValue"] retain];
	escapingMode = [[coder decodeObjectForKey:@"omcEscapingMode"] retain];
	if(escapingMode == nil)
	{
		escapingMode = @"esc_none";//use default if key not present
		[escapingMode retain];
	}

	acceptFileDrop = NO;
	acceptTextDrop = NO;
	droppedItems = nil;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    if( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed encoding"];

	if(commandID != NULL)
		[coder encodeObject:commandID forKey:@"omcCommandID"];

	if(mappedOnValue != NULL)
		[coder encodeObject:mappedOnValue forKey:@"omcMappedOnValue"];

	if(mappedOffValue != NULL)
		[coder encodeObject:mappedOffValue forKey:@"omcMappedOffValue"];

	if(escapingMode == NULL)
	{
		escapingMode = @"esc_none";
		[escapingMode retain];
	}
	
	[coder encodeObject:escapingMode forKey:@"omcEscapingMode"];
}

- (void)awakeFromNib
{
	if(acceptFileDrop || acceptTextDrop)
	{
		NSMutableArray *typesArray = [NSMutableArray array];
		if(acceptFileDrop)
			[typesArray addObject:NSURLPboardType];
		if(acceptTextDrop)
			[typesArray addObject:NSPasteboardTypeString];
		[self registerForDraggedTypes:typesArray];
	}
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
	//new drag, new context
	self.droppedItems = nil;

    NSPasteboard *pboard = [sender draggingPasteboard];
	NSArray *pboardTypes = [pboard types];
    if( (acceptFileDrop && [pboardTypes containsObject:NSURLPboardType]) ||
		(acceptTextDrop && [pboardTypes containsObject:NSPasteboardTypeString]) )
	{
		[self highlight:YES];
    	return NSDragOperationGeneric;
	}
	return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
	[self highlight:NO];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];
	NSArray *pboardTypes = [pboard types];
    if( (acceptFileDrop && [pboardTypes containsObject:NSURLPboardType]) ||
		(acceptTextDrop && [pboardTypes containsObject:NSPasteboardTypeString]) )
	{
		return YES;
	}
	return NO;
}


- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];
	NSArray *pboardTypes = [pboard types];
    if (acceptFileDrop && [pboardTypes containsObject:NSURLPboardType])
    {
        NSArray *urls = [pboard readObjectsForClasses:@[[NSURL class]] options:nil];
		self.droppedItems = urls;
        //NSLog(@"URLs are: %@", urls);
		[self performClick:self];
    }
    else if (acceptTextDrop && [pboardTypes containsObject:NSPasteboardTypeString])
    {
       //NSArray* strings = [pboard readObjectsForClasses:@[[NSString class]] options:nil];
	   NSString* string = [pboard stringForType:NSPasteboardTypeString];
	   self.droppedItems = string;
       //NSLog(@"String is: %@", string);
	   [self performClick:self];
    }
	else
	{
		//should not happen: ending up with unsupported drag type
		self.droppedItems = nil;
	}

    return YES;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
	[self highlight:NO];
}

@end

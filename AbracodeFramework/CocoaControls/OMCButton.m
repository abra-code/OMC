/*
	OMCButton.m
*/

#import "OMCButton.h"

@implementation OMCButton

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
	else if([self.mappedOffValue isEqualToString:aString] )
	{
		[self setIntValue:0];
	}
	else
	{
		[super setStringValue:aString];
	}
}


- (void)awakeFromNib
{
	if(self.acceptFileDrop || self.acceptTextDrop)
	{
		NSMutableArray *typesArray = [NSMutableArray array];
		if(self.acceptFileDrop)
			[typesArray addObject:NSURLPboardType];
		if(self.acceptTextDrop)
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
    if( (self.acceptFileDrop && [pboardTypes containsObject:NSURLPboardType]) ||
		(self.acceptTextDrop && [pboardTypes containsObject:NSPasteboardTypeString]) )
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
    if( (self.acceptFileDrop && [pboardTypes containsObject:NSURLPboardType]) ||
		(self.acceptTextDrop && [pboardTypes containsObject:NSPasteboardTypeString]) )
	{
		return YES;
	}
	return NO;
}


- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];
	NSArray *pboardTypes = [pboard types];
    if (self.acceptFileDrop && [pboardTypes containsObject:NSURLPboardType])
    {
        NSArray *urls = [pboard readObjectsForClasses:@[[NSURL class]] options:nil];
		self.droppedItems = urls;
        //NSLog(@"URLs are: %@", urls);
		[self performClick:self];
    }
    else if (self.acceptTextDrop && [pboardTypes containsObject:NSPasteboardTypeString])
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

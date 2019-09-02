/*
	OMCImageView.m
*/

#import "OMCImageView.h"

@implementation OMCImageView

@synthesize commandID, escapingMode;

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;
	escapingMode = @"esc_none";
	[escapingMode retain];
	commandID = NULL;
	imagePath = NULL;
	return self;
}

- (void)dealloc
{
	[escapingMode release];
    [commandID release];

	if(imagePath != NULL)
		[imagePath release];

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

	imagePath = NULL;

	commandID = [[coder decodeObjectForKey:@"omcCommandID"] retain];
	
	escapingMode = [[coder decodeObjectForKey:@"omcEscapingMode"] retain];
	if(escapingMode == NULL)
	{
		escapingMode = @"esc_none";//use default if key not present
		[escapingMode retain];
	}

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    if ( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed encoding"];

	if(commandID != NULL)
		[coder encodeObject:commandID forKey:@"omcCommandID"];

	if(escapingMode == NULL)
	{
		escapingMode = @"esc_none";
		[escapingMode retain];
	}
	
	[coder encodeObject:escapingMode forKey:@"omcEscapingMode"];
}

//override NSControl methods
- (NSString *)stringValue
{
	return imagePath;
}

- (void)setStringValue:(NSString *)aString
{

//	NSLog(@"image name = %@", [[self image] name]);

	if(imagePath != NULL)
	{
		[imagePath release];
		imagePath = NULL;
	}
	imagePath = aString;
	
	if(imagePath != NULL)
	{
		[imagePath retain];

		NSImage *myImage = [[NSImage alloc] initWithContentsOfFile:imagePath];

		if(myImage == NULL)
			NSLog(@"OMCImageView failed to load image at \"%@\"", imagePath);
		[self setImage:myImage];
		
//		NSLog(@"image name = %@", [myImage name]);
		
		[myImage release];
	}
	else
	{
		[self setImage:NULL];
	}
}

@end

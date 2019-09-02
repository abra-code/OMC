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

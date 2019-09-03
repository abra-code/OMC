/*
	OMCImageView.m
*/

#import "OMCImageView.h"

@implementation OMCImageView

@synthesize commandID;
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
	self.escapingMode = nil;
	self.commandID = nil;
	[_imagePath release];
    [super dealloc];
}

//override NSControl methods
- (NSString *)stringValue
{
	return _imagePath;
}

- (void)setStringValue:(NSString *)aString
{
//	NSLog(@"image name = %@", [[self image] name]);

	if(_imagePath != nil)
	{
		[_imagePath release];
		_imagePath = nil;
	}
	_imagePath = aString;
	
	if(_imagePath != nil)
	{
		[_imagePath retain];

		NSImage *myImage = [[NSImage alloc] initWithContentsOfFile:_imagePath];

		if(myImage == NULL)
			NSLog(@"OMCImageView failed to load image at \"%@\"", _imagePath);
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

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

//override NSControl methods
- (NSString *)stringValue
{
	return _imagePath;
}

- (void)setStringValue:(NSString *)aString
{
//	NSLog(@"image name = %@", [[self image] name]);

	self.imagePath = aString;
	
	if(self.imagePath != nil)
	{
		NSImage *myImage = [[NSImage alloc] initWithContentsOfFile:self.imagePath];

		if(myImage == nil)
			NSLog(@"OMCImageView failed to load image at \"%@\"", self.imagePath);
		[self setImage:myImage];
		
//		NSLog(@"image name = %@", [myImage name]);
    }
	else
	{
		[self setImage:nil];
	}
}

@end

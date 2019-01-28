/*
	OMCQTMovieView.m
*/

#import "OMCQTMovieView.h"

@implementation OMCQTMovieView

@synthesize tag = _omcTag, escapingMode;

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;
    _omcTag = 0;
	escapingMode = @"esc_none";
	[escapingMode retain];
	return self;
}

- (void)dealloc
{
	[escapingMode release];
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
	
	_omcTag = [coder decodeIntForKey:@"omcTag"];
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

	[coder encodeInt:_omcTag forKey:@"omcTag"];

	if(escapingMode == NULL)
	{
		escapingMode = @"esc_none";
		[escapingMode retain];
	}
	
	[coder encodeObject:escapingMode forKey:@"omcEscapingMode"];
}

- (NSString *)stringValue
{
	QTMovie *qtMovie = [self movie];
	if(qtMovie == NULL)
		return NULL;

	NSURL *movieURL = [qtMovie attributeForKey:QTMovieURLAttribute];
	if(movieURL == NULL)
		return NULL;
	
	return [movieURL path];
}

- (void)setStringValue:(NSString *)aString
{
	QTMovie *qtMovie = [QTMovie movieWithFile:aString error:NULL];
	if(qtMovie == NULL)
		return;

	[self setMovie:qtMovie];
}


@end

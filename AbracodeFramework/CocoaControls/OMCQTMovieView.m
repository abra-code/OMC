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

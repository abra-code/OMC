/*
	OMCQTMovieView.m
*/

#import "OMCQTMovieView.h"

@implementation OMCQTMovieView

@synthesize tag;

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
    [super dealloc];
}

- (NSString *)stringValue
{
	QTMovie *qtMovie = [self movie];
	if(qtMovie == nil)
		return nil;

	NSURL *movieURL = [qtMovie attributeForKey:QTMovieURLAttribute];
	if(movieURL == nil)
		return nil;
	
	return [movieURL path];
}

- (void)setStringValue:(NSString *)aString
{
	QTMovie *qtMovie = [QTMovie movieWithFile:aString error:NULL];
	if(qtMovie == nil)
		return;

	[self setMovie:qtMovie];
}


@end

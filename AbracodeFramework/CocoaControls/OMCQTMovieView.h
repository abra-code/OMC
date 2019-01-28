/*
	OMCQTMovieView.h
*/

#import <Cocoa/Cocoa.h>
#import <QTKit/QTKit.h>

IB_DESIGNABLE
@interface OMCQTMovieView : QTMovieView
{
	NSInteger	_omcTag;
	NSString *  escapingMode;
}

@property(readwrite) IBInspectable NSInteger tag;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;

@end

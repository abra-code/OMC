/*
	OMCQTMovieView.h
*/

#import <Cocoa/Cocoa.h>
#import <QTKit/QTKit.h>

IB_DESIGNABLE
@interface OMCQTMovieView : QTMovieView

@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, strong) IBInspectable NSString * escapingMode;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;

@end

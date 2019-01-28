/*
	OMCIKImageView.h
*/

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>

IB_DESIGNABLE
@interface OMCIKImageView : IKImageView
{
	NSInteger	_omcTag;
	NSString *  escapingMode;
}

//no tag in IKImageView - OMC extension
@property(readwrite) IBInspectable NSInteger tag;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;

@end

/*
	OMCImageView.h
*/

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>

IB_DESIGNABLE
@interface OMCImageView : NSImageView
{
	NSString *	commandID;
	NSString *  escapingMode;
	NSString *	imagePath;
}

@property (nonatomic, retain) IBInspectable NSString * commandID;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;

@end

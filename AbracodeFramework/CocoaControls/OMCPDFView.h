/*
	OMCPDFView.h
*/

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>

IB_DESIGNABLE
@interface OMCPDFView : PDFView
{
	NSInteger	_omcTag;
	NSString *  escapingMode;
}

@property(readwrite) IBInspectable NSInteger tag;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;

@end

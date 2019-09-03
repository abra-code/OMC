/*
	OMCQCView.h
*/

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>

IB_DESIGNABLE
@interface OMCQCView : QCView
{
	id			_omcTarget;
	SEL			_omcTargetSelector;
	NSString *	_compositionPath;
}

- (id)target;
- (void)setTarget:(id)anObject;

- (void)setAction:(SEL)aSelector;

@property (nonatomic, retain) IBInspectable NSString * commandID;
@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;


@end

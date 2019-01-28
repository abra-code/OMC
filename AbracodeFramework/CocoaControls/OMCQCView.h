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
	NSString *	commandID; //only for OMC Subcommand QC plug-in
	NSInteger	_omcTag;
	NSString *  escapingMode;
	NSString *	compositionPath;
}

- (id)target;
- (void)setTarget:(id)anObject;

- (void)setAction:(SEL)aSelector;

@property (nonatomic, retain) IBInspectable NSString * commandID;
@property(readwrite) IBInspectable NSInteger tag;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;


@end

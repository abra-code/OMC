/*
	OMCQCView.h
*/

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import "OMCActionProtocol.h"

IB_DESIGNABLE
@interface OMCQCView : QCView<OMCActionProtocol>

@property (nonatomic, assign) SEL action;
@property (nonatomic, weak) id target;
@property (nonatomic, strong) NSString *compositionPath;

@property (nonatomic, readwrite) IBInspectable NSInteger tag;
@property (nonatomic, strong) IBInspectable NSString * commandID;
@property (nonatomic, strong) IBInspectable NSString * escapingMode;

- (NSString *)stringValue;
- (void)setStringValue:(NSString *)aString;


@end

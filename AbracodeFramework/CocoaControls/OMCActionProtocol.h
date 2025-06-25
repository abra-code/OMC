/*
	OMCActionProtocol.h
*/

#import <Cocoa/Cocoa.h>

@protocol OMCActionProtocol

@required
@property (nonatomic, assign) SEL action;

@optional
@property (nonatomic, weak) id target;

@end

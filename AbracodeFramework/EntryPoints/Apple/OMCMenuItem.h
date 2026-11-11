/*
	OMCMenuItem.h
*/

#import <Cocoa/Cocoa.h>

@interface OMCMenuItem : NSMenuItem

@property (nonatomic, strong) NSString * commandID;
@property (nonatomic, strong) NSString * mappedValue;
@property (nonatomic, strong) NSString * escapingMode;

@end


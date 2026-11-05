/*
	OMCComboBox.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCComboBox : NSComboBox

@property (nonatomic, strong) NSString *lastValue;
@property (nonatomic, strong) IBInspectable NSString * commandID;
@property (nonatomic, strong) IBInspectable NSString * escapingMode;

-(BOOL)shouldExecuteAction;

@end

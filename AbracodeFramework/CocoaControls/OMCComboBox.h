/*
	OMCComboBox.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCComboBox : NSComboBox
{
	NSString *	_lastValue;
}

@property (nonatomic, retain) IBInspectable NSString * commandID;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

-(BOOL)shouldExecuteAction;

@end

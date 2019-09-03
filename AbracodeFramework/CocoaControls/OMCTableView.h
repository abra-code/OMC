/*
	OMCTableView.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCTableView : NSTableView
{
}

@property (nonatomic, retain) IBInspectable NSString * selectionCommandID;
@property (nonatomic, retain) IBInspectable NSString * doubleClickCommandID;
@property (nonatomic, retain) IBInspectable NSString * combinedSelectionPrefix;
@property (nonatomic, retain) IBInspectable NSString * combinedSelectionSuffix;
@property (nonatomic, retain) IBInspectable NSString * combinedSelectionSeparator;
@property (nonatomic, retain) IBInspectable NSString * multipleColumnPrefix;
@property (nonatomic, retain) IBInspectable NSString * multipleColumnSuffix;
@property (nonatomic, retain) IBInspectable NSString * multipleColumnSeparator;
@property (nonatomic, retain) IBInspectable NSString * escapingMode;

@end

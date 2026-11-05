/*
	OMCTableView.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCTableView : NSTableView

@property (nonatomic, strong) IBInspectable NSString * selectionCommandID;
@property (nonatomic, strong) IBInspectable NSString * doubleClickCommandID;
@property (nonatomic, strong) IBInspectable NSString * combinedSelectionPrefix;
@property (nonatomic, strong) IBInspectable NSString * combinedSelectionSuffix;
@property (nonatomic, strong) IBInspectable NSString * combinedSelectionSeparator;
@property (nonatomic, strong) IBInspectable NSString * multipleColumnPrefix;
@property (nonatomic, strong) IBInspectable NSString * multipleColumnSuffix;
@property (nonatomic, strong) IBInspectable NSString * multipleColumnSeparator;
@property (nonatomic, strong) IBInspectable NSString * escapingMode;

@end

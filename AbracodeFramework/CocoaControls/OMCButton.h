/*
	OMCButton.h
*/

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCButton : NSButton <NSDraggingDestination>
{
}

@property (nonatomic, strong) IBInspectable NSString * commandID;
@property (nonatomic, strong) IBInspectable NSString * mappedOnValue;
@property (nonatomic, strong) IBInspectable NSString * mappedOffValue;
@property (nonatomic, strong) IBInspectable NSString * escapingMode;
@property (nonatomic) BOOL IBInspectable acceptFileDrop;
@property (nonatomic) BOOL IBInspectable acceptTextDrop;
@property (nonatomic, strong) id droppedItems; //could be NSArray * for list of files or NSString * for text

@end


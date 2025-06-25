//
//  OMCTableViewController.h
//  Abracode
//
//  Created by Tomasz Kukielka on 9/13/09.
//  Copyright 2009-2010 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include "SelectionIterator.h"

typedef enum ColumnSeparatorFormat
{
	kOMCColumnSeparatorTab,
	kOMCColumnSeparatorComma,
	kOMCColumnSeparatorSpace
} ColumnSeparatorFormat;

@class OMCDialogController;

@interface OMCTableViewController : NSObject<NSTableViewDataSource, NSTableViewDelegate>
{
	ColumnSeparatorFormat mSeparator;
}

@property (nonatomic, weak) OMCDialogController *dialogController; //the dialog controller that owns us
@property (nonatomic, strong) NSTableView *tableView; //the table we control
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSArray *columnNames;
@property (nonatomic, strong) NSArray *columnWidths;
@property (nonatomic, strong) NSString *selectionChangeCommandID;

- (id)initWithTableView:(NSTableView *)aTableView dialogController:(OMCDialogController *)inController;

-(void)removeRows;
-(void)addRows:(CFArrayRef)inRowArray;
-(void)reloadData;
-(void)setColumns:(NSArray *)columnArray;
-(NSArray *)splitRowString:(NSString *)inRowString;
-(NSArray *)columnArrayForRow:(NSUInteger)inRowIndex;
-(id)selectionValueForColumn:(NSInteger)inColumnIndex withIterator:(SelectionIterator *)inSelIterator;
-(NSArray *)allRowsForColumn:(NSInteger)inColumnIndex;
-(NSString *)stringForRow:(NSUInteger)inRow column:(NSUInteger)inColumn prefix:(NSString *)colPrefix suffix:(NSString *)colSuffix separator:(NSString *)colSeparator;
-(NSUInteger)columnCount;

@end

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

@class OMCNibWindowController;

@interface OMCTableViewController : NSObject<NSTableViewDataSource, NSTableViewDelegate>
{
	ColumnSeparatorFormat mSeparator;
}

@property (nonatomic, weak) OMCNibWindowController *dialogController; //the dialog controller that owns us
@property (nonatomic, strong) NSTableView *tableView; //the table we control
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSArray *columnNames;
@property (nonatomic, strong) NSArray *columnWidths;
@property (nonatomic, strong) NSString *selectionChangeCommandID;

- (id)initWithTableView:(NSTableView *)aTableView dialogController:(OMCNibWindowController *)inController;

-(void)removeRows;
-(void)addRows:(CFArrayRef)inRowArray;
-(void)reloadData;
-(void)setColumns:(NSArray *)columnArray;

// Programmatic row selection. These suppress the selection-change command so programmatic
// selection is silent (matching the ActionUI path) — read the result back from the table.
-(void)selectRowByIndex:(NSInteger)inRowIndex;            // 0-based; out-of-range clears the selection
// inText matched (exact) against a row's column value(s). inColumnNumber is 1-based
// (mirrors $OMC_NIB_TABLE_<N>_COLUMN_<M>_VALUE); 0 or negative matches any column.
// Returns the 0-based index of the selected row, or -1 if no row matched.
-(NSInteger)selectRowWithContent:(NSString *)inText column:(NSInteger)inColumnNumber;
-(void)deselectAllRows;
-(NSArray *)splitRowString:(NSString *)inRowString;
-(NSArray *)columnArrayForRow:(NSUInteger)inRowIndex;
-(id)selectionValueForColumn:(NSInteger)inColumnIndex withIterator:(SelectionIterator *)inSelIterator;
-(NSArray *)allRowsForColumn:(NSInteger)inColumnIndex;
-(NSString *)stringForRow:(NSUInteger)inRow column:(NSUInteger)inColumn prefix:(NSString *)colPrefix suffix:(NSString *)colSuffix separator:(NSString *)colSeparator;
-(NSUInteger)columnCount;

@end

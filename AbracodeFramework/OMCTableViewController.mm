//
//  OMCTableViewController.m
//  Abracode
//
//  Created by Tomasz Kukielka on 9/13/09.
//  Copyright 2009-2010 Abracode. All rights reserved.
//

#import "OMCTableViewController.h"
#import "OMCTableView.h"
#import "OMCDialogController.h"


@implementation OMCTableViewController

- (id)initWithTableView:(NSTableView *)aTableView dialogController:(OMCDialogController *)inController
{
    self = [super init];
	if(self != NULL)
	{
		_tableView = aTableView;
		_dialogController = inController;//weak, it owns us and retain cause circular retain
		if( [_tableView isKindOfClass:[OMCTableView class]] )
		{
			OMCTableView *omcTableView  = (OMCTableView *)_tableView;
			_selectionChangeCommandID = [omcTableView selectionCommandID];
		}
		_rows = [[NSMutableArray alloc] init];
	}
    return self;
}

-(void)removeRows
{
	[self.rows removeAllObjects];
}

-(void)addRows:(CFArrayRef)inRowArray
{
    [self.rows addObjectsFromArray:(__bridge NSArray *)inRowArray]; //inRowArray is array of strings (unsplit) or array of column arrays
}

-(void)reloadData
{
	[self.tableView reloadData];
}

-(void)setColumns:(NSArray *)columnArray
{
	NSArray<NSTableColumn *> *oldColumns = [self.tableView tableColumns];
	NSInteger oldCount = (NSInteger)[oldColumns count];

    self.columnNames = columnArray;
	
	if(self.columnNames == NULL)
		return;

	NSUInteger newCount = [self.columnNames count];

	NSString *hiddenColumnName = @"omc_hidden_column";
	CGFloat defaultColumnWidth = 100.0;
	NSUInteger currColumnIndex = 0;
	NSTableColumn *prevTableColumn = NULL;
	for(NSUInteger newIndex = 0; newIndex < newCount; newIndex++)
	{
		id oneColumnTitle = [self.columnNames objectAtIndex:newIndex];
		if( ![oneColumnTitle isKindOfClass:[NSString class]] )
			oneColumnTitle = @"";
		
		//we skip hidden columns. ids are also skipped so the column id will be correct for next column and will point to right item in internal array
		if( ![hiddenColumnName isEqualToString:oneColumnTitle] )
		{
			NSNumber *columnIdentifier = [NSNumber numberWithUnsignedInteger:newIndex];
			
			NSTableColumn * oneTableColumn = NULL;
			if(currColumnIndex < oldCount)
			{//existing column
				oneTableColumn = [oldColumns objectAtIndex:currColumnIndex];
				[oneTableColumn setIdentifier:[columnIdentifier stringValue]];
			}
			else
			{//new column
				oneTableColumn = [[NSTableColumn alloc] initWithIdentifier:[columnIdentifier stringValue]];
				if( prevTableColumn != NULL)
				{//with settings from previous column
					NSTableHeaderCell *headerCell = [[prevTableColumn headerCell] copy];
					[oneTableColumn setHeaderCell: headerCell];
					NSCell *dataCell = [[prevTableColumn dataCell] copy];
					[oneTableColumn setDataCell:dataCell];
					[oneTableColumn setEditable: [prevTableColumn isEditable]];
					[oneTableColumn setResizingMask: [prevTableColumn resizingMask]];
				}
			}

			
			[oneTableColumn setWidth:defaultColumnWidth];//init width to some reasonable value
			NSTableHeaderCell *headerCell = [oneTableColumn headerCell];
			[headerCell setStringValue:oneColumnTitle];
			
			if(currColumnIndex >= oldCount)
				[self.tableView addTableColumn:oneTableColumn];
			prevTableColumn = oneTableColumn;
			currColumnIndex++;
		}
	}

	//currColumnIndex now holds the count of new columns
	//do not remove the last and only column so:
	if(currColumnIndex == 0)
		currColumnIndex = 1;

	//if there were more columns in the table in nib than we need at runtime, we remove the extras
	for(NSInteger i = (oldCount-1); i >= currColumnIndex; i--)
	{
		NSTableColumn * oneTableColumn = [oldColumns objectAtIndex:i];
		[self.tableView removeTableColumn:oneTableColumn];
	}

	if( self.columnWidths != nil )
	{//if column widths set before column names, populate widths now
		[self setColumnWidths:_columnWidths];
	}

}

-(void)setColumnWidths:(NSArray *)widthsArray
{
    _columnWidths = widthsArray;
	if(_columnWidths == nil)
		return;
	
	if( [_columnWidths count] == 0 )
		return;

	if(self.columnNames == nil) //column names not set yet, do not set widths
		return;

	NSUInteger columnNameCount = [self.columnNames count];
	NSString *hiddenColumnName = @"omc_hidden_column";

	NSUInteger columnWidthCount = [_columnWidths count];

	//limit to max number of columns already added
	if( columnWidthCount > columnNameCount )
		columnWidthCount = columnNameCount;

	for(NSUInteger i = 0; i < columnWidthCount; i++)
	{
		id oneColumnTitle = [self.columnNames objectAtIndex:i];
		if( ![oneColumnTitle isKindOfClass:[NSString class]] )
			oneColumnTitle = @"";
		
		//we skip hidden columns
		if( ![hiddenColumnName isEqualToString:oneColumnTitle] )
		{
			CGFloat columnWidth = 100.0;
			id oneColumnWidth = [_columnWidths objectAtIndex:i];
			if( [oneColumnWidth isKindOfClass:[NSString class]] )
			{
				columnWidth = [(NSString *)oneColumnWidth intValue];
				if(columnWidth < 0.0)
					columnWidth = 0.0;
				if(columnWidth > 10000.0)
					columnWidth = 10000.0;
			}
			NSNumber *columnIdentifier = [NSNumber numberWithUnsignedInteger:i];
			NSTableColumn * oneTableColumn = [self.tableView tableColumnWithIdentifier:[columnIdentifier stringValue]];
			if(oneTableColumn != NULL)
				[oneTableColumn setWidth:columnWidth];
		}
	}
}

-(NSArray *)splitRowString:(NSString *)inRowString
{
	NSArray *splitArray = NULL;
	if(mSeparator == kOMCColumnSeparatorTab)
	{
		splitArray = [inRowString componentsSeparatedByString:@"\t"];
	}
	else
	{
		printf("OMCDataBrowser::SplitRowString. splitting non tab-separated columns not supported yet\n");
	}
	return splitArray;
}

-(NSArray *)columnArrayForRow:(NSUInteger)inRowIndex
{
	if([self.rows count] == 0)
		return nil;

	NSArray *rowColumnsArray = nil;
	id oneRow = [self.rows objectAtIndex:inRowIndex];
	if( [oneRow isKindOfClass:[NSString class]] )
	{
		rowColumnsArray = [self splitRowString:oneRow];
		if(rowColumnsArray != nil)
		{
			[self.rows replaceObjectAtIndex:inRowIndex withObject:oneRow];
		}
	}
	else if( [oneRow isKindOfClass:[NSArray class]] )
	{
		rowColumnsArray = (NSArray *)oneRow;
	}
	return rowColumnsArray;
}

//NSTableDataSource/NSTableViewDataSource protocol
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [self.rows count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if( (self.rows == NULL) || (aTableColumn == NULL) )
		return @"";

	NSUInteger rowCount = [self.rows count];
	if(rowIndex >= rowCount)
		return @"";

	NSString *cellString = @"";
	NSArray *rowColumnsArray = [self columnArrayForRow:rowIndex];
	if(rowColumnsArray != NULL)
	{
		NSString *columnIdentifier = [aTableColumn identifier];
		NSUInteger columnIndex = (NSUInteger)[columnIdentifier integerValue];
		NSUInteger columnValuesCount = [rowColumnsArray count];
		if(columnIndex < columnValuesCount)
			cellString = [rowColumnsArray objectAtIndex:columnIndex];
	}

	return cellString;
}


//delegate methods:
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if( (self.dialogController != NULL) && (self.selectionChangeCommandID != NULL) )
	{
		[self.dialogController dispatchCommand:self.selectionChangeCommandID withContext:NULL];
	}
}

//this may return:
//	- a string value for single row selection or when inSelIterator is not NULL
//	or
//	- an array for multiple selections when inSelIterator is NULL

//inColumnIndex is 1-based
//if inColumnIndex = 0, this means combine the text from all columns (with optional prefix, separator and suffix set in the OMCTableView)

-(id)selectionValueForColumn:(NSInteger)inColumnIndex withIterator:(SelectionIterator *)inSelIterator
{
	NSString *colPrefix = NULL;
	NSString *colSuffix = NULL;
	NSString *colSeparator = NULL;

	if( [self.tableView isKindOfClass:[OMCTableView class]] )
	{
		OMCTableView *omcTableView  = (OMCTableView *)self.tableView;
		colPrefix = [omcTableView multipleColumnPrefix];
		colSuffix = [omcTableView multipleColumnSuffix];
		colSeparator = [omcTableView multipleColumnSeparator];
	}

	NSUInteger columnCount = [self.columnNames count];
	if(columnCount == 0)
		return NULL;

	NSUInteger currRow = 0;
	if( (inSelIterator != NULL) && SelectionIterator_IsValid(inSelIterator) )
	{
		currRow = SelectionIterator_GetCurrentSelection(inSelIterator);
	}
	else
	{
		NSIndexSet *indexSet = [self.tableView selectedRowIndexes];
		if(indexSet == NULL)
			return NULL;

		NSUInteger selectedRowsCount = [indexSet count];
		if(selectedRowsCount == 0)
			return NULL;
		
		if(selectedRowsCount == 1) 
		{//one row
			currRow = [indexSet firstIndex];
		}
		else
		{//more rows - we return an array of strings: OMC will know how to combine them for final result
			NSUInteger *selectedRows = (NSUInteger *)calloc(selectedRowsCount, sizeof(NSUInteger));//sel iterator takes ownership
			[indexSet getIndexes:selectedRows maxCount:selectedRowsCount inIndexRange:NULL];
			NSUInteger rowCount = [self.rows count];
			NSMutableArray *resultArray = [NSMutableArray array];
			for(NSUInteger i = 0; i < selectedRowsCount; i++)
			{
				NSUInteger oneRowIndex = selectedRows[i];
				NSString *rowString = NULL;
				if(oneRowIndex < rowCount)
					rowString = [self stringForRow:oneRowIndex column:inColumnIndex prefix:colPrefix suffix:colSuffix separator:colSeparator];
				if(rowString == NULL)
					rowString = @"";
				[resultArray addObject:rowString];
			}
			free(selectedRows);
			
			return resultArray;
		}
	}

	if( currRow < [self.rows count] )//single row case
		return [self stringForRow:currRow column:inColumnIndex prefix:colPrefix suffix:colSuffix separator:colSeparator];
	
	return NULL;
}



//this returns an array for all rows

//inColumnIndex is 1-based
//if inColumnIndex = 0, this means combine the text from all columns (with optional prefix, separator and suffix set in the OMCTableView)

-(NSArray *)allRowsForColumn:(NSInteger)inColumnIndex
{
	NSString *colPrefix = nil;
	NSString *colSuffix = nil;
	NSString *colSeparator = nil;

	if( [self.tableView isKindOfClass:[OMCTableView class]] )
	{
		OMCTableView *omcTableView  = (OMCTableView *)self.tableView;
		colPrefix = [omcTableView multipleColumnPrefix];
		colSuffix = [omcTableView multipleColumnSuffix];
		colSeparator = [omcTableView multipleColumnSeparator];
	}

	NSUInteger columnCount = [self.columnNames count];
	if(columnCount == 0)
		return nil;

	NSUInteger allRowsCount = [self.tableView numberOfRows];
	if(allRowsCount == 0)
		return nil;
	
	//we return an array of strings: OMC will know how to combine them for final result
	NSMutableArray *resultArray = [NSMutableArray array];
	for(NSUInteger i = 0; i < allRowsCount; i++)
	{
		NSString *rowString = [self stringForRow:i column:inColumnIndex prefix:colPrefix suffix:colSuffix separator:colSeparator];
		if(rowString == nil)
			rowString = @"";
		[resultArray addObject:rowString];
	}

	return resultArray;
}


//row index 0-based
//column index is 1-based with special value 0 meaning all columns
-(NSString *)stringForRow:(NSUInteger)inRow column:(NSUInteger)inColumnIndex prefix:(NSString *)colPrefix suffix:(NSString *)colSuffix separator:(NSString *)colSeparator
{
	NSUInteger columnCount = [self.columnNames count];//visible columns
	NSArray *rowColumnsArray = [self columnArrayForRow:inRow];
	NSUInteger currRowColumnCount = [rowColumnsArray count];
	//there might be more data columns than are visible. we allow access to all of them
	NSUInteger maxColumnCount = (columnCount > currRowColumnCount) ? columnCount : currRowColumnCount;
	if( inColumnIndex == 0 )
	{//all columns
		NSMutableString *combinedString = [NSMutableString string];
		for(NSUInteger colIndex = 0; colIndex < maxColumnCount; colIndex++)//column count determined by number of names
		{
			NSString *oneColumnValue = @"";
			if( colIndex < currRowColumnCount )//currRowColumnCount this may be less than preset column count
				oneColumnValue = [rowColumnsArray objectAtIndex:colIndex];
			
			if(colPrefix != NULL)
				[combinedString appendString:colPrefix];
			
			[combinedString appendString:oneColumnValue];
			
			if(colSuffix != NULL)
				[combinedString appendString:colSuffix];

			if( (colIndex+1) < maxColumnCount )//if there is a next value, we append separator (tab if no custom defined)
			{
				[combinedString appendString: (colSeparator != NULL) ? colSeparator : @"\t"];
			}
		}
		return combinedString;
	}
	else if((inColumnIndex-1) < maxColumnCount)
	{//single column
		NSString *oneColumnValue = @"";
		if( (inColumnIndex-1) < currRowColumnCount )
			oneColumnValue = [rowColumnsArray objectAtIndex:(inColumnIndex-1)];//1-based to 0-based
			
		if( (colPrefix != NULL) || (colSuffix != NULL) )//wrap the result with preffix and suffix
		{
			NSMutableString *combinedString = [NSMutableString string];
			if(colPrefix != NULL)
				[combinedString appendString:colPrefix];
			
			[combinedString appendString:oneColumnValue];
			
			if(colSuffix != NULL)
				[combinedString appendString:colSuffix];
			
			oneColumnValue = combinedString;
		}
		return oneColumnValue;
	}
	return NULL;
}

-(NSUInteger)columnCount
{
	NSUInteger columnCount = [self.columnNames count];//visible columns
	
	// The data may have more columns than just the visible ones
	// if the data is well formed each row of data has the same number of columns
	// it would be too expensive to go over all rows and check the max num of columns
	// it should be good enough to query just the first row
	NSArray *firstRowColumnsArray = [self columnArrayForRow:0];
	NSUInteger firstRowColumnCount = [firstRowColumnsArray count];
	//there might be more data columns than are visible. we allow access to all of them
	NSUInteger maxColumnCount = (columnCount > firstRowColumnCount) ? columnCount : firstRowColumnCount;
	return maxColumnCount;
}

@end

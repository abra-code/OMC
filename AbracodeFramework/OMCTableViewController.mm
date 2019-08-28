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
		mTableView = aTableView;
		[mTableView retain];
		mDialogController = inController;//do not retain, it owns us and retain would prevent its destruction
		mSelectionChangeCommandID = NULL;
		if( [mTableView isKindOfClass:[OMCTableView class]] )
		{
			OMCTableView *omcTableView  = (OMCTableView *)mTableView;
			mSelectionChangeCommandID = [omcTableView selectionCommandID];
			if(mSelectionChangeCommandID != NULL)
				[mSelectionChangeCommandID retain];
		}
		mRows = [[NSMutableArray alloc] init];
		mColumnNames = NULL;
		mColumnWidths = NULL;
	}
    return self;
}

- (void)dealloc
{
	[mTableView release];
	[mSelectionChangeCommandID release];
    [mRows release];
	[mColumnNames release];
	[mColumnWidths release];
	[super dealloc];
}

-(void)removeRows
{
	[mRows removeAllObjects];
	[mTableView reloadData];//inefficient if removeRows is followed by addRows
}

-(void)addRows:(CFArrayRef)inRowArray
{
	[mRows addObjectsFromArray:(NSArray *)inRowArray];//inRowArray is array of strings (unsplit) or array of column arrays
	[mTableView reloadData];
}

-(void)setColumns:(CFArrayRef)inColumnArray
{
	NSArray *oldColumns = [mTableView tableColumns];
	NSInteger oldCount = (NSInteger)[oldColumns count];

	NSArray *columnArray = (NSArray *)inColumnArray;
	if(columnArray != NULL)
		[columnArray retain];

	if(mColumnNames != NULL)
		[mColumnNames release];
	mColumnNames = columnArray;
	
	if(mColumnNames == NULL)
		return;

	NSUInteger newCount = [mColumnNames count];

	NSString *hiddenColumnName = @"omc_hidden_column";
	CGFloat defaultColumnWidth = 100.0;
	NSUInteger currColumnIndex = 0;
	NSTableColumn *prevTableColumn = NULL;
	for(NSUInteger newIndex = 0; newIndex < newCount; newIndex++)
	{
		id oneColumnTitle = [mColumnNames objectAtIndex:newIndex];
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
				oneTableColumn = [[[NSTableColumn alloc] initWithIdentifier:[columnIdentifier stringValue]] autorelease];
				if( prevTableColumn != NULL)
				{//with settings from previous column
					NSTableHeaderCell *headerCell = [[prevTableColumn headerCell] copy];
					[headerCell autorelease];
					[oneTableColumn setHeaderCell: headerCell];
					NSCell *dataCell = [[prevTableColumn dataCell] copy];
					[dataCell autorelease];
					[oneTableColumn setDataCell:dataCell];
					[oneTableColumn setEditable: [prevTableColumn isEditable]];
					[oneTableColumn setResizingMask: [prevTableColumn resizingMask]];
				}
			}

			
			[oneTableColumn setWidth:defaultColumnWidth];//init width to some reasonable value
			NSTableHeaderCell *headerCell = [oneTableColumn headerCell];
			[headerCell setStringValue:oneColumnTitle];
			
			if(currColumnIndex >= oldCount)
				[mTableView addTableColumn:oneTableColumn];
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
		[mTableView removeTableColumn:oneTableColumn];
	}

	if( mColumnWidths != NULL )
	{//if column widths set before column names, populate widths now
		[self setColumnWidths:(CFArrayRef)mColumnWidths];
	}

}

-(void)setColumnWidths:(CFArrayRef)inWidthsArray
{
	NSArray *widthsArray = (NSArray *)inWidthsArray;
	if(widthsArray != NULL)
		[widthsArray retain];
	
	if(mColumnWidths != NULL)
		[mColumnWidths release];

	mColumnWidths = widthsArray;
	if(mColumnWidths == NULL)
		return;
	
	if( [mColumnWidths count] == 0 )
		return;

	if(mColumnNames == NULL) //column names not set yet, do not set widths
		return;

	NSUInteger columnNameCount = [mColumnNames count];
	NSString *hiddenColumnName = @"omc_hidden_column";

	NSUInteger columnWidthCount = [mColumnWidths count];

	//limit to max number of columns already added
	if( columnWidthCount > columnNameCount )
		columnWidthCount = columnNameCount;

	for(NSUInteger i = 0; i < columnWidthCount; i++)
	{
		id oneColumnTitle = [mColumnNames objectAtIndex:i];
		if( ![oneColumnTitle isKindOfClass:[NSString class]] )
			oneColumnTitle = @"";
		
		//we skip hidden columns
		if( ![hiddenColumnName isEqualToString:oneColumnTitle] )
		{
			CGFloat columnWidth = 100.0;
			id oneColumnWidth = [mColumnWidths objectAtIndex:i];
			if( [oneColumnWidth isKindOfClass:[NSString class]] )
			{
				columnWidth = [(NSString *)oneColumnWidth intValue];
				if(columnWidth < 0.0)
					columnWidth = 0.0;
				if(columnWidth > 10000.0)
					columnWidth = 10000.0;
			}
			NSNumber *columnIdentifier = [NSNumber numberWithUnsignedInteger:i];
			NSTableColumn * oneTableColumn = [mTableView tableColumnWithIdentifier:[columnIdentifier stringValue]];
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
	if([mRows count] == 0)
		return nil;

	NSArray *rowColumnsArray = nil;
	id oneRow = [mRows objectAtIndex:inRowIndex];
	if( [oneRow isKindOfClass:[NSString class]] )
	{
		rowColumnsArray = [self splitRowString:oneRow];
		if(rowColumnsArray != nil)
		{
			[mRows replaceObjectAtIndex:inRowIndex withObject:oneRow];
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
	return [mRows count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if( (mRows == NULL) || (aTableColumn == NULL) )
		return @"";

	NSUInteger rowCount = [mRows count];
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
	if( (mDialogController != NULL) && (mSelectionChangeCommandID != NULL) )
	{
		[mDialogController dispatchCommand:mSelectionChangeCommandID withContext:NULL];
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

	if( [mTableView isKindOfClass:[OMCTableView class]] )
	{
		OMCTableView *omcTableView  = (OMCTableView *)mTableView;
		colPrefix = [omcTableView multipleColumnPrefix];
		colSuffix = [omcTableView multipleColumnSuffix];
		colSeparator = [omcTableView multipleColumnSeparator];
	}

	NSUInteger columnCount = [mColumnNames count];
	if(columnCount == 0)
		return NULL;

	NSUInteger currRow = 0;
	if( (inSelIterator != NULL) && SelectionIterator_IsValid(inSelIterator) )
	{
		currRow = SelectionIterator_GetCurrentSelection(inSelIterator);
	}
	else
	{
		NSIndexSet *indexSet = [mTableView selectedRowIndexes];
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
			NSUInteger rowCount = [mRows count];
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

	if( currRow < [mRows count] )//single row case
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

	if( [mTableView isKindOfClass:[OMCTableView class]] )
	{
		OMCTableView *omcTableView  = (OMCTableView *)mTableView;
		colPrefix = [omcTableView multipleColumnPrefix];
		colSuffix = [omcTableView multipleColumnSuffix];
		colSeparator = [omcTableView multipleColumnSeparator];
	}

	NSUInteger columnCount = [mColumnNames count];
	if(columnCount == 0)
		return nil;

	NSUInteger allRowsCount = [mTableView numberOfRows];
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
	NSUInteger columnCount = [mColumnNames count];//visible columns
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
	NSUInteger columnCount = [mColumnNames count];//visible columns
	
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

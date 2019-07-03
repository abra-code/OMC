/*
 *  SelectionIterator.h
 *  Abracode
 *
 *  Created by Tomasz Kukielka on 10/1/09.
 *  Copyright 2009-2010 Abracode. All rights reserved.
 *
 */

#ifndef _SelectionIterator_h_
	#define _SelectionIterator_h_

//new iterator starts at first valid item. Calling Next() will move to next selection
typedef struct SelectionIterator
{
	unsigned long		*mSelectedRows;
	unsigned long		mSelCount; //the number of items in mSelectedRows
	unsigned long		mCurrSelIndex;//index into mSelectedRows
} SelectionIterator;

//inSelRows must be allocated with malloc. we take ownership of it here and will release with iterator
static inline SelectionIterator *SelectionIterator_Create(unsigned long *inSelRows, size_t inCount)
{
	SelectionIterator *outIterator = (SelectionIterator *)calloc(1, sizeof(SelectionIterator));
	outIterator->mSelectedRows = inSelRows;
	outIterator->mSelCount = inCount;
	return outIterator;
}

static inline SelectionIterator * AllRowsIterator_Create()
{
	SelectionIterator *outIterator = (SelectionIterator *)calloc(1, sizeof(SelectionIterator));
	outIterator->mSelectedRows = NULL;
	outIterator->mSelCount = (unsigned long)-1;
	outIterator->mCurrSelIndex = (unsigned long)-1;
	return outIterator;
}

static inline void SelectionIterator_Release(SelectionIterator *inIterator)
{
	if(inIterator != NULL)
	{
		if( inIterator->mSelectedRows != NULL )
			free(inIterator->mSelectedRows);
		free(inIterator);
	}
}

static inline Boolean SelectionIterator_IsValid(SelectionIterator *inIterator)
{
	return ((inIterator->mSelectedRows != NULL) && (inIterator->mCurrSelIndex < inIterator->mSelCount));
}

static inline Boolean SelectionIterator_IsAllRows(SelectionIterator *inIterator)
{
	return ((inIterator->mSelectedRows == NULL) && (inIterator->mCurrSelIndex == (unsigned long)-1) && (inIterator->mCurrSelIndex == (unsigned long)-1) );
}

static inline Boolean SelectionIterator_Next(SelectionIterator *inIterator)
{
	inIterator->mCurrSelIndex++;
	return SelectionIterator_IsValid(inIterator);
}

//no bounds check here, caller must make sure the iterator is valid
static inline unsigned long SelectionIterator_GetCurrentSelection(SelectionIterator *inIterator)
{
	return inIterator->mSelectedRows[inIterator->mCurrSelIndex];
}

#endif //_SelectionIterator_h_
